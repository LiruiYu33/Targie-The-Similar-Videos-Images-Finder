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
