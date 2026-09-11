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
        // Real changes during the read must retain sub-millisecond precision.
        XCTAssertFalse(FileHasher.shouldCacheSHA256(
            originalSize: 100, originalModifiedAt: originalMtime,
            currentSize: 100, currentModifiedAt: originalMtime.addingTimeInterval(0.0004)
        ))
    }

    func testCacheAwareHashRefreshesAttributesOfReusedURL() async throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = InMemoryHashCache()
        _ = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let original = try await FileHasher.sha256(of: url, cache: cache)

        try Data("BBBB".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 6_000)],
            ofItemAtPath: url.path
        )

        let refreshed = try await FileHasher.sha256(of: url, cache: cache)
        let direct = try await FileHasher.sha256(of: url)
        XCTAssertNotEqual(refreshed, original)
        XCTAssertEqual(refreshed, direct)
    }

    func testCacheLookupChangeRejectsBothHitsAndMisses() async throws {
        for cachedDigest in [String?.some("old-digest"), nil] {
            let url = try makeFixture()
            defer { try? FileManager.default.removeItem(at: url) }
            let cache = HashLookupProbe(result: cachedDigest) {
                try? Data("BBBB".utf8).write(to: url)
                try? FileManager.default.setAttributes(
                    [.modificationDate: Date(timeIntervalSince1970: 6_000)],
                    ofItemAtPath: url.path
                )
            }

            do {
                _ = try await FileHasher.sha256(of: url, cache: cache)
                XCTFail("A changed source must not return a cached or newly computed digest")
            } catch {
                XCTAssertEqual(error as? FileHashError, .fileChangedDuringRead)
            }
            let writes = await cache.writeCount
            XCTAssertEqual(writes, 0)
        }
    }

    func testChangeDuringChunkReadRejectsDigestWithAndWithoutCache() async throws {
        let cache = HashLookupProbe(result: nil)
        for selectedCache: (any HashCaching)? in [nil, cache] {
            let url = try makeFixture()
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                _ = try await FileHasher.sha256(of: url, mediaKind: .video, cache: selectedCache) {
                    try Data("BBBB".utf8).write(to: url)
                    // The change is smaller than persisted cache precision,
                    // but must still invalidate this live read.
                    try FileManager.default.setAttributes(
                        [.modificationDate: Date(timeIntervalSince1970: 5_000.0004)],
                        ofItemAtPath: url.path
                    )
                }
                XCTFail("A digest for content changed during reading must be rejected")
            } catch {
                XCTAssertEqual(error as? FileHashError, .fileChangedDuringRead)
            }
        }
        let writes = await cache.writeCount
        XCTAssertEqual(writes, 0)
    }

    func testAlreadyCancelledCacheAwareHashDoesNotQueryCache() async throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = HashLookupProbe(result: "cached")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FileHasher.sha256(of: url, cache: cache)
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled task must not return a cached digest")
        } catch is CancellationError {
            // Expected.
        }
        let lookups = await cache.lookupCount
        XCTAssertEqual(lookups, 0)
    }

    func testCancellationWhileCacheLookupIsPendingDoesNotReturnDigest() async throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let entered = expectation(description: "cache lookup entered")
        let gate = HashReadGate()
        let cache = HashLookupProbe(result: "cached") {
            entered.fulfill()
            await gate.wait()
        }
        let task = Task { try await FileHasher.sha256(of: url, cache: cache) }
        await fulfillment(of: [entered], timeout: 5)
        task.cancel()
        await gate.release()
        do {
            _ = try await task.value
            XCTFail("A cancelled cache hit must not return a digest")
        } catch is CancellationError {
            // Expected.
        }
        let writes = await cache.writeCount
        XCTAssertEqual(writes, 0)
    }

    func testCancellationDuringChunkReadDoesNotCacheDigest() async throws {
        let url = try makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let entered = expectation(description: "first chunk read")
        let gate = HashReadGate()
        let cache = HashLookupProbe(result: nil)
        let task = Task {
            try await FileHasher.sha256(of: url, mediaKind: .video, cache: cache) {
                entered.fulfill()
                await gate.wait()
            }
        }
        await fulfillment(of: [entered], timeout: 5)
        task.cancel()
        await gate.release()
        do {
            _ = try await task.value
            XCTFail("A cancelled read must not return a digest")
        } catch is CancellationError {
            // Expected.
        }
        let writes = await cache.writeCount
        XCTAssertEqual(writes, 0)
    }

    private func makeFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FileHasher-\(UUID().uuidString).bin")
        try Data("AAAA".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 5_000)],
            ofItemAtPath: url.path
        )
        return url
    }
}

private actor HashLookupProbe: HashCaching {
    private let result: String?
    private let onLookup: @Sendable () async -> Void
    private(set) var lookupCount = 0
    private(set) var writeCount = 0

    init(result: String?, onLookup: @escaping @Sendable () async -> Void = {}) {
        self.result = result
        self.onLookup = onLookup
    }

    func lookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, algorithmVersion: String) -> CacheRecord? { nil }
    func upsert(_ record: CacheRecord) {}
    func pruneStale(validPaths: Set<String>) {}
    func count() -> Int { 0 }
    func clearAll() {}
    func sizeInBytes() -> Int64 { 0 }

    func lookupSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) async -> String? {
        lookupCount += 1
        await onLookup()
        return result
    }

    func upsertSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, sha256: String) {
        writeCount += 1
    }
}

private actor HashReadGate {
    private var isReleased = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}
