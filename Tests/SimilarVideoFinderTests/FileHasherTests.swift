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

    /// A cache-aware hash is stored when the file is unchanged across the read.
    func testCacheAwareHashIsStoredForStableFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("stable.bin")
        try Data("stable-content".utf8).write(to: url)
        let cache = InMemoryHashCache()

        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        _ = try await FileHasher.sha256(of: url, mediaKind: .video, cache: cache)

        let cached = await cache.lookupSHA256(
            filePath: url.path,
            fileSize: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate,
            mediaKind: .video
        )
        XCTAssertNotNil(cached)
    }

    /// If the file's modification date changes during hashing, the result must
    /// not be cached under the stale pre-read attributes - otherwise a later
    /// lookup at those attributes would return a hash for different content.
    /// The decision is unit-tested deterministically (the slow real-file
    /// version races the kernel scheduler and is flaky).
    func testChangedAttributesDuringHashingAreNotCached() {
        let originalMtime = Date(timeIntervalSince1970: 1_000)
        let bumpedMtime = originalMtime.addingTimeInterval(60)

        // Unchanged attributes -> safe to cache.
        XCTAssertTrue(FileHasher.shouldCacheSHA256(
            originalSize: 100, originalModifiedAt: originalMtime,
            currentSize: 100, currentModifiedAt: originalMtime
        ))
        // Size changed -> must not cache.
        XCTAssertFalse(FileHasher.shouldCacheSHA256(
            originalSize: 100, originalModifiedAt: originalMtime,
            currentSize: 101, currentModifiedAt: originalMtime
        ))
        // Modification date changed -> must not cache.
        XCTAssertFalse(FileHasher.shouldCacheSHA256(
            originalSize: 100, originalModifiedAt: originalMtime,
            currentSize: 100, currentModifiedAt: bumpedMtime
        ))
        // Dates that differ by sub-millisecond noise are treated as unchanged.
        XCTAssertTrue(FileHasher.shouldCacheSHA256(
            originalSize: 100, originalModifiedAt: originalMtime,
            currentSize: 100, currentModifiedAt: originalMtime.addingTimeInterval(0.0004)
        ))
    }
}
