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

final class SimilarityScoringTests: XCTestCase {
    func testStripsCopyAndExportNoise() {
        XCTAssertEqual(FilenameNormalizer.normalize("旅行 copy 2_export.mp4"), "旅行")
    }

    func testExactHashProducesCertainMatch() {
        let result = SimilarityScorer.score(
            Self.video(name: "one.mov"),
            Self.video(name: "two.mov"),
            hashesMatch: true,
            frameSimilarity: nil
        )
        XCTAssertEqual(result.score, 1.0)
        XCTAssertTrue(result.evidence.contains(.identicalContentHash))
    }

    func testMetadataAloneCannotClaimHighVisualMatch() {
        let result = SimilarityScorer.score(
            Self.video(name: "holiday.mov"),
            Self.video(name: "holiday copy.mov"),
            hashesMatch: false,
            frameSimilarity: nil
        )
        XCTAssertLessThan(result.score, 0.82)
    }

    // MARK: - Perceptual Hash Layer

    func testPerceptualHashAddsEvidenceWhenStrong() {
        let result = SimilarityScorer.score(
            Self.video(name: "a.mov"),
            Self.video(name: "b.mov"),
            hashesMatch: false,
            perceptualSimilarity: 0.95,
            frameSimilarity: nil
        )
        XCTAssertTrue(result.evidence.contains(.similarPerceptualHash))
    }

    func testPerceptualHashWithoutFrameStillScoresHigh() {
        let result = SimilarityScorer.score(
            Self.video(name: "trip.mov"),
            Self.video(name: "trip copy.mov"),
            hashesMatch: false,
            perceptualSimilarity: 0.95,
            frameSimilarity: nil
        )
        // 仅哈希 + 元数据时上限 0.95
        XCTAssertGreaterThan(result.score, 0.78)
        XCTAssertLessThanOrEqual(result.score, 0.95)
    }

    func testWeakPerceptualHashKeepsScoreLow() {
        let result = SimilarityScorer.score(
            Self.video(name: "a.mov"),
            Self.video(name: "b.mov", size: 5_000_000, duration: 30),  // 不同元数据
            hashesMatch: false,
            perceptualSimilarity: 0.4,
            frameSimilarity: nil
        )
        XCTAssertLessThan(result.score, 0.7)
        XCTAssertFalse(result.evidence.contains(.similarPerceptualHash))
    }

    func testThreeLayerScoreCombinesWeights() {
        // 三层都强 → 应接近 1.0
        let result = SimilarityScorer.score(
            Self.video(name: "trip.mov"),
            Self.video(name: "trip copy.mov"),
            hashesMatch: false,
            perceptualSimilarity: 0.95,
            frameSimilarity: 0.92
        )
        // 0.45·0.95 + 0.35·0.92 + 0.20·meta(高) → ~0.92+
        XCTAssertGreaterThan(result.score, 0.88)
        XCTAssertTrue(result.evidence.contains(.similarPerceptualHash))
        XCTAssertTrue(result.evidence.contains(.similarFrames))
    }

    func testIdenticalContentHashStillBeatsAllOtherSignals() {
        let result = SimilarityScorer.score(
            Self.video(name: "x.mov"),
            Self.video(name: "y.mov"),
            hashesMatch: true,
            perceptualSimilarity: 0.4,
            frameSimilarity: 0.5
        )
        XCTAssertEqual(result.score, 1.0)
        XCTAssertEqual(result.evidence, [.identicalContentHash])
    }

    static func video(name: String, size: Int64 = 1_000_000, duration: Double = 60) -> VideoItem {
        VideoItem(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            fileSize: size,
            duration: duration,
            width: 1920,
            height: 1080,
            modifiedAt: nil,
            thumbnailData: nil
        )
    }
}
