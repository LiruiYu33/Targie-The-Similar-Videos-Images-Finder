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

    func testBatchMetadataLookupReturnsOnlyMatchingPrimaryEntries() async {
        let date = Date(timeIntervalSince1970: 5_600)
        let matching = MediaMetadataCacheKey(filePath: "/tmp/batch-metadata.mp4", fileSize: 4, modifiedAt: date, mediaKind: .video)
        let stale = MediaMetadataCacheKey(filePath: "/tmp/batch-stale.mp4", fileSize: 4, modifiedAt: date.addingTimeInterval(10), mediaKind: .video)
        await cache.upsertMetadata(
            filePath: matching.filePath,
            fileSize: matching.fileSize,
            modifiedAt: matching.modifiedAt,
            mediaKind: matching.mediaKind,
            duration: 12,
            width: 1920,
            height: 1080
        )
        await cache.upsertMetadata(
            filePath: stale.filePath,
            fileSize: stale.fileSize,
            modifiedAt: date,
            mediaKind: stale.mediaKind,
            duration: 30,
            width: 1280,
            height: 720
        )
        let batch = await cache.lookupMetadata(keys: [matching, stale])

        XCTAssertEqual(batch[matching]?.duration, 12)
        XCTAssertEqual(batch[matching]?.width, 1920)
        XCTAssertNil(batch[stale])
    }

    func testBatchFingerprintLookupReturnsOnlyMatchingPrimaryEntries() async {
        let date = Date(timeIntervalSince1970: 5_700)
        var record = makeRecord(path: "/tmp/batch-hash.mp4", size: 4, date: date)
        record.mediaKind = MediaKind.video.rawValue
        record.algorithmVersion = "video-dct3d-v1"
        await cache.upsert(record)
        let matching = MediaHashCacheKey(
            filePath: record.filePath,
            fileSize: record.fileSize,
            modifiedAt: record.modifiedAt,
            mediaKind: .video,
            algorithmVersion: "video-dct3d-v1"
        )
        let wrongVersion = MediaHashCacheKey(
            filePath: record.filePath,
            fileSize: record.fileSize,
            modifiedAt: record.modifiedAt,
            mediaKind: .video,
            algorithmVersion: "video-dct3d-v2"
        )

        let batch = await cache.lookupHashes(keys: [matching, wrongVersion])

        XCTAssertEqual(batch[matching]?.filePath, record.filePath)
        XCTAssertNil(batch[wrongVersion])
    }

    // MARK: - Pair Relation Cache

    func testPairRelationCachePersistsSymmetricallyAcrossDatabaseConnections() async throws {
        let first = makeMedia(path: "/tmp/pair-a.mp4", size: 100, date: Date(timeIntervalSince1970: 6_000))
        let second = makeMedia(path: "/tmp/pair-b.mp4", size: 120, date: Date(timeIntervalSince1970: 6_100))
        let relation = SimilarityRelation(
            firstID: first.id,
            secondID: second.id,
            score: 0.91,
            evidence: [.similarPerceptualHash, .similarName]
        )

        await cache.upsertPairRelation(first: first, second: second, algorithmVersion: "test-pair-v1", relation: relation)
        cache = nil
        cache = try HashCache(databaseURL: dbURL)

        let cached = await cache.lookupPairRelation(first: second, second: first, algorithmVersion: "test-pair-v1")

        XCTAssertEqual(cached?.score, 0.91)
        XCTAssertEqual(cached?.evidence, [.similarPerceptualHash, .similarName])
    }

    func testPairRelationCacheToleratesSubmillisecondDateNoise() async {
        let first = makeMedia(path: "/tmp/pair-date-a.mp4", size: 100, date: Date(timeIntervalSince1970: 6_025.123_1))
        let second = makeMedia(path: "/tmp/pair-date-b.mp4", size: 120, date: Date(timeIntervalSince1970: 6_025.456_1))
        let relation = SimilarityRelation(
            firstID: first.id,
            secondID: second.id,
            score: 0.91,
            evidence: [.similarPerceptualHash]
        )

        await cache.upsertPairRelation(first: first, second: second, algorithmVersion: "test-pair-v1", relation: relation)
        let noisySecond = makeMedia(
            path: second.url.path,
            size: second.fileSize,
            date: second.modifiedAt?.addingTimeInterval(0.000_2)
        )

        let cached = await cache.lookupPairRelation(first: first, second: noisySecond, algorithmVersion: "test-pair-v1")

        XCTAssertEqual(cached?.score, 0.91)
    }

    func testPairRelationCacheStoresNoRelationAndInvalidatesChangedFileIdentity() async {
        let first = makeMedia(path: "/tmp/no-relation-a.mp4", size: 100, date: Date(timeIntervalSince1970: 6_200))
        let second = makeMedia(path: "/tmp/no-relation-b.mp4", size: 120, date: Date(timeIntervalSince1970: 6_300))

        await cache.upsertPairRelation(first: first, second: second, algorithmVersion: "test-pair-v1", relation: nil)

        let cached = await cache.lookupPairRelation(first: first, second: second, algorithmVersion: "test-pair-v1")
        let changedSecond = makeMedia(path: second.url.path, size: second.fileSize, date: second.modifiedAt?.addingTimeInterval(0.5))
        let changed = await cache.lookupPairRelation(first: first, second: changedSecond, algorithmVersion: "test-pair-v1")

        XCTAssertNotNil(cached)
        XCTAssertNil(cached?.score)
        XCTAssertEqual(cached?.evidence, [])
        XCTAssertNil(changed)
    }

    func testBatchPairRelationLookupReturnsOnlyMatchingIdentities() async throws {
        let first = makeMedia(path: "/tmp/batch-pair-a.mp4", size: 100, date: Date(timeIntervalSince1970: 6_400))
        let second = makeMedia(path: "/tmp/batch-pair-b.mp4", size: 120, date: Date(timeIntervalSince1970: 6_500))
        let relation = SimilarityRelation(
            firstID: first.id,
            secondID: second.id,
            score: 0.91,
            evidence: [.similarPerceptualHash]
        )
        await cache.upsertPairRelation(first: first, second: second, algorithmVersion: "test-pair-v1", relation: relation)
        let matching = try XCTUnwrap(PairRelationCacheKey(first: first, second: second, algorithmVersion: "test-pair-v1"))
        let changedSecond = makeMedia(path: second.url.path, size: second.fileSize, date: second.modifiedAt?.addingTimeInterval(1))
        let changed = try XCTUnwrap(PairRelationCacheKey(first: first, second: changedSecond, algorithmVersion: "test-pair-v1"))

        let batch = await cache.lookupPairRelations(keys: [matching, changed])

        XCTAssertEqual(batch[matching]?.score, 0.91)
        XCTAssertNil(batch[changed])
    }

    func testScanRelationIndexPersistsPositiveRelations() async throws {
        let first = makeMedia(path: "/tmp/index-a.mp4", size: 100, date: Date(timeIntervalSince1970: 10))
        let second = makeMedia(path: "/tmp/index-b.mp4", size: 120, date: Date(timeIntervalSince1970: 20))
        let relation = CachedScanRelation(
            firstPath: first.url.path,
            secondPath: second.url.path,
            score: 0.91,
            evidence: [.similarPerceptualHash]
        )

        await cache.upsertScanRelationIndex(
            signature: "sig-video-1",
            mediaKind: .video,
            algorithmVersion: "pair-v1",
            fileCount: 2,
            candidateCount: 1,
            relations: [relation]
        )

        cache = nil
        cache = try HashCache(databaseURL: dbURL)

        let cached = await cache.lookupScanRelationIndex(
            signature: "sig-video-1",
            mediaKind: .video,
            algorithmVersion: "pair-v1"
        )
        XCTAssertEqual(cached?.fileCount, 2)
        XCTAssertEqual(cached?.candidateCount, 1)
        XCTAssertEqual(cached?.relations, [relation])
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

    func testPruneStaleRemovesPairRelationsWithInvalidMembers() async {
        let first = makeMedia(path: "/tmp/pair-prune-a.mp4", size: 100, date: nil)
        let second = makeMedia(path: "/tmp/pair-prune-b.mp4", size: 120, date: nil)
        let relation = SimilarityRelation(
            firstID: first.id,
            secondID: second.id,
            score: 0.91,
            evidence: [.similarPerceptualHash]
        )
        await cache.upsertPairRelation(first: first, second: second, algorithmVersion: "test-pair-v1", relation: relation)

        await cache.pruneStale(validPaths: [first.url.path])

        let cached = await cache.lookupPairRelation(first: first, second: second, algorithmVersion: "test-pair-v1")
        XCTAssertNil(cached)
    }

    func testPruneStaleRemovesScanRelationIndexWithInvalidRelationMembers() async {
        let first = makeMedia(path: "/tmp/index-prune-a.mp4", size: 100, date: nil)
        let second = makeMedia(path: "/tmp/index-prune-b.mp4", size: 120, date: nil)
        await cache.upsertScanRelationIndex(
            signature: "sig-prune",
            mediaKind: .video,
            algorithmVersion: "test-pair-v1",
            fileCount: 2,
            candidateCount: 1,
            relations: [
                CachedScanRelation(
                    firstPath: first.url.path,
                    secondPath: second.url.path,
                    score: 0.91,
                    evidence: [.similarPerceptualHash]
                )
            ]
        )

        await cache.pruneStale(validPaths: [first.url.path])

        let cached = await cache.lookupScanRelationIndex(
            signature: "sig-prune",
            mediaKind: .video,
            algorithmVersion: "test-pair-v1"
        )
        XCTAssertNil(cached)
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

    private func makeMedia(path: String, size: Int64, date: Date?) -> MediaItem {
        MediaItem(
            kind: .video,
            url: URL(fileURLWithPath: path),
            fileSize: size,
            duration: 60,
            width: 1920,
            height: 1080,
            modifiedAt: date,
            thumbnailData: nil
        )
    }

    private func writeFixture(named name: String, data: Data, modifiedAt: Date) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
        return url
    }
}
