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

final class VideoScannerTests: XCTestCase {
    func testDiscoversSupportedVideosRecursivelyInStableOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for path in ["b.mov", "nested/a.mp4", "nested/c.M4V", "notes.txt"] {
            let url = root.appendingPathComponent(path)
            try Data("fixture".utf8).write(to: url)
        }

        let found = try VideoScanner.discoverVideoURLs(in: root)
        XCTAssertEqual(found.map(\.lastPathComponent), ["b.mov", "a.mp4", "c.M4V"])
    }

    func testScanLoadsMetadataConcurrentlyAndKeepsStableOrder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["c.mp4", "a.mp4", "b.mp4"] {
            try Data().write(to: root.appendingPathComponent(name))
        }

        let tracker = LoadConcurrencyTracker()
        let scanner = VideoScanner(maxConcurrentLoads: 3) { url in
            await tracker.started()
            try await Task.sleep(for: .milliseconds(40))
            await tracker.finished()
            return VideoItem(
                url: url,
                fileSize: 1,
                duration: 1,
                width: 1,
                height: 1,
                modifiedAt: nil,
                thumbnailData: nil
            )
        }

        let result = try await scanner.scan(folder: root) { _ in }

        XCTAssertEqual(result.videos.map(\.filename), ["a.mp4", "b.mp4", "c.mp4"])
        let maximum = await tracker.maximum
        XCTAssertGreaterThan(maximum, 1)
        XCTAssertLessThanOrEqual(maximum, 3)
    }
}

private actor LoadConcurrencyTracker {
    private(set) var current = 0
    private(set) var maximum = 0

    func started() {
        current += 1
        maximum = max(maximum, current)
    }

    func finished() {
        current -= 1
    }
}
