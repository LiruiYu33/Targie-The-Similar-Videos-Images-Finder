// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SimilarVideoFinder

final class ImageSimilarityPipelineTests: XCTestCase {
    func testImageComparisonConcurrencyDropsWhenThermalStateIsHigh() {
        XCTAssertEqual(
            ImageSimilarityPipeline.comparisonConcurrencyLimit(processorCount: 12, thermalState: .nominal),
            6
        )
        XCTAssertEqual(
            ImageSimilarityPipeline.comparisonConcurrencyLimit(processorCount: 12, thermalState: .serious),
            2
        )
        XCTAssertEqual(
            ImageSimilarityPipeline.comparisonConcurrencyLimit(processorCount: 12, thermalState: .critical),
            1
        )
    }

    func testExactDuplicateImagesFormAGroup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ImagePipeline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.png")
        let second = root.appendingPathComponent("second.png")
        try writePattern(to: first)
        try FileManager.default.copyItem(at: first, to: second)
        let scan = try await ImageScanner().scan(folder: root) { _ in }

        let result = try await ImageSimilarityPipeline(cache: InMemoryHashCache()).process(images: scan.images, threshold: 0.88) { _ in }
        let groups = SimilarityGrouper.groups(items: result.images, relations: result.relations, threshold: 0.88)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].items.count, 2)
        XCTAssertEqual(groups[0].kind, .image)
    }

    func testCachedImageHashesAdvanceHashingProgress() async throws {
        let image = MediaItem(
            kind: .image,
            url: URL(fileURLWithPath: "/tmp/cached-image.jpg"),
            fileSize: 10,
            duration: nil,
            width: 40,
            height: 20,
            modifiedAt: nil,
            thumbnailData: nil
        )
        let cache = InMemoryHashCache()
        var record = CacheRecord(
            filePath: image.url.path,
            fileSize: image.fileSize,
            modifiedAt: image.modifiedAt,
            perceptualHash: Data([0, 1, 2, 3, 4, 5, 6, 7]),
            prehashDurationBucket: 0,
            prehashSizeBucket: 0,
            prehashAspectBucket: 0,
            prehashThumbnailMean: 0,
            prehashThumbnailVariance: 0
        )
        record.mediaKind = MediaKind.image.rawValue
        record.algorithmVersion = ImageSimilarityPipeline.algorithmVersion
        await cache.upsert(record)
        let progress = ImageProgressRecorder()

        _ = try await ImageSimilarityPipeline(cache: cache).process(images: [image], threshold: 0.88) {
            await progress.append($0)
        }

        let hashingFractions = await progress.fractions(for: .hashing)
        XCTAssertTrue(hashingFractions.contains(1))
        let hashingUpdates = await progress.updates(for: .hashing)
        let finalHashing = try XCTUnwrap(hashingUpdates.last)
        XCTAssertEqual(finalHashing.cacheKind, .fingerprint)
        XCTAssertEqual(finalHashing.cacheHits, 1)
        XCTAssertEqual(finalHashing.cacheTotal, 1)
    }

    func testCancellingImageHashingPropagatesCancellation() async throws {
        let image = image(path: "/tmp/cancelled-image.jpg", size: 10)
        let provider = BlockingImagePerceptualHashProvider()
        let pipeline = ImageSimilarityPipeline(
            perceptualHashProvider: { url, id in
                try await provider.hash(for: url, id: id)
            }
        )
        let task = Task {
            try await pipeline.process(images: [image], threshold: 0.88) { _ in }
        }

        for _ in 0..<100 {
            if await provider.hasStarted { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let hasStarted = await provider.hasStarted
        XCTAssertTrue(hasStarted)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Image hashing cancellation should reach the pipeline caller")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testCancellingImageFeatureComparisonPropagatesCancellation() async throws {
        let first = image(path: "/missing/cancel-feature-first.jpg", size: 1_000)
        let second = image(path: "/missing/cancel-feature-second.jpg", size: 1_100)
        let cache = InMemoryHashCache()
        await seed(cache, image: first, hash: [UInt8](repeating: 0, count: 8))
        await seed(cache, image: second, hash: [0xff] + [UInt8](repeating: 0, count: 7))
        let extractor = CountingThrowingImageFeatureExtractor(delayNanoseconds: 30_000_000_000)
        let pipeline = ImageSimilarityPipeline(cache: cache, featureExtractor: extractor)
        let task = Task {
            try await pipeline.process(images: [first, second], threshold: 0.88) { _ in }
        }

        for _ in 0..<100 {
            if extractor.extractionCount > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(extractor.extractionCount, 0)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Image feature comparison cancellation should reach the pipeline caller")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testCachedPairRelationSkipsImageFeatureExtraction() async throws {
        let first = image(path: "/missing/pair-cache-first.jpg", size: 1_000)
        let second = image(path: "/missing/pair-cache-second.jpg", size: 1_100)
        let cache = InMemoryHashCache()
        await seed(cache, image: first, hash: [UInt8](repeating: 0, count: 8))
        await seed(cache, image: second, hash: [0xff] + [UInt8](repeating: 0, count: 7))
        let relation = SimilarityRelation(
            firstID: first.id,
            secondID: second.id,
            score: 0.92,
            evidence: [.similarPerceptualHash]
        )
        await cache.upsertPairRelation(
            first: first,
            second: second,
            algorithmVersion: ImageSimilarityPipeline.pairRelationAlgorithmVersion,
            relation: relation
        )
        let extractor = CountingThrowingImageFeatureExtractor()
        let progress = ImageProgressRecorder()
        let pipeline = ImageSimilarityPipeline(cache: cache, featureExtractor: extractor)

        let result = try await pipeline.process(images: [first, second], threshold: 0.88) {
            await progress.append($0)
        }

        XCTAssertEqual(extractor.extractionCount, 0)
        XCTAssertEqual(result.relations, [relation])
        XCTAssertEqual(
            SimilarityGrouper.groups(items: result.images, relations: result.relations, threshold: 0.88).count,
            1
        )
        let comparingUpdates = await progress.updates(for: .comparing)
        let relationCacheUpdate = comparingUpdates.first { $0.cacheTotal == 1 }
        let cachedComparing = try XCTUnwrap(relationCacheUpdate)
        XCTAssertEqual(cachedComparing.cacheHits, 1)
        XCTAssertEqual(cachedComparing.cacheKind.map { "\($0)" }, "relation")
        XCTAssertEqual(cachedComparing.comparisonPhase, .checkingPairCache)
        XCTAssertEqual(
            L10n.scanProgressDetail(cachedComparing, .english),
            "Checking pair cache: hits 1 of 1 - pair-cache-first.jpg"
        )
    }

    func testV1ImagePairRelationDoesNotSkipV2FeatureExtraction() async throws {
        let first = image(path: "/missing/v1-pair-first.jpg", size: 1_000)
        let second = image(path: "/missing/v1-pair-second.jpg", size: 1_100)
        let cache = InMemoryHashCache()
        await seed(cache, image: first, hash: [UInt8](repeating: 0, count: 8))
        await seed(cache, image: second, hash: [0xff] + [UInt8](repeating: 0, count: 7))
        await cache.upsertPairRelation(
            first: first,
            second: second,
            algorithmVersion: "image-pair-relation-v1",
            relation: SimilarityRelation(
                firstID: first.id,
                secondID: second.id,
                score: 0.99,
                evidence: [.similarFrames]
            )
        )
        let extractor = CountingThrowingImageFeatureExtractor()
        let pipeline = ImageSimilarityPipeline(cache: cache, featureExtractor: extractor)

        _ = try await pipeline.process(images: [first, second], threshold: 0.88) { _ in }

        XCTAssertGreaterThan(extractor.extractionCount, 0)
    }

    func testImageFeatureCacheCoalescesConcurrentRequestsForSameURL() async {
        let extractor = CountingThrowingImageFeatureExtractor(delayNanoseconds: 50_000_000)
        let cache = ImageFeatureCache(extractor: extractor)
        let url = URL(fileURLWithPath: "/tmp/concurrent-feature.jpg")

        let failures = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    do {
                        _ = try await cache.feature(for: url)
                        return false
                    } catch {
                        return true
                    }
                }
            }

            var values: [Bool] = []
            for await value in group {
                values.append(value)
            }
            return values
        }

        XCTAssertTrue(failures.allSatisfy { $0 })
        XCTAssertEqual(extractor.extractionCount, 1)
    }

    func testImageFeatureCacheRetriesAfterFailedTask() async {
        let extractor = CountingThrowingImageFeatureExtractor()
        let cache = ImageFeatureCache(extractor: extractor)
        let url = URL(fileURLWithPath: "/tmp/retry-feature.jpg")

        for _ in 0..<2 {
            do {
                _ = try await cache.feature(for: url)
                XCTFail("Feature extraction should fail")
            } catch {
                // A failed in-flight task must be removed so the next call retries.
            }
        }

        XCTAssertEqual(extractor.extractionCount, 2)
    }

    func testCachedPairRelationUsesBatchLookupDuringComparison() async throws {
        let first = image(path: "/missing/batch-pair-cache-first.jpg", size: 1_000)
        let second = image(path: "/missing/batch-pair-cache-second.jpg", size: 1_100)
        let cache = ImagePairRelationBatchRecordingCache()
        await cache.seed(image: first, hash: [UInt8](repeating: 0, count: 8))
        await cache.seed(image: second, hash: [0xff] + [UInt8](repeating: 0, count: 7))
        await cache.seedRelation(
            first: first,
            second: second,
            algorithmVersion: ImageSimilarityPipeline.pairRelationAlgorithmVersion,
            entry: PairRelationCacheEntry(score: 0.92, evidence: [.similarPerceptualHash])
        )
        let pipeline = ImageSimilarityPipeline(cache: cache)

        let result = try await pipeline.process(images: [first, second], threshold: 0.88) { _ in }

        XCTAssertEqual(
            SimilarityGrouper.groups(items: result.images, relations: result.relations, threshold: 0.88).count,
            1
        )
        let pairBatchLookupCount = await cache.pairBatchLookupCount
        let pairSingleLookupCount = await cache.pairSingleLookupCount
        XCTAssertEqual(pairBatchLookupCount, 1)
        XCTAssertEqual(pairSingleLookupCount, 0)
    }

    func testUncachedImagePairRelationsAreWrittenInBatches() async throws {
        let first = image(path: "/missing/batch-write-image-a.jpg", size: 1_000)
        let second = image(path: "/missing/batch-write-image-b.jpg", size: 1_100)
        let cache = ImagePairRelationBatchRecordingCache()
        await cache.seed(image: first, hash: [UInt8](repeating: 0, count: 8))
        await cache.seed(image: second, hash: [1] + [UInt8](repeating: 0, count: 7))
        let pipeline = ImageSimilarityPipeline(cache: cache, featureExtractor: CountingThrowingImageFeatureExtractor())

        _ = try await pipeline.process(images: [first, second], threshold: 0.60) { _ in }

        let counts = await cache.pairUpsertCounts()
        XCTAssertEqual(counts.batchCalls, 1)
        XCTAssertEqual(counts.singleCalls, 0)
        XCTAssertEqual(counts.lastBatchSize, 1)
    }

    func testCachedPairRelationsAreLookedUpOnceForWholeComparisonPhase() async throws {
        let images = [
            image(path: "/missing/bulk-pair-cache-1.jpg", size: 1_000),
            image(path: "/missing/bulk-pair-cache-2.jpg", size: 1_100),
            image(path: "/missing/bulk-pair-cache-3.jpg", size: 1_200),
            image(path: "/missing/bulk-pair-cache-4.jpg", size: 1_300)
        ]
        let cache = ImagePairRelationBatchRecordingCache()
        for image in images {
            await cache.seed(image: image, hash: [UInt8](repeating: 0, count: 8))
        }
        for firstIndex in images.indices {
            for secondIndex in images.indices.dropFirst(firstIndex + 1) {
                await cache.seedRelation(
                    first: images[firstIndex],
                    second: images[secondIndex],
                    algorithmVersion: ImageSimilarityPipeline.pairRelationAlgorithmVersion,
                    entry: PairRelationCacheEntry(score: 0.92, evidence: [.similarPerceptualHash])
                )
            }
        }
        let pipeline = ImageSimilarityPipeline(cache: cache)

        let result = try await pipeline.process(images: images, threshold: 0.88) { _ in }

        XCTAssertEqual(result.relations.count, 6)
        XCTAssertEqual(
            SimilarityGrouper.groups(items: result.images, relations: result.relations, threshold: 0.88).count,
            1
        )
        let pairBatchLookupCount = await cache.pairBatchLookupCount
        let pairSingleLookupCount = await cache.pairSingleLookupCount
        XCTAssertEqual(pairBatchLookupCount, 1)
        XCTAssertEqual(pairSingleLookupCount, 0)
    }

    func testUnchangedImageScanUsesScanRelationIndexAndSkipsCandidateLookup() async throws {
        let first = image(path: "/missing/index-first.jpg", size: 1_000)
        let second = image(path: "/missing/index-second.jpg", size: 1_100)
        let cache = ImagePairRelationBatchRecordingCache()
        await cache.seed(image: first, hash: [UInt8](repeating: 0, count: 8))
        await cache.seed(image: second, hash: [0xff] + [UInt8](repeating: 0, count: 7))
        await cache.seedScanRelationIndex(
            items: [first, second],
            algorithmVersion: ImageSimilarityPipeline.pairRelationAlgorithmVersion,
            relations: [
                CachedScanRelation(
                    firstPath: first.url.path,
                    secondPath: second.url.path,
                    score: 0.92,
                    evidence: [.similarPerceptualHash]
                )
            ]
        )
        let pipeline = ImageSimilarityPipeline(cache: cache)

        let result = try await pipeline.process(images: [first, second], threshold: 0.88) { _ in }

        XCTAssertEqual(result.relations.count, 1)
        let pairBatchLookupCount = await cache.pairBatchLookupCount
        XCTAssertEqual(pairBatchLookupCount, 0)
    }

    func testImageComparisonProgressReportsCandidateCacheAndUncachedPhases() async throws {
        let first = image(path: "/missing/phase-first.jpg", size: 1_000)
        let second = image(path: "/missing/phase-second.jpg", size: 1_100)
        let cache = InMemoryHashCache()
        await seed(cache, image: first, hash: [UInt8](repeating: 0, count: 8))
        await seed(cache, image: second, hash: [0xff] + [UInt8](repeating: 0, count: 7))
        let progress = ImageProgressRecorder()
        let pipeline = ImageSimilarityPipeline(cache: cache)

        _ = try await pipeline.process(images: [first, second], threshold: 0.88) {
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

    func testUncachedImageComparisonProgressIsThrottledForLargeCandidateSets() async throws {
        let images = (0..<30).map { index in
            image(path: "/missing/throttled-image-\(index).jpg", size: 1_000 + Int64(index))
        }
        let cache = InMemoryHashCache()
        for image in images {
            await seed(cache, image: image, hash: [UInt8](repeating: 0, count: 8))
        }
        let progress = ImageProgressRecorder()
        let pipeline = ImageSimilarityPipeline(
            cache: cache,
            featureExtractor: CountingThrowingImageFeatureExtractor()
        )

        _ = try await pipeline.process(images: images, threshold: 0.88) {
            await progress.append($0)
        }

        let uncachedUpdates = await progress.updates(for: .comparing)
            .filter { $0.comparisonPhase == .comparingUncached }
        let finalUpdate = try XCTUnwrap(uncachedUpdates.last)
        XCTAssertGreaterThan(finalUpdate.comparisonTotal, 400)
        XCTAssertEqual(finalUpdate.comparisonCompleted, finalUpdate.comparisonTotal)
        XCTAssertLessThan(uncachedUpdates.count, finalUpdate.comparisonTotal / 2)
    }

    private func writePattern(to url: URL) throws {
        guard let context = CGContext(data: nil, width: 80, height: 60, bitsPerComponent: 8, bytesPerRow: 320, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        context.setFillColor(CGColor.white)
        context.fillEllipse(in: CGRect(x: 15, y: 10, width: 35, height: 35))
        guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    private func image(path: String, size: Int64) -> MediaItem {
        MediaItem(
            kind: .image,
            url: URL(fileURLWithPath: path),
            fileSize: size,
            duration: nil,
            width: 80,
            height: 60,
            modifiedAt: nil,
            thumbnailData: nil
        )
    }

    private func seed(_ cache: InMemoryHashCache, image: MediaItem, hash: [UInt8]) async {
        var record = CacheRecord(
            filePath: image.url.path,
            fileSize: image.fileSize,
            modifiedAt: image.modifiedAt,
            perceptualHash: Data(hash),
            prehashDurationBucket: 0,
            prehashSizeBucket: 0,
            prehashAspectBucket: 0,
            prehashThumbnailMean: 0,
            prehashThumbnailVariance: 0
        )
        record.mediaKind = MediaKind.image.rawValue
        record.algorithmVersion = ImageSimilarityPipeline.algorithmVersion
        await cache.upsert(record)
    }
}

private actor ImageProgressRecorder {
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

private actor BlockingImagePerceptualHashProvider {
    private(set) var hasStarted = false

    func hash(for url: URL, id: UUID) async throws -> ImagePerceptualHash? {
        hasStarted = true
        try await Task.sleep(nanoseconds: 30_000_000_000)
        return ImagePerceptualHash(mediaID: id, hashBits: [UInt8](repeating: 0, count: 8))
    }
}

private final class CountingThrowingImageFeatureExtractor: @unchecked Sendable, ImageFeatureExtracting {
    private let lock = NSLock()
    private let delayNanoseconds: UInt64
    private var count = 0

    init(delayNanoseconds: UInt64 = 0) {
        self.delayNanoseconds = delayNanoseconds
    }

    var extractionCount: Int {
        lock.withLock { count }
    }

    func feature(for url: URL) async throws -> ImageFeature {
        lock.withLock { count += 1 }
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    func similarity(between first: ImageFeature, and second: ImageFeature) throws -> Double {
        throw CocoaError(.featureUnsupported)
    }
}

private actor ImagePairRelationBatchRecordingCache: HashCaching {
    private var hashes: [String: CacheRecord] = [:]
    private var relations: [PairRelationCacheKey: PairRelationCacheEntry] = [:]
    private var scanIndexes: [String: CachedScanRelationIndex] = [:]
    private(set) var pairBatchLookupCount = 0
    private(set) var pairSingleLookupCount = 0
    private var pairBatchUpsertCount = 0
    private var pairSingleUpsertCount = 0
    private var lastPairBatchUpsertCount = 0

    func seed(image: MediaItem, hash: [UInt8]) {
        var record = CacheRecord(
            filePath: image.url.path,
            fileSize: image.fileSize,
            modifiedAt: image.modifiedAt,
            perceptualHash: Data(hash),
            prehashDurationBucket: 0,
            prehashSizeBucket: 0,
            prehashAspectBucket: 0,
            prehashThumbnailMean: 0,
            prehashThumbnailVariance: 0
        )
        record.mediaKind = MediaKind.image.rawValue
        record.algorithmVersion = ImageSimilarityPipeline.algorithmVersion
        hashes[image.url.path] = record
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
        let signature = ImageSimilarityPipeline.scanRelationSignature(
            items: items,
            hashes: hashData,
            algorithmVersion: algorithmVersion
        )
        let index = CachedScanRelationIndex(
            signature: signature,
            mediaKind: .image,
            algorithmVersion: algorithmVersion,
            fileCount: items.count,
            candidateCount: relations.count,
            relations: relations
        )
        scanIndexes[scanIndexKey(signature: signature, mediaKind: .image, algorithmVersion: algorithmVersion)] = index
    }

    func lookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, algorithmVersion: String) -> CacheRecord? {
        hashes[filePath]
    }

    func upsert(_ record: CacheRecord) {}
    func pruneStale(validPaths: Set<String>) {}
    func count() -> Int { hashes.count }
    func clearAll() {}
    func sizeInBytes() -> Int64 { 0 }

    func upsertPairRelation(first: MediaItem, second: MediaItem, algorithmVersion: String, relation: SimilarityRelation?) async {
        pairSingleUpsertCount += 1
        storePairRelation(first: first, second: second, algorithmVersion: algorithmVersion, relation: relation)
    }

    func upsertPairRelations(_ upserts: [PairRelationCacheUpsert]) async {
        pairBatchUpsertCount += 1
        lastPairBatchUpsertCount = upserts.count
        for upsert in upserts {
            storePairRelation(
                first: upsert.first,
                second: upsert.second,
                algorithmVersion: upsert.algorithmVersion,
                relation: upsert.relation
            )
        }
    }

    func lookupPairRelation(first: MediaItem, second: MediaItem, algorithmVersion: String) async -> PairRelationCacheEntry? {
        pairSingleLookupCount += 1
        guard let key = PairRelationCacheKey(first: first, second: second, algorithmVersion: algorithmVersion) else { return nil }
        return relations[key]
    }

    func lookupPairRelations(keys: [PairRelationCacheKey]) -> [PairRelationCacheKey: PairRelationCacheEntry] {
        pairBatchLookupCount += 1
        return keys.reduce(into: [:]) { result, key in
            if let entry = relations[key] { result[key] = entry }
        }
    }

    func lookupScanRelationIndex(signature: String, mediaKind: MediaKind, algorithmVersion: String) -> CachedScanRelationIndex? {
        scanIndexes[scanIndexKey(signature: signature, mediaKind: mediaKind, algorithmVersion: algorithmVersion)]
    }

    func pairUpsertCounts() -> (batchCalls: Int, singleCalls: Int, lastBatchSize: Int) {
        (pairBatchUpsertCount, pairSingleUpsertCount, lastPairBatchUpsertCount)
    }

    private func storePairRelation(first: MediaItem, second: MediaItem, algorithmVersion: String, relation: SimilarityRelation?) {
        guard let key = PairRelationCacheKey(first: first, second: second, algorithmVersion: algorithmVersion) else { return }
        relations[key] = PairRelationCacheEntry(score: relation?.score, evidence: relation?.evidence ?? [])
    }

    private func scanIndexKey(signature: String, mediaKind: MediaKind, algorithmVersion: String) -> String {
        "\(signature)\u{0}\(mediaKind.rawValue)\u{0}\(algorithmVersion)"
    }
}
