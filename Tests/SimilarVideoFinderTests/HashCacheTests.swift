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
import GRDB
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

        // Changed file size invalidates the cache.
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
            mediaKind: .video, algorithmVersion: PerceptualHasher.algorithmVersion
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

        // Changed modification date invalidates the cache.
        let result = await cache.lookup(
            filePath: "/tmp/foo.mp4",
            fileSize: 100,
            modifiedAt: Date(timeIntervalSince1970: 2000)
        )
        XCTAssertNil(result)
    }

    func testLookupAcceptsModificationDatesWithinSameMillisecond() async {
        let record = makeRecord(path: "/tmp/foo.mp4", size: 100, date: Date(timeIntervalSince1970: 1000.123_1))
        await cache.upsert(record)

        let result = await cache.lookup(
            filePath: "/tmp/foo.mp4",
            fileSize: 100,
            modifiedAt: Date(timeIntervalSince1970: 1000.123_3)
        )
        XCTAssertNotNil(result)
    }

    func testLookupRejectsHalfSecondModificationDateDifference() async {
        let date = Date(timeIntervalSince1970: 1000)
        await cache.upsert(makeRecord(path: "/tmp/foo.mp4", size: 100, date: date))

        let result = await cache.lookup(
            filePath: "/tmp/foo.mp4",
            fileSize: 100,
            modifiedAt: date.addingTimeInterval(0.5)
        )

        XCTAssertNil(result)
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

    func testMoveLookupRejectsChangedModificationDateEvenWhenSHA256Matches() async throws {
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

    func testRealRenameWithSubmillisecondModificationDateReusesPersistedCaches() async throws {
        let original = try writeFixture(
            named: "fractional-old.mp4",
            data: Data("SAME".utf8),
            modifiedAt: Date(timeIntervalSince1970: 5_090.1234)
        )
        let date = try XCTUnwrap(original.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        XCTAssertNotEqual(date, FileCacheIdentity.normalizedModifiedAt(date))
        let digest = try await FileHasher.sha256(of: original)
        let frameData = Data("frame-features".utf8)
        await cache.upsert(makeRecord(path: original.path, size: 4, date: date))
        await cache.upsertMetadata(filePath: original.path, fileSize: 4, modifiedAt: date, mediaKind: .video, duration: 12, width: 1920, height: 1080)
        await cache.upsertSHA256(filePath: original.path, fileSize: 4, modifiedAt: date, mediaKind: .video, sha256: digest)
        await cache.upsertFrameFeature(filePath: original.path, fileSize: 4, modifiedAt: date, featureData: frameData)

        let moved = tempDir.appendingPathComponent("fractional-new.mp4")
        try FileManager.default.moveItem(at: original, to: moved)
        let movedDate = try XCTUnwrap(moved.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        XCTAssertEqual(date, movedDate)

        // Reopen the database to exercise persisted date precision, not a mock.
        let reopened = try HashCache(databaseURL: dbURL)
        let oldPath = await reopened.detectMove(filePath: moved.path, fileSize: 4, modifiedAt: movedDate, mediaKind: .video, algorithmVersion: PerceptualHasher.algorithmVersion)
        let metadata = await reopened.lookupMetadata(filePath: moved.path, fileSize: 4, modifiedAt: movedDate, mediaKind: .video)
        let sha = await reopened.lookupSHA256(filePath: moved.path, fileSize: 4, modifiedAt: movedDate, mediaKind: .video)
        let frames = await reopened.lookupFrameFeature(filePath: moved.path, fileSize: 4, modifiedAt: movedDate)
        let hash = await reopened.lookup(filePath: moved.path, fileSize: 4, modifiedAt: movedDate)
        XCTAssertEqual(oldPath, original.path)
        XCTAssertEqual(metadata?.duration, 12)
        XCTAssertEqual(sha, digest)
        XCTAssertEqual(frames, frameData)
        XCTAssertEqual(hash?.filePath, moved.path)
    }

    func testMoveDetectionStillRejectsExistingSourceAndWrongMediaKind() async throws {
        let date = Date(timeIntervalSince1970: 5_095.1234)
        let original = try writeFixture(named: "existing-old.mp4", data: Data("SAME".utf8), modifiedAt: date)
        let copied = try writeFixture(named: "existing-copy.mp4", data: Data("SAME".utf8), modifiedAt: date)
        let digest = try await FileHasher.sha256(of: original)
        await cache.upsertSHA256(filePath: original.path, fileSize: 4, modifiedAt: date, mediaKind: .video, sha256: digest)

        let whileOriginalExists = await cache.detectMove(filePath: copied.path, fileSize: 4, modifiedAt: date, mediaKind: .video, algorithmVersion: PerceptualHasher.algorithmVersion)
        XCTAssertNil(whileOriginalExists)
        try FileManager.default.removeItem(at: original)
        let wrongKind = await cache.detectMove(filePath: copied.path, fileSize: 4, modifiedAt: date, mediaKind: .image, algorithmVersion: PerceptualHasher.algorithmVersion)
        let correctKind = await cache.detectMove(filePath: copied.path, fileSize: 4, modifiedAt: date, mediaKind: .video, algorithmVersion: PerceptualHasher.algorithmVersion)
        XCTAssertNil(wrongKind)
        XCTAssertEqual(correctKind, original.path)
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

    /// Regression: a metadata move-hit used to migrate the media_metadata row
    /// to the new path, which erased the SHA-256 proof at the old path that
    /// every other move detection relies on. After a metadata move-hit, the
    /// hash_cache move detection must still succeed for the same moved file.
    func testHashCacheMoveDetectionSurvivesMetadataMoveHit() async throws {
        let date = Date(timeIntervalSince1970: 5_150)
        let data = Data("SAME".utf8)
        let current = try writeFixture(named: "after-metadata-move.mp4", data: data, modifiedAt: date)
        let oldPath = tempDir.appendingPathComponent("before-metadata-move.mp4").path
        let oldSHA = try await FileHasher.sha256(of: current)
        let size = Int64(data.count)

        await cache.upsert(makeRecord(path: oldPath, size: size, date: date))
        await cache.upsertMetadata(filePath: oldPath, fileSize: size, modifiedAt: date, mediaKind: .video, duration: 12, width: 1920, height: 1080)
        await cache.upsertSHA256(filePath: oldPath, fileSize: size, modifiedAt: date, sha256: oldSHA)

        // Scanner calls lookupMetadata first (move-hit reuses metadata)...
        let metadata = await cache.lookupMetadata(filePath: current.path, fileSize: size, modifiedAt: date, mediaKind: .video)
        XCTAssertEqual(metadata?.duration, 12)

        // ...then the pipeline calls lookup for the perceptual hash. This must
        // still move-hit; before the fix the migrated row broke the SHA proof.
        let hash = await cache.lookup(filePath: current.path, fileSize: size, modifiedAt: date, mediaKind: .video, algorithmVersion: PerceptualHasher.algorithmVersion)
        XCTAssertNotNil(hash)
        XCTAssertEqual(hash?.filePath, current.path)
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

    func testImageFeatureCacheSeparatesAlgorithmVersions() async {
        let date = Date(timeIntervalSince1970: 5_350)
        let path = tempDir.appendingPathComponent("versioned-feature.jpg").path
        await cache.upsertImageFeature(
            filePath: path,
            fileSize: 4,
            modifiedAt: date,
            algorithmVersion: "vision-image-feature-v1",
            featureData: Data([1, 2, 3])
        )

        let oldFeature = await cache.lookupImageFeature(
            filePath: path,
            fileSize: 4,
            modifiedAt: date,
            algorithmVersion: "vision-image-feature-v1"
        )
        let currentFeature = await cache.lookupImageFeature(
            filePath: path,
            fileSize: 4,
            modifiedAt: date,
            algorithmVersion: ImageFeatureExtractor.algorithmVersion
        )

        XCTAssertEqual(oldFeature, Data([1, 2, 3]))
        XCTAssertNil(currentFeature)
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

    func testMetadataUpdateInvalidatesSHA256WhenFileIdentityChanges() async {
        let originalDate = Date(timeIntervalSince1970: 5_510)
        let changedDate = originalDate.addingTimeInterval(10)
        let path = tempDir.appendingPathComponent("changed-in-place.mp4").path
        await cache.upsertMetadata(
            filePath: path,
            fileSize: 4,
            modifiedAt: originalDate,
            mediaKind: .video,
            duration: 10,
            width: 640,
            height: 360
        )
        await cache.upsertSHA256(
            filePath: path,
            fileSize: 4,
            modifiedAt: originalDate,
            mediaKind: .video,
            sha256: "stale-sha"
        )

        await cache.upsertMetadata(
            filePath: path,
            fileSize: 4,
            modifiedAt: changedDate,
            mediaKind: .video,
            duration: 11,
            width: 640,
            height: 360
        )

        let sha = await cache.lookupSHA256(
            filePath: path,
            fileSize: 4,
            modifiedAt: changedDate,
            mediaKind: .video
        )
        XCTAssertNil(sha)
    }

    func testMetadataUpdatePreservesSHA256ForUnchangedFileIdentity() async {
        let date = Date(timeIntervalSince1970: 5_520)
        let path = tempDir.appendingPathComponent("same-file.mp4").path
        await cache.upsertSHA256(
            filePath: path,
            fileSize: 4,
            modifiedAt: date,
            mediaKind: .video,
            sha256: "current-sha"
        )

        await cache.upsertMetadata(
            filePath: path,
            fileSize: 4,
            modifiedAt: date,
            mediaKind: .video,
            duration: 12,
            width: 1920,
            height: 1080
        )

        let sha = await cache.lookupSHA256(
            filePath: path,
            fileSize: 4,
            modifiedAt: date,
            mediaKind: .video
        )
        XCTAssertEqual(sha, "current-sha")
    }

    func testInMemoryMetadataUpdateInvalidatesSHA256WhenIdentityChanges() async {
        let inMemory = InMemoryHashCache()
        let originalDate = Date(timeIntervalSince1970: 5_530)
        let changedDate = originalDate.addingTimeInterval(10)
        let path = "/tmp/in-memory-changed.mp4"
        await inMemory.upsertSHA256(
            filePath: path,
            fileSize: 4,
            modifiedAt: originalDate,
            mediaKind: .video,
            sha256: "stale-sha"
        )

        await inMemory.upsertMetadata(
            filePath: path,
            fileSize: 4,
            modifiedAt: changedDate,
            mediaKind: .video,
            duration: 10,
            width: 640,
            height: 360
        )

        let sha = await inMemory.lookupSHA256(
            filePath: path,
            fileSize: 4,
            modifiedAt: changedDate,
            mediaKind: .video
        )
        XCTAssertNil(sha)
    }

    func testSHA256UpdatePreservesMetadataOnlyForUnchangedIdentity() async {
        let date = Date(timeIntervalSince1970: 5_540)
        let identities: [(size: Int64, date: Date, kind: MediaKind)] = [
            (4, date, .video),
            (8, date, .video),
            (4, date.addingTimeInterval(10), .video),
            (4, date, .image)
        ]
        let caches: [any HashCaching] = [cache, InMemoryHashCache()]
        for selectedCache in caches {
            for (index, identity) in identities.enumerated() {
                let path = tempDir.appendingPathComponent("sha-metadata-\(index).mp4").path
                await selectedCache.upsertMetadata(filePath: path, fileSize: 4, modifiedAt: date, mediaKind: .video, duration: 12, width: 1920, height: 1080)
                await selectedCache.upsertSHA256(filePath: path, fileSize: identity.size, modifiedAt: identity.date, mediaKind: identity.kind, sha256: "new-digest")

                let metadata = await selectedCache.lookupMetadata(filePath: path, fileSize: identity.size, modifiedAt: identity.date, mediaKind: identity.kind)
                let digest = await selectedCache.lookupSHA256(filePath: path, fileSize: identity.size, modifiedAt: identity.date, mediaKind: identity.kind)
                XCTAssertNotNil(metadata)
                XCTAssertEqual(digest, "new-digest")
                if index == 0 {
                    XCTAssertEqual(metadata?.duration, 12)
                    XCTAssertEqual(metadata?.width, 1920)
                    XCTAssertEqual(metadata?.height, 1080)
                } else {
                    XCTAssertNil(metadata?.duration)
                    XCTAssertNil(metadata?.width)
                    XCTAssertNil(metadata?.height)
                    let previous = await selectedCache.lookupMetadata(filePath: path, fileSize: 4, modifiedAt: date, mediaKind: .video)
                    XCTAssertNil(previous)
                }
            }
        }
    }

    func testFrameFeatureCacheVersionsSeparateLegacyAndCurrentData() async {
        let date = Date(timeIntervalSince1970: 5_550)
        let path = tempDir.appendingPathComponent("versioned-frames.mp4").path
        let legacy = "vision-frame-feature-v1"
        let caches: [any HashCaching] = [cache, InMemoryHashCache()]
        for selectedCache in caches {
            await selectedCache.upsertFrameFeature(filePath: path, fileSize: 4, modifiedAt: date, algorithmVersion: legacy, featureData: Data([1]))
            let stale = await selectedCache.lookupFrameFeature(filePath: path, fileSize: 4, modifiedAt: date)
            let legacyHit = await selectedCache.lookupFrameFeature(filePath: path, fileSize: 4, modifiedAt: date, algorithmVersion: legacy)
            XCTAssertNil(stale)
            XCTAssertEqual(legacyHit, Data([1]))

            await selectedCache.upsertFrameFeature(filePath: path, fileSize: 4, modifiedAt: date, featureData: Data([2]))
            let current = await selectedCache.lookupFrameFeature(filePath: path, fileSize: 4, modifiedAt: date, algorithmVersion: FrameFeatureExtractor.algorithmVersion)
            let invalidatedLegacy = await selectedCache.lookupFrameFeature(filePath: path, fileSize: 4, modifiedAt: date, algorithmVersion: legacy)
            XCTAssertEqual(current, Data([2]))
            XCTAssertNil(invalidatedLegacy)
        }
    }

    func testFrameFeatureMoveLookupRequiresMatchingAlgorithmVersion() async throws {
        let date = Date(timeIntervalSince1970: 5_560.1234)
        let original = try writeFixture(named: "old-version-frames.mp4", data: Data("SAME".utf8), modifiedAt: date)
        let moved = tempDir.appendingPathComponent("moved-version-frames.mp4")
        let digest = try await FileHasher.sha256(of: original)
        let legacy = "vision-frame-feature-v1"
        await cache.upsertSHA256(filePath: original.path, fileSize: 4, modifiedAt: date, mediaKind: .video, sha256: digest)
        await cache.upsertFrameFeature(filePath: original.path, fileSize: 4, modifiedAt: date, algorithmVersion: legacy, featureData: Data([1]))
        try FileManager.default.moveItem(at: original, to: moved)

        let stale = await cache.lookupFrameFeature(filePath: moved.path, fileSize: 4, modifiedAt: date)
        XCTAssertNil(stale)
        await cache.upsertFrameFeature(filePath: original.path, fileSize: 4, modifiedAt: date, featureData: Data([2]))
        let current = await cache.lookupFrameFeature(filePath: moved.path, fileSize: 4, modifiedAt: date)
        XCTAssertEqual(current, Data([2]))
    }

    func testFrameFeatureMigrationInvalidatesUnversionedRowsAndPreservesSHA256() async throws {
        let path = tempDir.appendingPathComponent("migration-frames.mp4").path
        let date = Date(timeIntervalSince1970: 5_570)
        await cache.upsertSHA256(filePath: path, fileSize: 4, modifiedAt: date, mediaKind: .video, sha256: "preserved-sha")
        cache = nil
        let queue = try DatabaseQueue(path: dbURL.path)
        // Restore the exact pre-v10 frame table while retaining the previous
        // migrations and unrelated cache data.
        try await queue.write { db in
            try db.execute(sql: "DROP TABLE frame_features")
            try db.execute(sql: "CREATE TABLE frame_features (filePath TEXT PRIMARY KEY, fileSize INTEGER NOT NULL, modifiedAt DATETIME, featureData BLOB NOT NULL)")
            try db.execute(sql: "INSERT INTO frame_features (filePath, fileSize, modifiedAt, featureData) VALUES (?, ?, ?, ?)", arguments: [path, 4, date, Data([1])])
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = ?", arguments: ["v10_version_frame_features"])
        }

        let migrated = try HashCache(databaseURL: dbURL)
        let current = await migrated.lookupFrameFeature(filePath: path, fileSize: 4, modifiedAt: date)
        let legacy = await migrated.lookupFrameFeature(filePath: path, fileSize: 4, modifiedAt: date, algorithmVersion: "vision-frame-feature-v1")
        let sha = await migrated.lookupSHA256(filePath: path, fileSize: 4, modifiedAt: date, mediaKind: .video)
        XCTAssertNil(current)
        XCTAssertEqual(legacy, Data([1]))
        XCTAssertEqual(sha, "preserved-sha")
    }

    func testAllPrimaryCachesRejectSameSizeFileChangedWithinOneSecond() async {
        let path = tempDir.appendingPathComponent("rapid-change.mp4").path
        let originalDate = Date(timeIntervalSince1970: 5_540)
        let changedDate = originalDate.addingTimeInterval(0.5)
        await cache.upsert(makeRecord(path: path, size: 4, date: originalDate))
        await cache.upsertMetadata(
            filePath: path,
            fileSize: 4,
            modifiedAt: originalDate,
            mediaKind: .video,
            duration: 10,
            width: 640,
            height: 360
        )
        await cache.upsertSHA256(
            filePath: path,
            fileSize: 4,
            modifiedAt: originalDate,
            mediaKind: .video,
            sha256: "stale-sha"
        )
        await cache.upsertImageFeature(
            filePath: path,
            fileSize: 4,
            modifiedAt: originalDate,
            featureData: Data([1])
        )
        await cache.upsertFrameFeature(
            filePath: path,
            fileSize: 4,
            modifiedAt: originalDate,
            featureData: Data([2])
        )

        let fingerprint = await cache.lookup(
            filePath: path,
            fileSize: 4,
            modifiedAt: changedDate
        )
        let metadata = await cache.lookupMetadata(
            filePath: path,
            fileSize: 4,
            modifiedAt: changedDate,
            mediaKind: .video
        )
        let sha = await cache.lookupSHA256(
            filePath: path,
            fileSize: 4,
            modifiedAt: changedDate,
            mediaKind: .video
        )
        let imageFeature = await cache.lookupImageFeature(
            filePath: path,
            fileSize: 4,
            modifiedAt: changedDate
        )
        let frameFeature = await cache.lookupFrameFeature(
            filePath: path,
            fileSize: 4,
            modifiedAt: changedDate
        )

        XCTAssertNil(fingerprint)
        XCTAssertNil(metadata)
        XCTAssertNil(sha)
        XCTAssertNil(imageFeature)
        XCTAssertNil(frameFeature)
    }

    func testInMemoryFeatureCachesValidateFileIdentity() async {
        let inMemory = InMemoryHashCache()
        let path = "/tmp/in-memory-feature.mp4"
        let originalDate = Date(timeIntervalSince1970: 5_550)
        let changedDate = originalDate.addingTimeInterval(0.5)
        await inMemory.upsertImageFeature(
            filePath: path,
            fileSize: 4,
            modifiedAt: originalDate,
            featureData: Data([1])
        )
        await inMemory.upsertFrameFeature(
            filePath: path,
            fileSize: 4,
            modifiedAt: originalDate,
            featureData: Data([2])
        )

        let imageFeature = await inMemory.lookupImageFeature(
            filePath: path,
            fileSize: 4,
            modifiedAt: changedDate
        )
        let frameFeature = await inMemory.lookupFrameFeature(
            filePath: path,
            fileSize: 4,
            modifiedAt: changedDate
        )

        XCTAssertNil(imageFeature)
        XCTAssertNil(frameFeature)
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
        record.algorithmVersion = PerceptualHasher.algorithmVersion
        await cache.upsert(record)
        let matching = MediaHashCacheKey(
            filePath: record.filePath,
            fileSize: record.fileSize,
            modifiedAt: record.modifiedAt,
            mediaKind: .video,
            algorithmVersion: PerceptualHasher.algorithmVersion
        )
        let oldVersion = MediaHashCacheKey(
            filePath: record.filePath,
            fileSize: record.fileSize,
            modifiedAt: record.modifiedAt,
            mediaKind: .video,
            algorithmVersion: "video-dct3d-v1"
        )

        let batch = await cache.lookupHashes(keys: [matching, oldVersion])

        XCTAssertEqual(batch[matching]?.filePath, record.filePath)
        XCTAssertNil(batch[oldVersion])
    }

    func testConvenienceVideoLookupIgnoresV1Fingerprint() async {
        var record = makeRecord(path: "/tmp/old-video-hash.mp4", size: 4, date: nil)
        record.algorithmVersion = "video-dct3d-v1"
        await cache.upsert(record)

        let result = await cache.lookup(filePath: record.filePath, fileSize: record.fileSize, modifiedAt: nil)

        XCTAssertNil(result)
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

    func testV1PairRelationIsNotReturnedForCurrentPipelineVersion() async {
        let first = makeMedia(path: "/tmp/old-pair-a.mp4", size: 100, date: nil)
        let second = makeMedia(path: "/tmp/old-pair-b.mp4", size: 120, date: nil)
        let relation = SimilarityRelation(
            firstID: first.id,
            secondID: second.id,
            score: 0.91,
            evidence: [.similarPerceptualHash]
        )
        await cache.upsertPairRelation(
            first: first,
            second: second,
            algorithmVersion: "video-pair-relation-v1-perceptual",
            relation: relation
        )

        let cached = await cache.lookupPairRelation(
            first: first,
            second: second,
            algorithmVersion: SimilarityPipeline.pairRelationAlgorithmVersion(usesFrameVerification: false)
        )

        XCTAssertNil(cached)
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

    func testBatchPairRelationUpsertPersistsMultipleRelations() async throws {
        let first = makeMedia(path: "/tmp/batch-upsert-a.mp4", size: 100, date: Date(timeIntervalSince1970: 10))
        let second = makeMedia(path: "/tmp/batch-upsert-b.mp4", size: 120, date: Date(timeIntervalSince1970: 20))
        let third = makeMedia(path: "/tmp/batch-upsert-c.mp4", size: 140, date: Date(timeIntervalSince1970: 30))
        let firstRelation = SimilarityRelation(
            firstID: first.id,
            secondID: second.id,
            score: 0.91,
            evidence: [.similarPerceptualHash]
        )

        await cache.upsertPairRelations([
            PairRelationCacheUpsert(
                first: first,
                second: second,
                algorithmVersion: "test-pair-v1",
                relation: firstRelation
            ),
            PairRelationCacheUpsert(
                first: first,
                second: third,
                algorithmVersion: "test-pair-v1",
                relation: nil
            )
        ])

        let positive = await cache.lookupPairRelation(first: first, second: second, algorithmVersion: "test-pair-v1")
        let negative = await cache.lookupPairRelation(first: first, second: third, algorithmVersion: "test-pair-v1")

        XCTAssertEqual(positive?.score, 0.91)
        XCTAssertEqual(positive?.evidence, [.similarPerceptualHash])
        XCTAssertNotNil(negative)
        XCTAssertNil(negative?.score)
        XCTAssertTrue(negative?.evidence.isEmpty == true)
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

    func testV1ScanRelationIndexIsNotReturnedForCurrentPipelineVersion() async {
        await cache.upsertScanRelationIndex(
            signature: "old-video-index",
            mediaKind: .video,
            algorithmVersion: "video-pair-relation-v1-perceptual",
            fileCount: 2,
            candidateCount: 0,
            relations: []
        )

        let cached = await cache.lookupScanRelationIndex(
            signature: "old-video-index",
            mediaKind: .video,
            algorithmVersion: SimilarityPipeline.pairRelationAlgorithmVersion(usesFrameVerification: false)
        )

        XCTAssertNil(cached)
    }

    func testScanRelationIndexDeduplicatesRelationsBeforePersisting() async throws {
        let first = makeMedia(path: "/tmp/index-duplicate-a.mp4", size: 100, date: Date(timeIntervalSince1970: 10))
        let second = makeMedia(path: "/tmp/index-duplicate-b.mp4", size: 120, date: Date(timeIntervalSince1970: 20))
        let relation = CachedScanRelation(
            firstPath: first.url.path,
            secondPath: second.url.path,
            score: 0.91,
            evidence: [.similarPerceptualHash]
        )
        let reversedDuplicate = CachedScanRelation(
            firstPath: second.url.path,
            secondPath: first.url.path,
            score: 0.91,
            evidence: [.similarPerceptualHash]
        )

        await cache.upsertScanRelationIndex(
            signature: "sig-video-duplicates",
            mediaKind: .video,
            algorithmVersion: "pair-v1",
            fileCount: 2,
            candidateCount: 2,
            relations: [relation, reversedDuplicate]
        )

        let cached = await cache.lookupScanRelationIndex(
            signature: "sig-video-duplicates",
            mediaKind: .video,
            algorithmVersion: "pair-v1"
        )
        XCTAssertEqual(cached?.candidateCount, 2)
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

    func testClearAllRemovesRowsAndCompactsDatabaseFile() async throws {
        let record = CacheRecord(
            filePath: "/tmp/large-cache-entry.mp4",
            fileSize: 2_000_000,
            modifiedAt: Date(timeIntervalSince1970: 7_000),
            perceptualHash: Data(repeating: 0xAB, count: 2_000_000),
            prehashDurationBucket: 50,
            prehashSizeBucket: 60,
            prehashAspectBucket: 59,
            prehashThumbnailMean: 128,
            prehashThumbnailVariance: 1000
        )
        await cache.upsert(record)
        let populatedSize = await cache.sizeInBytes()
        XCTAssertGreaterThan(populatedSize, 1_000_000)

        try await cache.clearAll()

        let remainingCount = await cache.count()
        let clearedSize = await cache.sizeInBytes()
        XCTAssertEqual(remainingCount, 0)
        XCTAssertLessThan(clearedSize, 512_000)
    }

    // MARK: - Persistence Across Instances

    func testCachePersistsAcrossDatabaseConnections() async throws {
        let record = makeRecord(path: "/tmp/foo.mp4", size: 100, date: Date(timeIntervalSince1970: 1000))
        await cache.upsert(record)

        // Reopen the same database.
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

    func testCacheRecordToPerceptualHash() throws {
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
        let hash = try XCTUnwrap(record.toPerceptualHash(videoID: id))
        XCTAssertEqual(hash.videoID, id)
        XCTAssertEqual(hash.hashBits, [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88])
    }

    func testCacheRecordRejectsMalformedVideoPerceptualHash() {
        var record = makeRecord(path: "/tmp/malformed.mp4", size: 100, date: nil)
        record.perceptualHash = Data([0x11, 0x22, 0x33, 0x44])

        XCTAssertNil(record.toPerceptualHash(videoID: UUID()))
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
        XCTAssertEqual(record.algorithmVersion, PerceptualHasher.algorithmVersion)
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
