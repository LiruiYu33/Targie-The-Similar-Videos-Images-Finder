// Targie - Find similar videos on macOS.
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

import XCTest
@testable import SimilarVideoFinder

@MainActor
final class DeepVerificationTests: XCTestCase {
    func testDefaultPipelineUsesPerceptualAlgorithmVersion() {
        let model = ScanViewModel()
        XCTAssertEqual(
            model.videoPairRelationAlgorithmVersion,
            "video-pair-relation-v2-perceptual"
        )
    }

    func testEnablingSwitchesToFrameAlgorithmVersion() {
        let model = ScanViewModel()
        model.setDeepVerification(true)
        XCTAssertEqual(
            model.videoPairRelationAlgorithmVersion,
            "video-pair-relation-v2-frame"
        )
    }

    func testDisablingRestoresPerceptualAlgorithmVersion() {
        let model = ScanViewModel()
        model.setDeepVerification(true)
        model.setDeepVerification(false)
        XCTAssertEqual(
            model.videoPairRelationAlgorithmVersion,
            "video-pair-relation-v2-perceptual"
        )
    }

    func testInjectedPipelineIsNotRebuiltOnToggle() {
        let stub = SimilarityPipelineStub()
        let model = ScanViewModel(pipeline: stub)

        model.setDeepVerification(true)
        // The flag still moves so the algorithm-version accessor reflects it,
        // but an externally injected pipeline instance is left in place.
        XCTAssertEqual(
            model.videoPairRelationAlgorithmVersion,
            "video-pair-relation-v2-frame"
        )
        XCTAssertEqual(stub.processCallCount, 0)
    }
}

/// Minimal SimilarityProcessing stub that records process() calls without
/// doing any real work. Used only to verify the injected-pipeline branch of
/// setDeepVerification does not rebuild the pipeline.
private final class SimilarityPipelineStub: SimilarityProcessing, @unchecked Sendable {
    private(set) var processCallCount = 0

    func process(
        videos: [MediaItem],
        threshold: Double,
        scanIntensity: ScanIntensity,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> PipelineResult {
        processCallCount += 1
        return PipelineResult(videos: videos, relations: [])
    }

    func process(
        videos: [MediaItem],
        threshold: Double,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> PipelineResult {
        try await process(videos: videos, threshold: threshold, scanIntensity: .balanced, progress: progress)
    }
}
