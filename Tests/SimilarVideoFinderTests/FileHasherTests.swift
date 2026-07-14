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

final class FileHasherTests: XCTestCase {
    func testIdenticalFilesHaveSameDigestAndChangedBytesDiffer() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("one.bin")
        let second = root.appendingPathComponent("two.bin")
        let third = root.appendingPathComponent("three.bin")
        try Data("same".utf8).write(to: first)
        try Data("same".utf8).write(to: second)
        try Data("different".utf8).write(to: third)

        let a = try await FileHasher.sha256(of: first)
        let b = try await FileHasher.sha256(of: second)
        let c = try await FileHasher.sha256(of: third)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testAlreadyCancelledHashDoesNotStartDetachedWork() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CancelledHash-\(UUID().uuidString).bin")
        try Data("payload".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FileHasher.sha256(of: url)
        }

        do {
            _ = try await task.value
            XCTFail("A cancelled hash operation should throw")
        } catch is CancellationError {
            // Expected.
        }
    }
}
