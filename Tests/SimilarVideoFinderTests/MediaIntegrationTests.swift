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

final class MediaIntegrationTests: XCTestCase {
    func testRealVideoScanAndExactDuplicateGrouping() async throws {
        let ffmpeg = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        guard FileManager.default.isExecutableFile(atPath: ffmpeg.path) else {
            throw XCTSkip("ffmpeg is unavailable")
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("sample.mp4")
        let duplicate = root.appendingPathComponent("sample copy.mp4")

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=size=320x180:rate=12",
            "-t", "1", "-pix_fmt", "yuv420p", "-y", original.path
        ]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        try FileManager.default.copyItem(at: original, to: duplicate)

        let scan = try await VideoScanner().scan(folder: root) { _ in }
        XCTAssertEqual(scan.videos.count, 2)
        XCTAssertTrue(scan.issues.isEmpty)

        let result = try await SimilarityPipeline().process(videos: scan.videos, threshold: 0.88) { _ in }
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].items.count, 2)
        XCTAssertEqual(result.groups[0].maximumScore, 1)
    }
}
