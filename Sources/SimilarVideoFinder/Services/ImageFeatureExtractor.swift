// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import Foundation
import ImageIO
@preconcurrency import Vision

struct ImageFeature: @unchecked Sendable {
    let observation: VNFeaturePrintObservation
}

protocol ImageFeatureExtracting: Sendable {
    func feature(for url: URL) async throws -> ImageFeature
    func similarity(between first: ImageFeature, and second: ImageFeature) throws -> Double
}

struct ImageFeatureExtractor: ImageFeatureExtracting {
    func feature(for url: URL) async throws -> ImageFeature {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let request = VNGenerateImageFeaturePrintRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw CocoaError(.featureUnsupported)
        }
        return ImageFeature(observation: observation)
    }

    func similarity(between first: ImageFeature, and second: ImageFeature) throws -> Double {
        var distance: Float = 0
        try first.observation.computeDistance(&distance, to: second.observation)
        return max(0, min(1, 1 - Double(distance) / 40))
    }
}

actor ImageFeatureCache {
    private let extractor: any ImageFeatureExtracting
    private var storage: [URL: Result<ImageFeature, Error>] = [:]

    init(extractor: any ImageFeatureExtracting = ImageFeatureExtractor()) {
        self.extractor = extractor
    }

    func feature(for url: URL) async throws -> ImageFeature {
        if let cached = storage[url] { return try cached.get() }
        do {
            let feature = try await extractor.feature(for: url)
            storage[url] = .success(feature)
            return feature
        } catch {
            storage[url] = .failure(error)
            throw error
        }
    }

    func similarity(between first: URL, and second: URL) async -> Double? {
        do {
            let firstFeature = try await feature(for: first)
            let secondFeature = try await feature(for: second)
            return try extractor.similarity(between: firstFeature, and: secondFeature)
        } catch {
            return nil
        }
    }
}
