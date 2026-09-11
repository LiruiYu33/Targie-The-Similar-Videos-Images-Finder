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
        let first = Self.video(name: "holiday.mov")
        let second = Self.video(name: "holiday copy.mov")
        let result = SimilarityScorer.score(
            first,
            second,
            hashesMatch: false,
            frameSimilarity: nil
        )
        XCTAssertLessThanOrEqual(result.score, 0.05)
        let relation = SimilarityRelation(
            firstID: first.id,
            secondID: second.id,
            score: result.score,
            evidence: result.evidence
        )
        let groups = SimilarityGrouper.groups(items: [first, second], relations: [relation], threshold: 0.88)
        XCTAssertTrue(groups.isEmpty, "Matching names and metadata must not create a recommended group without content evidence")
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
        // Hash + metadata only is capped at 0.95.
        XCTAssertGreaterThan(result.score, 0.78)
        XCTAssertLessThanOrEqual(result.score, 0.95)
    }

    func testWeakPerceptualHashKeepsScoreLow() {
        let result = SimilarityScorer.score(
            Self.video(name: "a.mov"),
            Self.video(name: "b.mov", size: 5_000_000, duration: 30),  // Different metadata.
            hashesMatch: false,
            perceptualSimilarity: 0.4,
            frameSimilarity: nil
        )
        XCTAssertLessThan(result.score, 0.7)
        XCTAssertFalse(result.evidence.contains(.similarPerceptualHash))
    }

    func testThreeLayerScoreCombinesWeights() {
        // All three layers are strong, so the score should be close to 1.0.
        let result = SimilarityScorer.score(
            Self.video(name: "trip.mov"),
            Self.video(name: "trip copy.mov"),
            hashesMatch: false,
            perceptualSimilarity: 0.95,
            frameSimilarity: 0.92
        )
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

    func testStrongPerceptualHashAndMatchingMetadataCannotOverrideWeakVision() {
        let first = Self.video(name: "trip.mov")
        let second = Self.video(name: "trip copy.mov")
        for vision in [0.3, 0.5, 0.8] {
            let result = SimilarityScorer.score(
                first,
                second,
                hashesMatch: false,
                perceptualSimilarity: 1,
                frameSimilarity: vision
            )
            XCTAssertLessThan(result.score, 0.88, "Weak Vision evidence must keep the pair below the default recommendation threshold")
            XCTAssertLessThanOrEqual(result.score, vision + 0.05 + 1e-12)
        }
    }

    func testRenamingResizingAndRecompressingDoNotHideStrongVisualMatches() {
        let image = Self.image(name: "mountain-original.png", size: 6_000_000, width: 3840, height: 2160)
        let resizedImage = Self.image(name: "received-image.jpg", size: 80_000, width: 640, height: 360)
        let video = Self.video(name: "mountain-original.mov", size: 60_000_000, duration: 60, width: 3840, height: 2160)
        let recompressedVideo = Self.video(name: "received-clip.mp4", size: 800_000, duration: 59.9, width: 640, height: 360)

        for (first, second) in [(image, resizedImage), (video, recompressedVideo)] {
            let result = SimilarityScorer.score(
                first,
                second,
                hashesMatch: false,
                perceptualSimilarity: 0.96,
                frameSimilarity: 0.99
            )
            XCTAssertGreaterThan(result.score, 0.88, "Changes in filename, dimensions and encoded size must not erase strong content evidence")
            XCTAssertTrue(result.evidence.contains(.similarFrames))
            XCTAssertFalse(result.evidence.contains(.identicalContentHash))
        }
    }

    func testStrongVisionCanRecommendPairWithoutPerceptualHashOrMatchingMetadata() {
        let result = SimilarityScorer.score(
            Self.image(name: "mountain-original.png", size: 6_000_000, width: 3840, height: 2160),
            Self.image(name: "received-image.jpg", size: 80_000, width: 640, height: 360),
            hashesMatch: false,
            perceptualSimilarity: nil,
            frameSimilarity: 0.98
        )
        XCTAssertGreaterThan(result.score, 0.88)
        XCTAssertTrue(result.evidence.contains(.similarFrames))
    }

    func testUnavailableRequiredVisionDoesNotReceiveTheFastModeScore() {
        let first = Self.video(name: "trip.mov")
        let second = Self.video(name: "trip copy.mov")
        let missingVerification = SimilarityScorer.score(
            first,
            second,
            hashesMatch: false,
            perceptualSimilarity: 1,
            frameSimilarity: nil,
            requiresVisualVerification: true
        )
        let intentionalFastMode = SimilarityScorer.score(
            first,
            second,
            hashesMatch: false,
            perceptualSimilarity: 1,
            frameSimilarity: nil,
            requiresVisualVerification: false
        )
        XCTAssertLessThanOrEqual(missingVerification.score, 0.85)
        XCTAssertLessThan(missingVerification.score, 0.88)
        XCTAssertTrue(missingVerification.evidence.contains(.similarPerceptualHash))
        XCTAssertFalse(missingVerification.evidence.contains(.similarFrames))
        XCTAssertGreaterThan(intentionalFastMode.score, 0.88)
        XCTAssertGreaterThan(intentionalFastMode.score, missingVerification.score)
    }

    func testAvailableRequiredVisionReceivesTheFullContentScore() {
        let first = Self.image(name: "mountain-original.png", size: 6_000_000, width: 3840, height: 2160)
        let second = Self.image(name: "received-image.jpg", size: 80_000, width: 640, height: 360)
        let verified = SimilarityScorer.score(
            first,
            second,
            hashesMatch: false,
            perceptualSimilarity: 0.96,
            frameSimilarity: 0.99,
            requiresVisualVerification: true
        )
        let optionalVerification = SimilarityScorer.score(
            first,
            second,
            hashesMatch: false,
            perceptualSimilarity: 0.96,
            frameSimilarity: 0.99,
            requiresVisualVerification: false
        )
        XCTAssertGreaterThan(verified.score, 0.88)
        XCTAssertEqual(verified.score, optionalVerification.score)
    }

    func testMetadataCanRaiseAnyEvidenceCombinationByAtMostFivePercentagePoints() {
        let first = Self.video(name: "trip.mov")
        let matchingMetadata = Self.video(name: "trip copy.mov")
        let missingMetadata = Self.video(name: "forest.mov", size: 0, duration: 0, width: 0, height: 0)
        let combinations: [(perceptual: Double?, vision: Double?)] = [
            (0.8, 0.75),
            (nil, 0.95),
            (0.8, nil),
            (nil, nil)
        ]
        for combination in combinations {
            let supported = SimilarityScorer.score(
                first,
                matchingMetadata,
                hashesMatch: false,
                perceptualSimilarity: combination.perceptual,
                frameSimilarity: combination.vision
            )
            let unsupported = SimilarityScorer.score(
                first,
                missingMetadata,
                hashesMatch: false,
                perceptualSimilarity: combination.perceptual,
                frameSimilarity: combination.vision
            )
            XCTAssertGreaterThanOrEqual(supported.score, unsupported.score)
            XCTAssertLessThanOrEqual(supported.score - unsupported.score, 0.05 + 1e-12)
        }
    }

    func testExactSHAStillOverridesContradictoryVisualAndMetadataEvidence() {
        let result = SimilarityScorer.score(
            Self.image(name: "mountain-original.png", size: 6_000_000, width: 3840, height: 2160),
            Self.image(name: "received-image.jpg", size: 80_000, width: 640, height: 360),
            hashesMatch: true,
            perceptualSimilarity: 0,
            frameSimilarity: 0
        )
        XCTAssertEqual(result.score, 1)
        XCTAssertEqual(result.evidence, [.identicalContentHash])
    }

    static func video(name: String, size: Int64 = 1_000_000, duration: Double = 60, width: Int = 1920, height: Int = 1080) -> MediaItem {
        MediaItem(
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            fileSize: size,
            duration: duration,
            width: width,
            height: height,
            modifiedAt: nil,
            thumbnailData: nil
        )
    }

    private static func image(name: String, size: Int64, width: Int, height: Int) -> MediaItem {
        MediaItem(
            kind: .image,
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            fileSize: size,
            duration: nil,
            width: width,
            height: height,
            modifiedAt: nil,
            thumbnailData: nil
        )
    }
}
