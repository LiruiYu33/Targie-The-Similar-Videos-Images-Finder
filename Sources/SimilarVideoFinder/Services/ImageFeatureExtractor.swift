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

// MARK: - VNFeaturePrintObservation Serialization

enum ImageFeatureSerializer {
    /// Archives a `VNFeaturePrintObservation` to a blob for SQLite storage.
    static func serialize(_ observation: VNFeaturePrintObservation) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
    }

    /// Unarchives a `VNFeaturePrintObservation` from a previously stored blob.
    static func deserialize(_ data: Data) throws -> VNFeaturePrintObservation {
        guard let observation = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: VNFeaturePrintObservation.self, from: data
        ) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return observation
    }
}

actor ImageFeatureCache {
    private let extractor: any ImageFeatureExtracting
    private var storage: [URL: Task<ImageFeature, Error>] = [:]
    private let persistentCache: (any HashCaching)?

    init(
        extractor: any ImageFeatureExtracting = ImageFeatureExtractor(),
        persistentCache: (any HashCaching)? = nil
    ) {
        self.extractor = extractor
        self.persistentCache = persistentCache
    }

    func feature(for url: URL) async throws -> ImageFeature {
        if let cached = storage[url] { return try await cached.value }

        let extractor = self.extractor
        let persistentCache = self.persistentCache
        let task = Task<ImageFeature, Error>(priority: .utility) {
            try await Self.loadFeature(
                for: url,
                extractor: extractor,
                persistentCache: persistentCache
            )
        }
        storage[url] = task
        return try await task.value
    }

    private static func loadFeature(
        for url: URL,
        extractor: any ImageFeatureExtracting,
        persistentCache: (any HashCaching)?
    ) async throws -> ImageFeature {
        // Check persistent SQLite cache — avoids Vision neural-network inference
        // on re-scan when the image file hasn't changed.
        if let pc = persistentCache,
           let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
           let data = await pc.lookupImageFeature(
               filePath: url.path,
               fileSize: Int64(values.fileSize ?? 0),
               modifiedAt: values.contentModificationDate
           ),
           let observation = try? ImageFeatureSerializer.deserialize(data) {
            return ImageFeature(observation: observation)
        }

        let feature = try await extractor.feature(for: url)
        // Persist to SQLite for next launch.
        if let pc = persistentCache,
           let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
           let data = try? ImageFeatureSerializer.serialize(feature.observation) {
            await pc.upsertImageFeature(
                filePath: url.path,
                fileSize: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate,
                featureData: data
            )
        }
        return feature
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
