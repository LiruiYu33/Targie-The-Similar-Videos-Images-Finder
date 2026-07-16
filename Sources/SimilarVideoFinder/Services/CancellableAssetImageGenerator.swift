// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import AVFoundation
import Foundation

private final class AssetImageGeneratorBox: @unchecked Sendable {
    let generator: AVAssetImageGenerator

    init(_ generator: AVAssetImageGenerator) {
        self.generator = generator
    }
}

enum CancellableAssetImageGenerator {
    static func image(
        at time: CMTime,
        using generator: AVAssetImageGenerator
    ) async throws -> CGImage {
        let box = AssetImageGeneratorBox(generator)
        return try await withTaskCancellationHandler {
            do {
                let image = try await box.generator.image(at: time).image
                try Task.checkCancellation()
                return image
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                throw error
            }
        } onCancel: {
            box.generator.cancelAllCGImageGeneration()
        }
    }
}
