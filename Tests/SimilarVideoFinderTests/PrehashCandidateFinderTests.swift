// Targie - Find similar videos on macOS.
// Copyright (C) 2026 Lirui Yu

import XCTest
@testable import SimilarVideoFinder

final class PrehashCandidateFinderTests: XCTestCase {
    func testFindsRenamedResizedVideoDespiteEightfoldEncodedSizeDifference() {
        let first = makeVideo(name: "camera-original.mp4", fileSize: 8_000_000, width: 1920, height: 1080)
        let second = makeVideo(name: "received-message.mov", fileSize: 1_000_000, width: 960, height: 540)
        let firstPrehash = QuickPrehasher.prehash(for: first)
        let secondPrehash = QuickPrehasher.prehash(for: second)
        XCTAssertNotEqual(FilenameNormalizer.normalize(first.filename), FilenameNormalizer.normalize(second.filename))
        XCTAssertGreaterThan(abs(firstPrehash.sizeBucket - secondPrehash.sizeBucket), 3)
        let result = PrehashCandidateFinder.find(
            videos: [first, second],
            prehashes: [first.id: firstPrehash, second.id: secondPrehash]
        )

        XCTAssertEqual(result.pairs.count, 1, "An encoding-size change must not prevent visual comparison of renamed copies.")
        XCTAssertEqual(result.compatibilityChecks, 1)
    }

    func testFindsCompatibleVideosAcrossNeighboringBuckets() {
        let first = makeVideo(name: "first.mp4")
        let second = makeVideo(name: "second.mp4")
        let prehashes = [
            first.id: makePrehash(id: first.id, duration: 80, size: 60, aspect: 59, mean: 120),
            second.id: makePrehash(id: second.id, duration: 82, size: 63, aspect: 61, mean: 150)
        ]

        let result = PrehashCandidateFinder.find(videos: [first, second], prehashes: prehashes)

        XCTAssertEqual(result.pairs.count, 1)
    }

    func testFindsNormalizedNameMatchOutsideCompatibleBuckets() {
        let first = makeVideo(name: "Holiday copy.mp4")
        let second = makeVideo(name: "Holiday export.mov")
        let prehashes = [
            first.id: makePrehash(id: first.id, duration: 10, size: 10, aspect: 10, mean: 10),
            second.id: makePrehash(id: second.id, duration: 100, size: 100, aspect: 100, mean: 220)
        ]

        let result = PrehashCandidateFinder.find(videos: [first, second], prehashes: prehashes)

        XCTAssertEqual(result.pairs.count, 1)
    }

    func testSparseBucketsAvoidQuadraticCompatibilityChecks() {
        let videos = (0..<1_000).map { makeVideo(name: "video-\($0)x.mp4") }
        let prehashes = Dictionary(uniqueKeysWithValues: videos.enumerated().map { index, video in
            (video.id, makePrehash(id: video.id, duration: index * 10, size: index * 10, aspect: index * 10, mean: 128))
        })

        let result = PrehashCandidateFinder.find(videos: videos, prehashes: prehashes)

        XCTAssertEqual(result.pairs.count, 0)
        XCTAssertLessThan(result.compatibilityChecks, 5_000)
    }

    private func makeVideo(name: String, fileSize: Int64 = 1, width: Int = 1, height: Int = 1) -> MediaItem {
        MediaItem(
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            fileSize: fileSize,
            duration: 1,
            width: width,
            height: height,
            modifiedAt: nil,
            thumbnailData: nil
        )
    }

    private func makePrehash(id: UUID, duration: Int, size: Int, aspect: Int, mean: UInt8) -> QuickPrehash {
        QuickPrehash(
            videoID: id,
            durationBucket: duration,
            sizeBucket: size,
            aspectBucket: aspect,
            thumbnailMean: mean,
            thumbnailVariance: 0
        )
    }
}
