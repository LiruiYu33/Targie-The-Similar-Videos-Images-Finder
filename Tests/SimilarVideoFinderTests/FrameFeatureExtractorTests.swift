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

final class FrameFeatureExtractorTests: XCTestCase {
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
        let extractor = CountingFrameFeatureExtractor()
        let persistentCache = InMemoryHashCache()
        let firstCache = FrameFeatureCache(extractor: extractor, persistentCache: persistentCache)
        let secondCache = FrameFeatureCache(extractor: extractor, persistentCache: persistentCache)

        _ = try await firstCache.features(for: url)
        _ = try await secondCache.features(for: url)

        let count = await extractor.count(for: url)
        XCTAssertEqual(count, 1)
    }
}

private actor CountingFrameFeatureExtractor: FrameFeatureExtracting {
    enum Failure: Error {
        case extractionFailed
    }

    private var counts: [URL: Int] = [:]
    private let delayNanoseconds: UInt64
    private let alwaysFails: Bool

    init(delayNanoseconds: UInt64 = 0, alwaysFails: Bool = false) {
        self.delayNanoseconds = delayNanoseconds
        self.alwaysFails = alwaysFails
    }

    func features(for url: URL) async throws -> FrameFeatures {
        counts[url, default: 0] += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if alwaysFails {
            throw Failure.extractionFailed
        }
        return FrameFeatures(observations: [])
    }

    func similarity(between first: FrameFeatures, and second: FrameFeatures) async throws -> Double? {
        nil
    }

    func count(for url: URL) -> Int {
        counts[url, default: 0]
    }
}
