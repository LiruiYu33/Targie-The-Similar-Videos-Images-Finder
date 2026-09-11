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
import CoreGraphics
@preconcurrency import Vision
@testable import SimilarVideoFinder

final class FrameFeatureExtractorTests: XCTestCase {
    func testPreviousFrameFeatureVersionIsReextractedAndThenReused() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FrameVersion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("video.mp4")
        try Data([1, 2, 3, 4]).write(to: url)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let persistentCache = InMemoryHashCache()
        let completeFeatures = try makeCompleteFeatures()
        await persistentCache.upsertFrameFeature(
            filePath: url.path, fileSize: Int64(try XCTUnwrap(values.fileSize)),
            modifiedAt: values.contentModificationDate, algorithmVersion: "vision-frame-feature-v2-revision2",
            featureData: try FrameFeatureSerializer.serialize(completeFeatures)
        )
        let extractor = CountingFrameFeatureExtractor(results: [completeFeatures])
        let firstCache = FrameFeatureCache(extractor: extractor, persistentCache: persistentCache)
        let secondCache = FrameFeatureCache(extractor: extractor, persistentCache: persistentCache)
        _ = try await firstCache.features(for: url)
        _ = try await secondCache.features(for: url)
        let count = await extractor.count(for: url)
        XCTAssertEqual(count, 1)
    }

    func testAggregationRequiresTwoSamplesAndIgnoresMissingValues() {
        XCTAssertNil(FrameSimilarityAggregator.aggregate([0.9, nil]))
        let result = FrameSimilarityAggregator.aggregate([0.9, nil, 0.7])
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 0.8, accuracy: 0.0001)
    }

    func testFeatureCacheExtractsEachVideoOnlyOnce() async throws {
        let extractor = CountingFrameFeatureExtractor()
        let cache = FrameFeatureCache(extractor: extractor)
        let first = URL(fileURLWithPath: "/tmp/first.mp4")
        let second = URL(fileURLWithPath: "/tmp/second.mp4")

        _ = try await cache.features(for: first)
        _ = try await cache.features(for: first)
        _ = try await cache.features(for: second)
        _ = try await cache.features(for: first)

        let firstCount = await extractor.count(for: first)
        let secondCount = await extractor.count(for: second)
        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 1)
    }

    func testFeatureCacheCoalescesConcurrentRequestsForSameVideo() async throws {
        let extractor = CountingFrameFeatureExtractor(delayNanoseconds: 50_000_000)
        let cache = FrameFeatureCache(extractor: extractor)
        let url = URL(fileURLWithPath: "/tmp/concurrent-video.mp4")

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    _ = try await cache.features(for: url)
                }
            }
            try await group.waitForAll()
        }

        let count = await extractor.count(for: url)
        XCTAssertEqual(count, 1)
    }

    func testFeatureCacheRetriesAfterFailedTask() async {
        let extractor = CountingFrameFeatureExtractor(alwaysFails: true)
        let cache = FrameFeatureCache(extractor: extractor)
        let url = URL(fileURLWithPath: "/tmp/retry-video.mp4")

        for _ in 0..<2 {
            do {
                _ = try await cache.features(for: url)
                XCTFail("Feature extraction should fail")
            } catch {
                // A failed in-flight task must be removed so the next call retries.
            }
        }

        let count = await extractor.count(for: url)
        XCTAssertEqual(count, 2)
    }

    func testCancellingOnlyFeatureWaiterCancelsWorkAndAllowsRetry() async throws {
        let extractor = CountingFrameFeatureExtractor(delayNanoseconds: 100_000_000)
        let cache = FrameFeatureCache(extractor: extractor)
        let url = URL(fileURLWithPath: "/tmp/cancelled-feature-video.mp4")
        let firstRequest = Task {
            try await cache.features(for: url)
        }

        for _ in 0..<100 {
            if await extractor.count(for: url) == 1 { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        firstRequest.cancel()

        do {
            _ = try await firstRequest.value
            XCTFail("Cancelling the only waiter should cancel feature extraction")
        } catch is CancellationError {
            // Expected.
        }

        _ = try await cache.features(for: url)
        let count = await extractor.count(for: url)
        XCTAssertEqual(count, 2)
    }

    func testFeatureCachePersistsFeaturesAcrossCacheInstances() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameFeatureCachePersistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("video.mp4")
        try Data([1, 2, 3, 4]).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 6_000)],
            ofItemAtPath: url.path
        )
        let completeFeatures = try makeCompleteFeatures()
        let extractor = CountingFrameFeatureExtractor(results: [completeFeatures])
        let persistentCache = try HashCache(databaseURL: root.appendingPathComponent("frames.sqlite"))
        let firstCache = FrameFeatureCache(extractor: extractor, persistentCache: persistentCache)
        let secondCache = FrameFeatureCache(extractor: extractor, persistentCache: persistentCache)

        let first = try await firstCache.features(for: url)
        let second = try await secondCache.features(for: url)

        let count = await extractor.count(for: url)
        XCTAssertEqual(count, 1)
        XCTAssertTrue(first.isCompleteForPersistence)
        XCTAssertTrue(second.isCompleteForPersistence)
        let similarity = try await FrameFeatureExtractor().similarity(between: first, and: second)
        XCTAssertEqual(try XCTUnwrap(similarity), 1, accuracy: 0.0001)
    }

    func testIncompletePersistentFeaturesAreReextractedBeforeReuse() async throws {
        let url = try makeVideoFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let complete = try makeCompleteFeatures()
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let observation = try XCTUnwrap(complete.observations.first ?? nil)
        let incompleteResults = [
            FrameFeatures(observations: []),
            FrameFeatures(observations: Array(repeating: nil, count: 5)),
            FrameFeatures(observations: [observation, observation, nil, observation, observation]),
            FrameFeatures(observations: Array(repeating: observation, count: 4))
        ]

        for incomplete in incompleteResults {
            let persistentCache = InMemoryHashCache()
            await persistentCache.upsertFrameFeature(
                filePath: url.path, fileSize: Int64(try XCTUnwrap(values.fileSize)),
                modifiedAt: values.contentModificationDate,
                algorithmVersion: FrameFeatureExtractor.algorithmVersion,
                featureData: try FrameFeatureSerializer.serialize(incomplete)
            )
            let extractor = CountingFrameFeatureExtractor(results: [complete])
            let firstCache = FrameFeatureCache(extractor: extractor, persistentCache: persistentCache)
            let secondCache = FrameFeatureCache(extractor: extractor, persistentCache: persistentCache)

            let first = try await firstCache.features(for: url)
            let second = try await secondCache.features(for: url)

            XCTAssertTrue(first.isCompleteForPersistence)
            XCTAssertTrue(second.isCompleteForPersistence)
            let count = await extractor.count(for: url)
            XCTAssertEqual(count, 1)
        }
    }

    func testLegacyObservationsUnderCurrentCacheVersionAreReextracted() async throws {
        let url = try makeVideoFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let legacy = try makeCompleteFeatures(revision: VNGenerateImageFeaturePrintRequestRevision1)
        let complete = try makeCompleteFeatures()
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let persistentCache = InMemoryHashCache()
        await persistentCache.upsertFrameFeature(
            filePath: url.path, fileSize: Int64(try XCTUnwrap(values.fileSize)),
            modifiedAt: values.contentModificationDate,
            algorithmVersion: FrameFeatureExtractor.algorithmVersion,
            featureData: try FrameFeatureSerializer.serialize(legacy)
        )
        let extractor = CountingFrameFeatureExtractor(results: [complete])
        let firstCache = FrameFeatureCache(extractor: extractor, persistentCache: persistentCache)
        let secondCache = FrameFeatureCache(extractor: extractor, persistentCache: persistentCache)

        let first = try await firstCache.features(for: url)
        let second = try await secondCache.features(for: url)

        XCTAssertTrue(first.isCompleteForPersistence)
        XCTAssertTrue(second.isCompleteForPersistence)
        let count = await extractor.count(for: url)
        XCTAssertEqual(count, 1)
    }

    func testIncompleteExtractionIsSharedWithinScanButRetriedOnNextScan() async throws {
        let url = try makeVideoFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let complete = try makeCompleteFeatures()
        let observation = try XCTUnwrap(complete.observations.first ?? nil)
        let incompatible = try makeCompleteFeatures(revision: VNGenerateImageFeaturePrintRequestRevision1)
        let initialResults = [
            FrameFeatures(observations: []),
            FrameFeatures(observations: Array(repeating: nil, count: 5)),
            FrameFeatures(observations: [observation, observation, nil, observation, observation]),
            FrameFeatures(observations: Array(repeating: observation, count: 4)),
            incompatible
        ]

        for initial in initialResults {
            let persistentCache = InMemoryHashCache()
            let extractor = CountingFrameFeatureExtractor(results: [initial, complete])
            let firstScan = FrameFeatureCache(extractor: extractor, persistentCache: persistentCache)
            let first = try await firstScan.features(for: url)
            let repeated = try await firstScan.features(for: url)
            XCTAssertFalse(first.isCompleteForPersistence)
            XCTAssertFalse(repeated.isCompleteForPersistence)
            let firstCount = await extractor.count(for: url)
            XCTAssertEqual(firstCount, 1, "A failed frame should not repeatedly decode within one scan")

            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let persistedFailure = await persistentCache.lookupFrameFeature(
                filePath: url.path, fileSize: Int64(try XCTUnwrap(values.fileSize)),
                modifiedAt: values.contentModificationDate,
                algorithmVersion: FrameFeatureExtractor.algorithmVersion
            )
            XCTAssertNil(persistedFailure, "An incomplete extraction must not become a cross-scan cache hit")

            let nextScan = FrameFeatureCache(extractor: extractor, persistentCache: persistentCache)
            let recovered = try await nextScan.features(for: url)
            XCTAssertTrue(recovered.isCompleteForPersistence)
            let finalScan = FrameFeatureCache(extractor: extractor, persistentCache: persistentCache)
            let persistedSuccess = try await finalScan.features(for: url)
            XCTAssertTrue(persistedSuccess.isCompleteForPersistence)
            let finalCount = await extractor.count(for: url)
            XCTAssertEqual(finalCount, 2, "Successful retry should be reusable on subsequent scans")
        }
    }

    private func makeVideoFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FrameCache-\(UUID().uuidString).mp4")
        try Data([1, 2, 3, 4]).write(to: url)
        return url
    }

    private func makeCompleteFeatures(
        revision: Int = VNGenerateImageFeaturePrintRequestRevision2
    ) throws -> FrameFeatures {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 512,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 20, y: 15, width: 45, height: 80))
        context.setFillColor(CGColor(gray: 0.2, alpha: 1))
        context.fillEllipse(in: CGRect(x: 75, y: 55, width: 35, height: 40))
        let image = try XCTUnwrap(context.makeImage())
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = revision
        try VNImageRequestHandler(cgImage: image).perform([request])
        let observation = try XCTUnwrap(request.results?.first as? VNFeaturePrintObservation)
        XCTAssertEqual(observation.requestRevision, revision)
        XCTAssertGreaterThan(observation.elementCount, 0)
        return FrameFeatures(observations: Array(repeating: observation, count: 5))
    }
}

private actor CountingFrameFeatureExtractor: FrameFeatureExtracting {
    enum Failure: Error {
        case extractionFailed
    }

    private var counts: [URL: Int] = [:]
    private let delayNanoseconds: UInt64
    private let alwaysFails: Bool
    private let results: [FrameFeatures]

    init(
        delayNanoseconds: UInt64 = 0,
        alwaysFails: Bool = false,
        results: [FrameFeatures] = [FrameFeatures(observations: [])]
    ) {
        precondition(!results.isEmpty)
        self.delayNanoseconds = delayNanoseconds
        self.alwaysFails = alwaysFails
        self.results = results
    }

    func features(for url: URL) async throws -> FrameFeatures {
        counts[url, default: 0] += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if alwaysFails {
            throw Failure.extractionFailed
        }
        return results[min(counts[url, default: 1] - 1, results.count - 1)]
    }

    func similarity(between first: FrameFeatures, and second: FrameFeatures) async throws -> Double? {
        nil
    }

    func count(for url: URL) -> Int {
        counts[url, default: 0]
    }
}
