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

final class DeletionServiceTests: XCTestCase {
    func testPermanentDeleteRemovesTemporaryFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("delete me".utf8).write(to: url)
        try await DeletionService().delete(url: url, mode: .permanent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testMissingFileReturnsTypedError() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try await DeletionService().delete(url: url, mode: .permanent)
            XCTFail("Expected missing file error")
        } catch let error as DeletionError {
            XCTAssertEqual(error, .fileMissing)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testDeleteOperationRunsOffMainThread() async throws {
        let recorder = ThreadRecorder()
        let service = DeletionService { _, _ in
            recorder.recordCurrentThread()
        }

        try await service.delete(
            url: URL(fileURLWithPath: "/tmp/background-delete-test"),
            mode: .permanent
        )

        XCTAssertEqual(recorder.wasMainThread, false)
    }
}

private final class ThreadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool?

    var wasMainThread: Bool? {
        lock.withLock { value }
    }

    func recordCurrentThread() {
        lock.withLock { value = Thread.isMainThread }
    }
}
