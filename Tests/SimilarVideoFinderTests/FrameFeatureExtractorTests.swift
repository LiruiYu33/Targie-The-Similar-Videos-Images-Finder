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
}

private actor CountingFrameFeatureExtractor: FrameFeatureExtracting {
    private var counts: [URL: Int] = [:]

    func features(for url: URL) async throws -> FrameFeatures {
        counts[url, default: 0] += 1
        return FrameFeatures(observations: [])
    }

    func similarity(between first: FrameFeatures, and second: FrameFeatures) async throws -> Double? {
        nil
    }

    func count(for url: URL) -> Int {
        counts[url, default: 0]
    }
}
