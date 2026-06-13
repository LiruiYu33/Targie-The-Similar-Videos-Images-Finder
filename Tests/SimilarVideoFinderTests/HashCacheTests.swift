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

final class HashCacheTests: XCTestCase {

    private var tempDir: URL!
    private var dbURL: URL!
    private var cache: HashCache!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HashCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbURL = tempDir.appendingPathComponent("test.sqlite")
        cache = try HashCache(databaseURL: dbURL)
    }

    override func tearDown() async throws {
        cache = nil
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Basic CRUD

    func testEmptyCacheReturnsNothing() async {
        let result = await cache.lookup(filePath: "/tmp/foo.mp4", fileSize: 100, modifiedAt: nil)
        XCTAssertNil(result)
    }

    func testInsertAndRetrieve() async {
        let record = makeRecord(path: "/tmp/foo.mp4", size: 100, date: Date(timeIntervalSince1970: 1000))
        await cache.upsert(record)

        let retrieved = await cache.lookup(
            filePath: "/tmp/foo.mp4",
            fileSize: 100,
            modifiedAt: Date(timeIntervalSince1970: 1000)
        )
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.filePath, "/tmp/foo.mp4")
        XCTAssertEqual(retrieved?.fileSize, 100)
    }

    func testInsertOverwritesExisting() async {
        let original = makeRecord(path: "/tmp/foo.mp4", size: 100, date: Date(timeIntervalSince1970: 1000))
        await cache.upsert(original)

        let updated = makeRecord(path: "/tmp/foo.mp4", size: 200, date: Date(timeIntervalSince1970: 2000))
        await cache.upsert(updated)

        let count = await cache.count()
        XCTAssertEqual(count, 1)

        let retrieved = await cache.lookup(
            filePath: "/tmp/foo.mp4",
            fileSize: 200,
            modifiedAt: Date(timeIntervalSince1970: 2000)
        )
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.fileSize, 200)
    }

    // MARK: - Cache Validation

    func testLookupFailsWhenSizeChanged() async {
        let record = makeRecord(path: "/tmp/foo.mp4", size: 100, date: Date(timeIntervalSince1970: 1000))
        await cache.upsert(record)

        // 文件大小变了 → 缓存失效
        let result = await cache.lookup(
            filePath: "/tmp/foo.mp4",
            fileSize: 200,
            modifiedAt: Date(timeIntervalSince1970: 1000)
        )
        XCTAssertNil(result)
    }

    func testLookupFailsWhenModificationDateChanged() async {
        let record = makeRecord(path: "/tmp/foo.mp4", size: 100, date: Date(timeIntervalSince1970: 1000))
        await cache.upsert(record)

        // 修改时间变了 → 缓存失效
        let result = await cache.lookup(
            filePath: "/tmp/foo.mp4",
            fileSize: 100,
            modifiedAt: Date(timeIntervalSince1970: 2000)
        )
        XCTAssertNil(result)
    }

    func testLookupAcceptsTinyDateDifferences() async {
        let record = makeRecord(path: "/tmp/foo.mp4", size: 100, date: Date(timeIntervalSince1970: 1000))
        await cache.upsert(record)

        // 时间差 < 1秒 → 视为有效
        let result = await cache.lookup(
            filePath: "/tmp/foo.mp4",
            fileSize: 100,
            modifiedAt: Date(timeIntervalSince1970: 1000.5)
        )
        XCTAssertNotNil(result)
    }

    // MARK: - Pruning

    func testPruneStaleRemovesNonValidEntries() async {
        await cache.upsert(makeRecord(path: "/tmp/a.mp4", size: 1, date: nil))
        await cache.upsert(makeRecord(path: "/tmp/b.mp4", size: 2, date: nil))
        await cache.upsert(makeRecord(path: "/tmp/c.mp4", size: 3, date: nil))

        let initialCount = await cache.count()
        XCTAssertEqual(initialCount, 3)

        await cache.pruneStale(validPaths: ["/tmp/a.mp4", "/tmp/c.mp4"])

        let finalCount = await cache.count()
        XCTAssertEqual(finalCount, 2)

        let removed = await cache.lookup(filePath: "/tmp/b.mp4", fileSize: 2, modifiedAt: nil)
        XCTAssertNil(removed)
    }

    func testPruneStaleEmptyValidPathsRemovesAll() async {
        await cache.upsert(makeRecord(path: "/tmp/a.mp4", size: 1, date: nil))
        await cache.upsert(makeRecord(path: "/tmp/b.mp4", size: 2, date: nil))

        await cache.pruneStale(validPaths: [])

        let finalCount = await cache.count()
        XCTAssertEqual(finalCount, 0)
    }

    // MARK: - Persistence Across Instances

    func testCachePersistsAcrossDatabaseConnections() async throws {
        let record = makeRecord(path: "/tmp/foo.mp4", size: 100, date: Date(timeIntervalSince1970: 1000))
        await cache.upsert(record)

        // 重新打开同一数据库
        cache = nil
        cache = try HashCache(databaseURL: dbURL)

        let retrieved = await cache.lookup(
            filePath: "/tmp/foo.mp4",
            fileSize: 100,
            modifiedAt: Date(timeIntervalSince1970: 1000)
        )
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.filePath, "/tmp/foo.mp4")
    }

    // MARK: - Conversion

    func testCacheRecordToPerceptualHash() {
        let record = CacheRecord(
            filePath: "/tmp/x.mp4",
            fileSize: 100,
            modifiedAt: nil,
            perceptualHash: Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]),
            prehashDurationBucket: 50,
            prehashSizeBucket: 60,
            prehashAspectBucket: 59,
            prehashThumbnailMean: 128,
            prehashThumbnailVariance: 1000
        )
        let id = UUID()
        let hash = record.toPerceptualHash(videoID: id)
        XCTAssertEqual(hash.videoID, id)
        XCTAssertEqual(hash.hashBits, [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88])
    }

    func testCacheRecordFromVideoItem() {
        let video = VideoItem(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/foo.mp4"),
            fileSize: 1000,
            duration: 60,
            width: 1920,
            height: 1080,
            modifiedAt: Date(timeIntervalSince1970: 5000),
            thumbnailData: nil
        )
        let phash = VideoPerceptualHash(videoID: video.id, hashBits: [1, 2, 3, 4, 5, 6, 7, 8])
        let qprehash = QuickPrehasher.prehash(for: video)

        let record = CacheRecord.make(video: video, perceptualHash: phash, quickPrehash: qprehash)
        XCTAssertEqual(record.filePath, "/tmp/foo.mp4")
        XCTAssertEqual(record.fileSize, 1000)
        XCTAssertEqual(record.modifiedAt, Date(timeIntervalSince1970: 5000))
        XCTAssertEqual(Array(record.perceptualHash), [1, 2, 3, 4, 5, 6, 7, 8])
    }

    // MARK: - In-Memory Cache

    func testInMemoryCacheBehavesLikeSQLite() async {
        let memCache = InMemoryHashCache()
        let record = makeRecord(path: "/tmp/foo.mp4", size: 100, date: Date(timeIntervalSince1970: 1000))
        await memCache.upsert(record)

        let result = await memCache.lookup(
            filePath: "/tmp/foo.mp4",
            fileSize: 100,
            modifiedAt: Date(timeIntervalSince1970: 1000)
        )
        XCTAssertNotNil(result)

        await memCache.pruneStale(validPaths: [])
        let count = await memCache.count()
        XCTAssertEqual(count, 0)
    }

    // MARK: - Helpers

    private func makeRecord(path: String, size: Int64, date: Date?) -> CacheRecord {
        CacheRecord(
            filePath: path,
            fileSize: size,
            modifiedAt: date,
            perceptualHash: Data([0xAB, 0xCD, 0xEF, 0x01, 0x02, 0x03, 0x04, 0x05]),
            prehashDurationBucket: 50,
            prehashSizeBucket: 60,
            prehashAspectBucket: 59,
            prehashThumbnailMean: 128,
            prehashThumbnailVariance: 1000
        )
    }
}
