// Targie — Find similar videos on macOS.
// Copyright (C) 2026 Lirui Yu
//
// This file is part of Targie.
//
// Targie is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Targie is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Targie.  If not, see <https://www.gnu.org/licenses/>.
//
// If you reuse this code (modified or not), you must keep this notice
// and credit the original author (Lirui Yu).

import XCTest
@testable import SimilarVideoFinder

final class QuickPrehasherTests: XCTestCase {

    // MARK: - Bucket Tests

    func testDurationBucketIsZeroForZero() {
        XCTAssertEqual(QuickPrehasher.durationBucket(0), 0)
    }

    func testDurationBucketsForCloseDurationsMatch() {
        // 60s 和 63s 应在同一/相邻桶 (5% 容差)
        let b60 = QuickPrehasher.durationBucket(60)
        let b63 = QuickPrehasher.durationBucket(63)
        XCTAssertLessThanOrEqual(abs(b60 - b63), 1)
    }

    func testDurationBucketsForVeryDifferentDurationsDiverge() {
        let b10 = QuickPrehasher.durationBucket(10)
        let b1000 = QuickPrehasher.durationBucket(1000)
        XCTAssertGreaterThan(abs(b10 - b1000), 5)
    }

    func testSizeBucketIsZeroForZero() {
        XCTAssertEqual(QuickPrehasher.sizeBucket(0), 0)
    }

    func testSizeBucketsForCloseSizesMatch() {
        // 10MB 和 11MB 应在同/相邻桶
        let b10mb = QuickPrehasher.sizeBucket(10 * 1024 * 1024)
        let b11mb = QuickPrehasher.sizeBucket(11 * 1024 * 1024)
        XCTAssertLessThanOrEqual(abs(b10mb - b11mb), 1)
    }

    func testAspectBucketsFor16x9And16x9Match() {
        let b1 = QuickPrehasher.aspectBucket(width: 1920, height: 1080)
        let b2 = QuickPrehasher.aspectBucket(width: 3840, height: 2160)  // same aspect, 4K
        XCTAssertEqual(b1, b2)
    }

    func testAspectBucketDistinguishes16x9From4x3() {
        let b169 = QuickPrehasher.aspectBucket(width: 1920, height: 1080)
        let b43 = QuickPrehasher.aspectBucket(width: 1024, height: 768)
        XCTAssertNotEqual(b169, b43)
    }

    // MARK: - Compatibility Tests

    func testCompatibleWithNearlyIdenticalPrehashes() {
        let a = QuickPrehash(
            videoID: UUID(),
            durationBucket: 80,
            sizeBucket: 60,
            aspectBucket: 59,
            thumbnailMean: 128,
            thumbnailVariance: 1000
        )
        let b = QuickPrehash(
            videoID: UUID(),
            durationBucket: 81,
            sizeBucket: 61,
            aspectBucket: 60,
            thumbnailMean: 130,
            thumbnailVariance: 1100
        )
        XCTAssertTrue(a.isCompatible(with: b))
    }

    func testNotCompatibleWithVeryDifferentDurations() {
        let a = QuickPrehash(
            videoID: UUID(), durationBucket: 50, sizeBucket: 60,
            aspectBucket: 59, thumbnailMean: 128, thumbnailVariance: 1000
        )
        let b = QuickPrehash(
            videoID: UUID(), durationBucket: 100, sizeBucket: 60,
            aspectBucket: 59, thumbnailMean: 128, thumbnailVariance: 1000
        )
        XCTAssertFalse(a.isCompatible(with: b))
    }

    func testNotCompatibleWithVeryDifferentAspects() {
        let a = QuickPrehash(
            videoID: UUID(), durationBucket: 80, sizeBucket: 60,
            aspectBucket: 33, thumbnailMean: 128, thumbnailVariance: 1000
        )
        let b = QuickPrehash(
            videoID: UUID(), durationBucket: 80, sizeBucket: 60,
            aspectBucket: 60, thumbnailMean: 128, thumbnailVariance: 1000
        )
        XCTAssertFalse(a.isCompatible(with: b))
    }

    func testNotCompatibleWithVeryDifferentThumbnails() {
        let a = QuickPrehash(
            videoID: UUID(), durationBucket: 80, sizeBucket: 60,
            aspectBucket: 59, thumbnailMean: 30, thumbnailVariance: 1000
        )
        let b = QuickPrehash(
            videoID: UUID(), durationBucket: 80, sizeBucket: 60,
            aspectBucket: 59, thumbnailMean: 200, thumbnailVariance: 1000
        )
        XCTAssertFalse(a.isCompatible(with: b))
    }

    // MARK: - Prehash from MediaItem

    func testPrehashFromVideoItemWithoutThumbnail() {
        let video = MediaItem(
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/test.mp4"),
            fileSize: 10 * 1024 * 1024,
            duration: 60,
            width: 1920,
            height: 1080,
            modifiedAt: nil,
            thumbnailData: nil
        )
        let pre = QuickPrehasher.prehash(for: video)
        // 没有缩略图时使用中性值
        XCTAssertEqual(pre.thumbnailMean, 128)
        XCTAssertEqual(pre.thumbnailVariance, 0)
        // 元数据桶应正常计算
        XCTAssertGreaterThan(pre.durationBucket, 0)
        XCTAssertGreaterThan(pre.sizeBucket, 0)
        XCTAssertGreaterThan(pre.aspectBucket, 0)
    }

    func testPrehashIsDeterministicForSameVideo() {
        let video = MediaItem(
            id: UUID(),
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/test.mp4"),
            fileSize: 10 * 1024 * 1024,
            duration: 60,
            width: 1920,
            height: 1080,
            modifiedAt: nil,
            thumbnailData: nil
        )
        let p1 = QuickPrehasher.prehash(for: video)
        let p2 = QuickPrehasher.prehash(for: video)
        XCTAssertEqual(p1, p2)
    }
}
