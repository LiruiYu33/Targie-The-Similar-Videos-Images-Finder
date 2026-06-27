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
        XCTAssertEqual(
            L10n.scanProgressDetail(cachedComparing, .english),
            "Pair comparison cache hits: 1 of 1 - pair-cache-first.mp4"
        )
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
