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
    static let algorithmVersion = "vision-image-feature-v3-revision2"
    static let maximumInputPixelSize = 1_536

    func feature(for url: URL) async throws -> ImageFeature {
        try Task.checkCancellation()
        guard let image = Self.inputImage(for: url) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try Task.checkCancellation()
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VisionFeatureSimilarity.requestRevision
        try await CancellableVisionRequest.perform(
            request,
            handler: VNImageRequestHandler(cgImage: image)
        )
        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw CocoaError(.featureUnsupported)
        }
        return ImageFeature(observation: observation)
    }

    static func inputImage(for url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumInputPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    func similarity(between first: ImageFeature, and second: ImageFeature) throws -> Double {
        try VisionFeatureSimilarity.similarity(between: first.observation, and: second.observation)
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

private actor ImageFeatureExtractionLimiter {
    private let limit: Int
    private var activeCount = 0
    private var waiterOrder: [UUID] = []
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() async throws {
        try Task.checkCancellation()
        if activeCount < limit {
            activeCount += 1
            return
        }

        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiterOrder.append(waiterID)
                waiters[waiterID] = continuation
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(waiterID)
            }
        }
    }

    func release() {
        while !waiterOrder.isEmpty {
            let waiterID = waiterOrder.removeFirst()
            guard let continuation = waiters.removeValue(forKey: waiterID) else { continue }
            continuation.resume()
            return
        }
        precondition(activeCount > 0)
        activeCount -= 1
    }

    private func cancelWaiter(_ waiterID: UUID) {
        guard let continuation = waiters.removeValue(forKey: waiterID) else { return }
        continuation.resume(throwing: CancellationError())
    }
}

actor ImageFeatureCache {
    private struct CachedTask {
        let id: UUID
        let task: Task<ImageFeature, Error>
        var waiterIDs: Set<UUID>
    }

    private struct TaskLease: Sendable {
        let taskID: UUID
        let waiterID: UUID
        let task: Task<ImageFeature, Error>
    }

    private let extractor: any ImageFeatureExtracting
    private var storage: [URL: CachedTask] = [:]
    private let persistentCache: (any HashCaching)?
    private let algorithmVersion: String
    private let extractionLimiter: ImageFeatureExtractionLimiter

    init(
        extractor: any ImageFeatureExtracting = ImageFeatureExtractor(),
        persistentCache: (any HashCaching)? = nil,
        algorithmVersion: String = ImageFeatureExtractor.algorithmVersion,
        maxConcurrentExtractions: Int = 2
    ) {
        self.extractor = extractor
        self.persistentCache = persistentCache
        self.algorithmVersion = algorithmVersion
        self.extractionLimiter = ImageFeatureExtractionLimiter(limit: maxConcurrentExtractions)
    }

    func feature(for url: URL) async throws -> ImageFeature {
        try Task.checkCancellation()
        let lease = acquireTask(for: url)
        return try await withTaskCancellationHandler {
            do {
                let value = try await lease.task.value
                try Task.checkCancellation()
                finishWaiter(lease, for: url, removeTask: false)
                return value
            } catch is CancellationError {
                finishWaiter(lease, for: url, removeTask: !Task.isCancelled)
                throw CancellationError()
            } catch {
                finishWaiter(lease, for: url, removeTask: true)
                throw error
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(lease, for: url)
            }
        }
    }

    func cancelAll() {
        for cached in storage.values {
            cached.task.cancel()
        }
        storage.removeAll()
    }

    private func acquireTask(for url: URL) -> TaskLease {
        let waiterID = UUID()
        if var cached = storage[url] {
            cached.waiterIDs.insert(waiterID)
            storage[url] = cached
            return TaskLease(taskID: cached.id, waiterID: waiterID, task: cached.task)
        }

        let extractor = self.extractor
        let persistentCache = self.persistentCache
        let algorithmVersion = self.algorithmVersion
        let extractionLimiter = self.extractionLimiter
        let task = Task.detached(priority: .utility) {
            try await Self.loadFeature(
                for: url,
                extractor: extractor,
                persistentCache: persistentCache,
                algorithmVersion: algorithmVersion,
                extractionLimiter: extractionLimiter
            )
        }
        let taskID = UUID()
        storage[url] = CachedTask(id: taskID, task: task, waiterIDs: [waiterID])
        return TaskLease(taskID: taskID, waiterID: waiterID, task: task)
    }

    private func finishWaiter(_ lease: TaskLease, for url: URL, removeTask: Bool) {
        guard var cached = storage[url], cached.id == lease.taskID else { return }
        cached.waiterIDs.remove(lease.waiterID)
        if removeTask {
            storage.removeValue(forKey: url)
        } else {
            storage[url] = cached
        }
    }

    private func cancelWaiter(_ lease: TaskLease, for url: URL) {
        guard var cached = storage[url], cached.id == lease.taskID else { return }
        cached.waiterIDs.remove(lease.waiterID)
        if cached.waiterIDs.isEmpty {
            cached.task.cancel()
            storage.removeValue(forKey: url)
        } else {
            storage[url] = cached
        }
    }

    private static func loadFeature(
        for url: URL,
        extractor: any ImageFeatureExtracting,
        persistentCache: (any HashCaching)?,
        algorithmVersion: String,
        extractionLimiter: ImageFeatureExtractionLimiter
    ) async throws -> ImageFeature {
        try Task.checkCancellation()
        // Check persistent SQLite cache — avoids Vision neural-network inference
        // on re-scan when the image file hasn't changed.
        if let pc = persistentCache,
           let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
           let data = await pc.lookupImageFeature(
               filePath: url.path,
               fileSize: Int64(values.fileSize ?? 0),
               modifiedAt: values.contentModificationDate,
               algorithmVersion: algorithmVersion
           ),
           let observation = try? ImageFeatureSerializer.deserialize(data) {
            try Task.checkCancellation()
            return ImageFeature(observation: observation)
        }

        try await extractionLimiter.acquire()
        let feature: ImageFeature
        do {
            feature = try await extractor.feature(for: url)
            await extractionLimiter.release()
        } catch {
            await extractionLimiter.release()
            throw error
        }
        try Task.checkCancellation()
        // Persist to SQLite for next launch.
        if let pc = persistentCache,
           let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
           let data = try? ImageFeatureSerializer.serialize(feature.observation) {
            await pc.upsertImageFeature(
                filePath: url.path,
                fileSize: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate,
                algorithmVersion: algorithmVersion,
                featureData: data
            )
        }
        try Task.checkCancellation()
        return feature
    }

    func similarity(between first: URL, and second: URL) async throws -> Double? {
        do {
            let firstFeature = try await feature(for: first)
            let secondFeature = try await feature(for: second)
            try Task.checkCancellation()
            let value = try extractor.similarity(between: firstFeature, and: secondFeature)
            try Task.checkCancellation()
            return value
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }
}
