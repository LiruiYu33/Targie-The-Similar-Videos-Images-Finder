// Targie - Find similar videos on macOS.
// Copyright (C) 2026 Lirui Yu

import XCTest
@testable import SimilarVideoFinder

final class SimilarityPipelineResilienceTests: XCTestCase {
    func testDefaultPipelineDoesNotRunVisionForPerceptualCandidates() async throws {
        let first = video(path: "/missing/first.mp4", size: 1_000)
        let second = video(path: "/missing/second.mp4", size: 1_100)
        let cache = InMemoryHashCache()
        await seed(cache, video: first, hash: [UInt8](repeating: 0, count: 8))
        await seed(cache, video: second, hash: [0xff] + [UInt8](repeating: 0, count: 7))
        let extractor = CountingThrowingExtractor()
        let pipeline = SimilarityPipeline(cache: cache, extractor: extractor)

        _ = try await pipeline.process(videos: [first, second], threshold: 0.72) { _ in }

        let extractionCount = await extractor.extractionCount
        XCTAssertEqual(extractionCount, 0)
    }

    func testMissingSameSizeFilesDoNotAbortComparison() async throws {
        let first = video(path: "/missing/first.mp4", size: 1_000)
        let second = video(path: "/missing/second.mp4", size: 1_000)
        let cache = InMemoryHashCache()
        let hash = [UInt8](repeating: 0, count: 8)
        await seed(cache, video: first, hash: hash)
        await seed(cache, video: second, hash: hash)
        let pipeline = SimilarityPipeline(cache: cache)

        let result = try await pipeline.process(videos: [first, second], threshold: 0.88) { _ in }

        XCTAssertEqual(result.groups.count, 1)
    }

    func testHashConcurrencyIsCappedForLargeProcessorCounts() {
        XCTAssertEqual(SimilarityPipeline.hashConcurrencyLimit(processorCount: 2), 2)
        XCTAssertEqual(SimilarityPipeline.hashConcurrencyLimit(processorCount: 12), 4)
    }

    func testScanRelationSignatureChangesWhenFileIdentityChanges() {
        let first = video(path: "/tmp/a.mp4", size: 100)
        let changed = MediaItem(
            kind: first.kind,
            url: first.url,
            fileSize: 101,
            duration: first.duration,
            width: first.width,
            height: first.height,
            modifiedAt: first.modifiedAt,
            thumbnailData: first.thumbnailData
        )
        let hash = VideoPerceptualHash(videoID: first.id, hashBits: [UInt8](repeating: 1, count: 8))

        let original = SimilarityPipeline.scanRelationSignature(
            items: [first],
            hashes: [first.id: Data(hash.hashBits)],
            algorithmVersion: SimilarityPipeline.pairRelationAlgorithmVersion(usesFrameVerification: false)
        )
        let updated = SimilarityPipeline.scanRelationSignature(
            items: [changed],
            hashes: [changed.id: Data(hash.hashBits)],
            algorithmVersion: SimilarityPipeline.pairRelationAlgorithmVersion(usesFrameVerification: false)
        )

        XCTAssertNotEqual(original, updated)
    }

    func testScanRelationSignatureToleratesSubmillisecondModifiedDateNoise() {
        let first = MediaItem(
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/stable.mp4"),
            fileSize: 100,
            duration: 60,
            width: 1920,
            height: 1080,
            modifiedAt: Date(timeIntervalSince1970: 1_000.123_456_1),
            thumbnailData: nil
        )
        let second = MediaItem(
            kind: first.kind,
            url: first.url,
            fileSize: first.fileSize,
            duration: first.duration,
            width: first.width,
            height: first.height,
            modifiedAt: Date(timeIntervalSince1970: 1_000.123_456_4),
            thumbnailData: first.thumbnailData
        )
        let hash = Data([1, 2, 3, 4, 5, 6, 7, 8])

        let original = SimilarityPipeline.scanRelationSignature(
            items: [first],
            hashes: [first.id: hash],
            algorithmVersion: SimilarityPipeline.pairRelationAlgorithmVersion(usesFrameVerification: false)
        )
        let updated = SimilarityPipeline.scanRelationSignature(
            items: [second],
            hashes: [second.id: hash],
            algorithmVersion: SimilarityPipeline.pairRelationAlgorithmVersion(usesFrameVerification: false)
        )

        XCTAssertEqual(original, updated)
    }

    func testScanRelationSignatureUsesFingerprintInsteadOfModifiedDateAsContentIdentity() {
        let first = MediaItem(
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/fingerprint-stable.mp4"),
            fileSize: 100,
            duration: 60,
            width: 1920,
            height: 1080,
            modifiedAt: Date(timeIntervalSince1970: 1_000),
            thumbnailData: nil
        )
        let second = MediaItem(
            kind: first.kind,
            url: first.url,
            fileSize: first.fileSize,
            duration: first.duration,
            width: first.width,
            height: first.height,
            modifiedAt: Date(timeIntervalSince1970: 1_030),
            thumbnailData: first.thumbnailData
        )
        let hash = Data([1, 2, 3, 4, 5, 6, 7, 8])

        let original = SimilarityPipeline.scanRelationSignature(
            items: [first],
            hashes: [first.id: hash],
            algorithmVersion: SimilarityPipeline.pairRelationAlgorithmVersion(usesFrameVerification: false)
        )
        let updated = SimilarityPipeline.scanRelationSignature(
            items: [second],
            hashes: [second.id: hash],
            algorithmVersion: SimilarityPipeline.pairRelationAlgorithmVersion(usesFrameVerification: false)
        )

        XCTAssertEqual(original, updated)
    }

    func testScanRelationSignatureChangesWhenFingerprintChanges() {
        let item = video(path: "/tmp/hash-change.mp4", size: 100)

        let original = SimilarityPipeline.scanRelationSignature(
            items: [item],
            hashes: [item.id: Data([1, 2, 3, 4, 5, 6, 7, 8])],
            algorithmVersion: SimilarityPipeline.pairRelationAlgorithmVersion(usesFrameVerification: false)
        )
        let updated = SimilarityPipeline.scanRelationSignature(
            items: [item],
            hashes: [item.id: Data([8, 7, 6, 5, 4, 3, 2, 1])],
            algorithmVersion: SimilarityPipeline.pairRelationAlgorithmVersion(usesFrameVerification: false)
        )

        XCTAssertNotEqual(original, updated)
    }

    func testCachedVideoHashesAdvanceHashingProgress() async throws {
        let first = video(path: "/missing/cached-first.mp4", size: 1_000)
        let second = video(path: "/missing/cached-second.mp4", size: 1_100)
        let cache = InMemoryHashCache()
        await seed(cache, video: first, hash: [UInt8](repeating: 0, count: 8))
        await seed(cache, video: second, hash: [1] + [UInt8](repeating: 0, count: 7))
        let progress = VideoProgressRecorder()
        let pipeline = SimilarityPipeline(cache: cache)

        _ = try await pipeline.process(videos: [first, second], threshold: 0.72) {
            await progress.append($0)
        }

        let hashingFractions = await progress.fractions(for: .hashing)
        XCTAssertTrue(hashingFractions.contains(1))
        let hashingUpdates = await progress.updates(for: .hashing)
        let finalHashing = try XCTUnwrap(hashingUpdates.last)
        XCTAssertEqual(finalHashing.cacheKind, .fingerprint)
        XCTAssertEqual(finalHashing.cacheHits, 2)
        XCTAssertEqual(finalHashing.cacheTotal, 2)
    }

    func testCachedPairRelationSkipsFrameVerification() async throws {
        let first = video(path: "/missing/pair-cache-first.mp4", size: 1_000)
        let second = video(path: "/missing/pair-cache-second.mp4", size: 1_100)
        let cache = InMemoryHashCache()
        await seed(cache, video: first, hash: [UInt8](repeating: 0, count: 8))
        await seed(cache, video: second, hash: [0xff] + [UInt8](repeating: 0, count: 7))
        let relation = SimilarityRelation(
            firstID: first.id,
            secondID: second.id,
            score: 0.93,
            evidence: [.similarPerceptualHash]
        )
        await cache.upsertPairRelation(
            first: first,
            second: second,
            algorithmVersion: SimilarityPipeline.pairRelationAlgorithmVersion(usesFrameVerification: true),
            relation: relation
        )
        let extractor = CountingThrowingExtractor()
        let progress = VideoProgressRecorder()
        let pipeline = SimilarityPipeline(cache: cache, extractor: extractor, usesFrameVerification: true)

        let result = try await pipeline.process(videos: [first, second], threshold: 0.88) {
            await progress.append($0)
        }

        let extractionCount = await extractor.extractionCount
        XCTAssertEqual(extractionCount, 0)
        XCTAssertEqual(result.relations, [relation])
        XCTAssertEqual(result.groups.count, 1)
        let comparingUpdates = await progress.updates(for: .comparing)
        let relationCacheUpdate = comparingUpdates.first { $0.cacheTotal == 1 }
        let cachedComparing = try XCTUnwrap(relationCacheUpdate)
        XCTAssertEqual(cachedComparing.cacheHits, 1)
        XCTAssertEqual(cachedComparing.cacheKind.map { "\($0)" }, "relation")
        XCTAssertEqual(cachedComparing.comparisonPhase, .checkingPairCache)
        XCTAssertEqual(
            L10n.scanProgressDetail(cachedComparing, .english),
            "Checking pair cache: hits 1 of 1 - pair-cache-first.mp4"
        )
    }

    func testCachedPairRelationUsesBatchLookupDuringComparison() async throws {
        let first = video(path: "/missing/batch-pair-cache-first.mp4", size: 1_000)
        let second = video(path: "/missing/batch-pair-cache-second.mp4", size: 1_100)
        let cache = VideoPairRelationBatchRecordingCache()
        await cache.seed(video: first, hash: [UInt8](repeating: 0, count: 8))
        await cache.seed(video: second, hash: [0xff] + [UInt8](repeating: 0, count: 7))
        await cache.seedRelation(
            first: first,
            second: second,
            algorithmVersion: SimilarityPipeline.pairRelationAlgorithmVersion(usesFrameVerification: false),
            entry: PairRelationCacheEntry(score: 0.93, evidence: [.similarPerceptualHash])
        )
        let pipeline = SimilarityPipeline(cache: cache)

        let result = try await pipeline.process(videos: [first, second], threshold: 0.88) { _ in }

        XCTAssertEqual(result.groups.count, 1)
        let pairBatchLookupCount = await cache.pairBatchLookupCount
        let pairSingleLookupCount = await cache.pairSingleLookupCount
        XCTAssertEqual(pairBatchLookupCount, 1)
        XCTAssertEqual(pairSingleLookupCount, 0)
    }

    func testCachedPairRelationsAreLookedUpOnceForWholeComparisonPhase() async throws {
        let videos = [
            video(path: "/missing/bulk-pair-cache-1.mp4", size: 1_000),
            video(path: "/missing/bulk-pair-cache-2.mp4", size: 1_100),
            video(path: "/missing/bulk-pair-cache-3.mp4", size: 1_200),
            video(path: "/missing/bulk-pair-cache-4.mp4", size: 1_300)
        ]
        let cache = VideoPairRelationBatchRecordingCache()
        for video in videos {
            await cache.seed(video: video, hash: [UInt8](repeating: 0, count: 8))
        }
        for firstIndex in videos.indices {
            for secondIndex in videos.indices.dropFirst(firstIndex + 1) {
                await cache.seedRelation(
                    first: videos[firstIndex],
                    second: videos[secondIndex],
                    algorithmVersion: SimilarityPipeline.pairRelationAlgorithmVersion(usesFrameVerification: false),
                    entry: PairRelationCacheEntry(score: 0.93, evidence: [.similarPerceptualHash])
                )
            }
        }
        let pipeline = SimilarityPipeline(cache: cache)

        let result = try await pipeline.process(videos: videos, threshold: 0.88) { _ in }

        XCTAssertEqual(result.relations.count, 6)
        XCTAssertEqual(result.groups.count, 1)
        let pairBatchLookupCount = await cache.pairBatchLookupCount
        let pairSingleLookupCount = await cache.pairSingleLookupCount
        XCTAssertEqual(pairBatchLookupCount, 1)
        XCTAssertEqual(pairSingleLookupCount, 0)
    }

    func testUnchangedVideoScanUsesScanRelationIndexAndSkipsCandidateLookup() async throws {
        let first = video(path: "/missing/index-first.mp4", size: 1_000)
        let second = video(path: "/missing/index-second.mp4", size: 1_100)
        let cache = VideoPairRelationBatchRecordingCache()
        await cache.seed(video: first, hash: [UInt8](repeating: 0, count: 8))
        await cache.seed(video: second, hash: [0xff] + [UInt8](repeating: 0, count: 7))
        await cache.seedScanRelationIndex(
            items: [first, second],
            algorithmVersion: SimilarityPipeline.pairRelationAlgorithmVersion(usesFrameVerification: false),
            relations: [
                CachedScanRelation(
                    firstPath: first.url.path,
                    secondPath: second.url.path,
                    score: 0.93,
                    evidence: [.similarPerceptualHash]
                )
            ]
        )
        let pipeline = SimilarityPipeline(cache: cache)

        let result = try await pipeline.process(videos: [first, second], threshold: 0.88) { _ in }

        XCTAssertEqual(result.relations.count, 1)
        let pairBatchLookupCount = await cache.pairBatchLookupCount
        XCTAssertEqual(pairBatchLookupCount, 0)
    }

    func testUncachedPairComparisonProgressDoesNotRepeatStaleRelationCacheStats() async throws {
        let first = video(path: "/missing/miss-progress-first.mp4", size: 1_000)
        let second = video(path: "/missing/miss-progress-second.mp4", size: 1_100)
        let cache = InMemoryHashCache()
        await seed(cache, video: first, hash: [UInt8](repeating: 0, count: 8))
        await seed(cache, video: second, hash: [0xff] + [UInt8](repeating: 0, count: 7))
        let progress = VideoProgressRecorder()
        let pipeline = SimilarityPipeline(cache: cache)

        _ = try await pipeline.process(videos: [first, second], threshold: 0.88) {
            await progress.append($0)
        }

        let comparingUpdates = await progress.updates(for: .comparing)
        let finalComparing = try XCTUnwrap(comparingUpdates.last)
        XCTAssertEqual(finalComparing.fraction, 1)
        XCTAssertEqual(finalComparing.currentFile, first.filename)
        XCTAssertNil(finalComparing.cacheKind)
        XCTAssertEqual(finalComparing.cacheHits, 0)
        XCTAssertEqual(finalComparing.cacheTotal, 0)
        XCTAssertEqual(finalComparing.comparisonPhase, .comparingUncached)
        XCTAssertEqual(finalComparing.comparisonCompleted, 1)
        XCTAssertEqual(finalComparing.comparisonTotal, 1)
    }

    func testVideoComparisonProgressReportsCandidateCacheAndUncachedPhases() async throws {
        let first = video(path: "/missing/phase-first.mp4", size: 1_000)
        let second = video(path: "/missing/phase-second.mp4", size: 1_100)
        let cache = InMemoryHashCache()
        await seed(cache, video: first, hash: [UInt8](repeating: 0, count: 8))
        await seed(cache, video: second, hash: [0xff] + [UInt8](repeating: 0, count: 7))
        let progress = VideoProgressRecorder()
        let pipeline = SimilarityPipeline(cache: cache)

        _ = try await pipeline.process(videos: [first, second], threshold: 0.88) {
            await progress.append($0)
        }

        let comparingUpdates = await progress.updates(for: .comparing)
        let firstComparing = try XCTUnwrap(comparingUpdates.first)
        XCTAssertEqual(firstComparing.comparisonPhase, .findingCandidates)
        XCTAssertEqual(firstComparing.comparisonCompleted, 0)
        XCTAssertEqual(firstComparing.comparisonTotal, 2)
        let finding = try XCTUnwrap(comparingUpdates.last { $0.comparisonPhase == .findingCandidates })
        XCTAssertEqual(finding.comparisonCompleted, 2)
        XCTAssertEqual(finding.comparisonTotal, 2)
        let checking = try XCTUnwrap(comparingUpdates.first { $0.comparisonPhase == .checkingPairCache })
        XCTAssertEqual(checking.cacheHits, 0)
        XCTAssertEqual(checking.cacheTotal, 1)
        let uncached = try XCTUnwrap(comparingUpdates.last { $0.comparisonPhase == .comparingUncached })
        XCTAssertEqual(uncached.comparisonCompleted, 1)
        XCTAssertEqual(uncached.comparisonTotal, 1)
    }

    func testIncrementalScanIndexReuseForAddedFileIsFutureWork() async throws {
        let existing = [
            video(path: "/missing/incremental-existing-1.mp4", size: 1_000),
            video(path: "/missing/incremental-existing-2.mp4", size: 1_100)
        ]
        let added = video(path: "/missing/incremental-added.mp4", size: 1_200)
        let cache = VideoPairRelationBatchRecordingCache()
        for item in existing + [added] {
            await cache.seed(video: item, hash: [UInt8](repeating: 0, count: 8))
        }
        await cache.seedScanRelationIndex(
            items: existing,
            algorithmVersion: SimilarityPipeline.pairRelationAlgorithmVersion(usesFrameVerification: false),
            relations: [
                CachedScanRelation(
                    firstPath: existing[0].url.path,
                    secondPath: existing[1].url.path,
                    score: 0.93,
                    evidence: [.similarPerceptualHash]
                )
            ]
        )
        let pipeline = SimilarityPipeline(cache: cache)

        _ = try await pipeline.process(videos: existing + [added], threshold: 0.88) { _ in }

        XCTExpectFailure("Incremental scan relation index reuse is the next pass: old-old pairs should come from the prior scan index, while only new/changed pairs are probed.")
        let lastPairBatchLookupKeyCount = await cache.lastPairBatchLookupKeyCount
        XCTAssertEqual(lastPairBatchLookupKeyCount, 2)
    }

    private func video(path: String, size: Int64) -> MediaItem {
        MediaItem(
            kind: .video,
            url: URL(fileURLWithPath: path),
            fileSize: size,
            duration: 60,
            width: 1920,
            height: 1080,
            modifiedAt: nil,
            thumbnailData: nil
        )
    }

    private func seed(_ cache: InMemoryHashCache, video: MediaItem, hash: [UInt8]) async {
        let prehash = QuickPrehasher.prehash(for: video)
        await cache.upsert(CacheRecord.make(
            video: video,
            perceptualHash: VideoPerceptualHash(videoID: video.id, hashBits: hash),
            quickPrehash: prehash
        ))
    }
}

private actor CountingThrowingExtractor: FrameFeatureExtracting {
    private(set) var extractionCount = 0

    func features(for url: URL) async throws -> FrameFeatures {
        extractionCount += 1
        throw CocoaError(.fileReadCorruptFile)
    }

    func similarity(between first: FrameFeatures, and second: FrameFeatures) async throws -> Double? {
        nil
    }
}

private actor VideoProgressRecorder {
    private var updates: [ScanProgress] = []

    func append(_ update: ScanProgress) {
        updates.append(update)
    }

    func fractions(for stage: ScanStage) -> [Double] {
        updates.filter { $0.stage == stage }.map(\.fraction)
    }

    func updates(for stage: ScanStage) -> [ScanProgress] {
        updates.filter { $0.stage == stage }
    }
}

private actor VideoPairRelationBatchRecordingCache: HashCaching {
    private var hashes: [String: CacheRecord] = [:]
    private var relations: [PairRelationCacheKey: PairRelationCacheEntry] = [:]
    private var scanIndexes: [String: CachedScanRelationIndex] = [:]
    private(set) var pairBatchLookupCount = 0
    private(set) var pairSingleLookupCount = 0
    private(set) var lastPairBatchLookupKeyCount = 0

    func seed(video: MediaItem, hash: [UInt8]) {
        let prehash = QuickPrehasher.prehash(for: video)
        var record = CacheRecord.make(
            video: video,
            perceptualHash: VideoPerceptualHash(videoID: video.id, hashBits: hash),
            quickPrehash: prehash
        )
        record.mediaKind = MediaKind.video.rawValue
        record.algorithmVersion = "video-dct3d-v1"
        hashes[video.url.path] = record
    }

    func seedRelation(first: MediaItem, second: MediaItem, algorithmVersion: String, entry: PairRelationCacheEntry) {
        guard let key = PairRelationCacheKey(first: first, second: second, algorithmVersion: algorithmVersion) else { return }
        relations[key] = entry
    }

    func seedScanRelationIndex(items: [MediaItem], algorithmVersion: String, relations: [CachedScanRelation]) {
        let hashData = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (UUID, Data)? in
            guard let record = hashes[item.url.path] else { return nil }
            return (item.id, record.perceptualHash)
        })
        let signature = SimilarityPipeline.scanRelationSignature(
            items: items,
            hashes: hashData,
            algorithmVersion: algorithmVersion
        )
        let index = CachedScanRelationIndex(
            signature: signature,
            mediaKind: .video,
            algorithmVersion: algorithmVersion,
            fileCount: items.count,
            candidateCount: relations.count,
            relations: relations
        )
        scanIndexes[scanIndexKey(signature: signature, mediaKind: .video, algorithmVersion: algorithmVersion)] = index
    }

    func lookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, algorithmVersion: String) -> CacheRecord? {
        hashes[filePath]
    }

    func upsert(_ record: CacheRecord) {}
    func pruneStale(validPaths: Set<String>) {}
    func count() -> Int { hashes.count }
    func clearAll() {}
    func sizeInBytes() -> Int64 { 0 }

    func lookupPairRelation(first: MediaItem, second: MediaItem, algorithmVersion: String) async -> PairRelationCacheEntry? {
        pairSingleLookupCount += 1
        guard let key = PairRelationCacheKey(first: first, second: second, algorithmVersion: algorithmVersion) else { return nil }
        return relations[key]
    }

    func lookupPairRelations(keys: [PairRelationCacheKey]) -> [PairRelationCacheKey: PairRelationCacheEntry] {
        pairBatchLookupCount += 1
        lastPairBatchLookupKeyCount = keys.count
        return keys.reduce(into: [:]) { result, key in
            if let entry = relations[key] { result[key] = entry }
        }
    }

    func lookupScanRelationIndex(signature: String, mediaKind: MediaKind, algorithmVersion: String) -> CachedScanRelationIndex? {
        scanIndexes[scanIndexKey(signature: signature, mediaKind: mediaKind, algorithmVersion: algorithmVersion)]
    }

    private func scanIndexKey(signature: String, mediaKind: MediaKind, algorithmVersion: String) -> String {
        "\(signature)\u{0}\(mediaKind.rawValue)\u{0}\(algorithmVersion)"
    }
}
