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

    func testLookupFailsForDifferentMediaKindOrAlgorithmVersion() async {
        var record = makeRecord(path: "/tmp/foo.jpg", size: 100, date: nil)
        record.mediaKind = MediaKind.image.rawValue
        record.algorithmVersion = "image-phash-v1"
        await cache.upsert(record)

        let matching = await cache.lookup(
            filePath: record.filePath, fileSize: 100, modifiedAt: nil,
            mediaKind: .image, algorithmVersion: "image-phash-v1"
        )
        let wrongKind = await cache.lookup(
            filePath: record.filePath, fileSize: 100, modifiedAt: nil,
            mediaKind: .video, algorithmVersion: "video-dct3d-v1"
        )
        let wrongVersion = await cache.lookup(
            filePath: record.filePath, fileSize: 100, modifiedAt: nil,
            mediaKind: .image, algorithmVersion: "image-phash-v2"
        )
        XCTAssertNotNil(matching)
        XCTAssertNil(wrongKind)
        XCTAssertNil(wrongVersion)
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

    func testMoveLookupDoesNotReusePerceptualHashWithoutContentProof() async throws {
        let date = Date(timeIntervalSince1970: 5_000)
        let current = try writeFixture(named: "current.mp4", data: Data("BBBB".utf8), modifiedAt: date)
        let oldPath = tempDir.appendingPathComponent("old.mp4").path
        await cache.upsert(makeRecord(path: oldPath, size: 4, date: date))

        let result = await cache.lookup(filePath: current.path, fileSize: 4, modifiedAt: date)

        XCTAssertNil(result)
    }

    func testMoveLookupReusesPerceptualHashWhenSHA256Matches() async throws {
        let date = Date(timeIntervalSince1970: 5_050)
        let data = Data("SAME".utf8)
        let current = try writeFixture(named: "moved-current.mp4", data: data, modifiedAt: date)
        let oldPath = tempDir.appendingPathComponent("moved-old.mp4").path
        let oldSHA = try await FileHasher.sha256(of: current)
        await cache.upsert(makeRecord(path: oldPath, size: Int64(data.count), date: date))
        await cache.upsertMetadata(
            filePath: oldPath,
            fileSize: Int64(data.count),
            modifiedAt: date,
            mediaKind: .video,
            duration: nil,
            width: nil,
            height: nil
        )
        await cache.upsertSHA256(filePath: oldPath, fileSize: Int64(data.count), modifiedAt: date, sha256: oldSHA)

        let result = await cache.lookup(filePath: current.path, fileSize: Int64(data.count), modifiedAt: date)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.filePath, current.path)
    }

    func testMoveLookupRequiresExactModificationDateEvenWhenSHA256Matches() async throws {
        let cachedDate = Date(timeIntervalSince1970: 5_075)
        let currentDate = cachedDate.addingTimeInterval(0.5)
        let data = Data("SAME".utf8)
        let current = try writeFixture(named: "moved-current-near-date.mp4", data: data, modifiedAt: currentDate)
        let oldPath = tempDir.appendingPathComponent("moved-old-near-date.mp4").path
        let oldSHA = try await FileHasher.sha256(of: current)
        await cache.upsert(makeRecord(path: oldPath, size: Int64(data.count), date: cachedDate))
        await cache.upsertMetadata(
            filePath: oldPath,
            fileSize: Int64(data.count),
            modifiedAt: cachedDate,
            mediaKind: .video,
            duration: nil,
            width: nil,
            height: nil
        )
        await cache.upsertSHA256(filePath: oldPath, fileSize: Int64(data.count), modifiedAt: cachedDate, sha256: oldSHA)

        let result = await cache.lookup(filePath: current.path, fileSize: Int64(data.count), modifiedAt: currentDate)

        XCTAssertNil(result)
    }

    func testMoveMetadataLookupDoesNotReuseMetadataWhenSHA256DoesNotMatch() async throws {
        let date = Date(timeIntervalSince1970: 5_100)
        let current = try writeFixture(named: "current-metadata.mp4", data: Data("BBBB".utf8), modifiedAt: date)
        let oldPath = tempDir.appendingPathComponent("old-metadata.mp4").path
        await cache.upsertMetadata(
            filePath: oldPath,
            fileSize: 4,
            modifiedAt: date,
            mediaKind: .video,
            duration: 12,
            width: 1920,
            height: 1080
        )
        await cache.upsertSHA256(filePath: oldPath, fileSize: 4, modifiedAt: date, sha256: "not-the-current-file")

        let result = await cache.lookupMetadata(filePath: current.path, fileSize: 4, modifiedAt: date, mediaKind: .video)

        XCTAssertNil(result)
    }

    func testMoveSHA256LookupDoesNotReturnHashForDifferentContent() async throws {
        let date = Date(timeIntervalSince1970: 5_200)
        let current = try writeFixture(named: "current-sha.mp4", data: Data("BBBB".utf8), modifiedAt: date)
        let oldPath = tempDir.appendingPathComponent("old-sha.mp4").path
        await cache.upsertMetadata(
            filePath: oldPath,
            fileSize: 4,
            modifiedAt: date,
            mediaKind: .video,
            duration: nil,
            width: nil,
            height: nil
        )
        await cache.upsertSHA256(filePath: oldPath, fileSize: 4, modifiedAt: date, sha256: "not-the-current-file")

        let result = await cache.lookupSHA256(filePath: current.path, fileSize: 4, modifiedAt: date)

        XCTAssertNil(result)
    }

    func testMoveImageFeatureLookupDoesNotReuseFeatureWithoutContentProof() async throws {
        let date = Date(timeIntervalSince1970: 5_300)
        let current = try writeFixture(named: "current-feature.jpg", data: Data("BBBB".utf8), modifiedAt: date)
        let oldPath = tempDir.appendingPathComponent("old-feature.jpg").path
        await cache.upsertImageFeature(filePath: oldPath, fileSize: 4, modifiedAt: date, featureData: Data([1, 2, 3]))

        let result = await cache.lookupImageFeature(filePath: current.path, fileSize: 4, modifiedAt: date)

        XCTAssertNil(result)
    }

    func testDetectMoveDoesNotReportOldPathWithoutContentProof() async throws {
        let date = Date(timeIntervalSince1970: 5_400)
        let current = try writeFixture(named: "current-thumbnail.jpg", data: Data("BBBB".utf8), modifiedAt: date)
        let oldPath = tempDir.appendingPathComponent("old-thumbnail.jpg").path
        await cache.upsertMetadata(
            filePath: oldPath,
            fileSize: 4,
            modifiedAt: date,
            mediaKind: .image,
            duration: nil,
            width: 40,
            height: 20
        )

        let result = await cache.detectMove(
            filePath: current.path,
            fileSize: 4,
            modifiedAt: date,
            mediaKind: .image,
            algorithmVersion: "image-phash-v1"
        )

        XCTAssertNil(result)
    }

    func testUpsertSHA256CreatesMetadataWithVideoKind() async {
        let date = Date(timeIntervalSince1970: 5_500)
        let path = tempDir.appendingPathComponent("sha-only.mp4").path

        await cache.upsertSHA256(filePath: path, fileSize: 4, modifiedAt: date, sha256: "abc")

        let metadata = await cache.lookupMetadata(filePath: path, fileSize: 4, modifiedAt: date, mediaKind: .video)
        XCTAssertNotNil(metadata)
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

    func testPruneStaleHandlesMorePathsThanSQLiteVariableLimit() async {
        await cache.upsert(makeRecord(path: "/tmp/stale.mp4", size: 1, date: nil))
        let validPaths = Set((0..<300_000).map { "/media/library/video-\($0).mp4" })

        await cache.pruneStale(validPaths: validPaths)

        let remainingCount = await cache.count()
        XCTAssertEqual(remainingCount, 0)
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
        let video = MediaItem(
            id: UUID(),
            kind: .video,
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

    private func writeFixture(named name: String, data: Data, modifiedAt: Date) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
        return url
    }
}
