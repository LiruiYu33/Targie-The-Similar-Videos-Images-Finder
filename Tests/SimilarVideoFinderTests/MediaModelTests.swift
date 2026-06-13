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

import XCTest
@testable import SimilarVideoFinder

/// Task 1: Media-Neutral Domain Types
/// 验证 `MediaKind`, `ScanMode`, `MediaItem`, 以及 `SimilarityGroup` 拒绝混合媒介。
final class MediaModelTests: XCTestCase {

    // MARK: - MediaKind

    func testMediaKindRawValues() {
        XCTAssertEqual(MediaKind.video.rawValue, "video")
        XCTAssertEqual(MediaKind.image.rawValue, "image")
    }

    func testMediaKindIsCodable() throws {
        let encoded = try JSONEncoder().encode(MediaKind.image)
        let decoded = try JSONDecoder().decode(MediaKind.self, from: encoded)
        XCTAssertEqual(decoded, .image)
    }

    // MARK: - ScanMode

    func testScanModeAllCases() {
        XCTAssertEqual(Set(ScanMode.allCases), [.videos, .images, .all])
    }

    func testScanModeRawValueRoundTrip() {
        XCTAssertEqual(ScanMode(rawValue: "videos"), .videos)
        XCTAssertEqual(ScanMode(rawValue: "images"), .images)
        XCTAssertEqual(ScanMode(rawValue: "all"), .all)
        XCTAssertNil(ScanMode(rawValue: "garbage"))
    }

    func testScanModeIdentifiableId() {
        XCTAssertEqual(ScanMode.videos.id, "videos")
    }

    // MARK: - MediaItem

    func testImageMediaItemHasNoDuration() {
        let item = MediaItem(
            kind: .image,
            url: URL(fileURLWithPath: "/tmp/a.png"),
            fileSize: 1024,
            duration: nil,
            width: 800,
            height: 600,
            modifiedAt: nil,
            thumbnailData: nil
        )
        XCTAssertEqual(item.kind, .image)
        XCTAssertNil(item.duration)
    }

    func testVideoMediaItemHasDuration() {
        let item = MediaItem(
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/a.mov"),
            fileSize: 1024,
            duration: 60,
            width: 1920,
            height: 1080,
            modifiedAt: nil,
            thumbnailData: nil
        )
        XCTAssertEqual(item.kind, .video)
        XCTAssertEqual(item.duration, 60)
    }

    func testFilenameProperty() {
        let item = MediaItem(
            kind: .image,
            url: URL(fileURLWithPath: "/tmp/sub/photo.jpg"),
            fileSize: 1,
            duration: nil,
            width: 1, height: 1,
            modifiedAt: nil, thumbnailData: nil
        )
        XCTAssertEqual(item.filename, "photo.jpg")
    }

    // MARK: - SimilarityGroup uses items, rejects mixed kinds

    func testSimilarityGroupExposesItems() {
        let a = makeItem(kind: .image)
        let b = makeItem(kind: .image)
        let group = SimilarityGroup(items: [a, b], relations: [])
        XCTAssertEqual(group.items.count, 2)
    }

    func testSimilarityGroupKindReflectsItems() {
        let a = makeItem(kind: .video)
        let b = makeItem(kind: .video)
        let group = SimilarityGroup(items: [a, b], relations: [])
        XCTAssertEqual(group.kind, .video)
    }

    /// 关键约束: Images and videos must never appear in the same `SimilarityGroup`.
    func testMakeRejectsMixedKinds() {
        let v = makeItem(kind: .video)
        let i = makeItem(kind: .image)
        XCTAssertNil(SimilarityGroup.make(items: [v, i], relations: []))
    }

    func testMakeAcceptsHomogeneousImages() {
        let a = makeItem(kind: .image)
        let b = makeItem(kind: .image)
        let group = SimilarityGroup.make(items: [a, b], relations: [])
        XCTAssertNotNil(group)
        XCTAssertEqual(group?.kind, .image)
    }

    // MARK: - Helpers

    private func makeItem(kind: MediaKind, name: String = "f") -> MediaItem {
        MediaItem(
            kind: kind,
            url: URL(fileURLWithPath: "/tmp/\(name)-\(UUID().uuidString)"),
            fileSize: 1,
            duration: kind == .video ? 60 : nil,
            width: 100,
            height: 100,
            modifiedAt: nil,
            thumbnailData: nil
        )
    }
}
