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

import AVFoundation
import Foundation
@preconcurrency import Vision

enum FrameSimilarityAggregator {
    static func aggregate(_ values: [Double?]) -> Double? {
        let valid = values.compactMap { $0 }
        guard valid.count >= 2 else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }
}

struct FrameFeatureExtractor {
    static let samplePositions = [0.08, 0.28, 0.50, 0.72, 0.92]

    func similarity(between firstURL: URL, and secondURL: URL) async throws -> Double? {
        let first = try await features(for: firstURL)
        let second = try await features(for: secondURL)
        return try await similarity(between: first, and: second)
    }
}

struct FrameFeatures: @unchecked Sendable {
    let observations: [VNFeaturePrintObservation?]
}

enum FrameFeatureSerializer {
    private struct Payload: Codable {
        let observations: [Data?]
    }

    static func serialize(_ features: FrameFeatures) throws -> Data {
        let observations = try features.observations.map { observation -> Data? in
            guard let observation else { return nil }
            return try ImageFeatureSerializer.serialize(observation)
        }
        return try JSONEncoder().encode(Payload(observations: observations))
    }

    static func deserialize(_ data: Data) throws -> FrameFeatures {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let observations = try payload.observations.map { data -> VNFeaturePrintObservation? in
            guard let data else { return nil }
            return try ImageFeatureSerializer.deserialize(data)
        }
        return FrameFeatures(observations: observations)
    }
}

protocol FrameFeatureExtracting: Sendable {
    func features(for url: URL) async throws -> FrameFeatures
    func similarity(between first: FrameFeatures, and second: FrameFeatures) async throws -> Double?
}

extension FrameFeatureExtractor: FrameFeatureExtracting {
    func features(for url: URL) async throws -> FrameFeatures {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { return FrameFeatures(observations: []) }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.35, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.35, preferredTimescale: 600)

        var observations: [VNFeaturePrintObservation?] = []
        observations.reserveCapacity(Self.samplePositions.count)
        for position in Self.samplePositions {
            try Task.checkCancellation()
            let time = CMTime(seconds: duration * position, preferredTimescale: 600)
            let image: CGImage
            do {
                image = try await CancellableAssetImageGenerator.image(at: time, using: generator)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                observations.append(nil)
                continue
            }
            let request = VNGenerateImageFeaturePrintRequest()
            try await CancellableVisionRequest.perform(
                request,
                handler: VNImageRequestHandler(cgImage: image)
            )
            observations.append(request.results?.first as? VNFeaturePrintObservation)
        }
        return FrameFeatures(observations: observations)
    }

    func similarity(between first: FrameFeatures, and second: FrameFeatures) async throws -> Double? {
        let count = min(first.observations.count, second.observations.count)
        var similarities: [Double?] = []
        for index in 0..<count {
            try Task.checkCancellation()
            guard let lhs = first.observations[index], let rhs = second.observations[index] else {
                similarities.append(nil)
                continue
            }
            var distance: Float = 0
            try lhs.computeDistance(&distance, to: rhs)
            similarities.append(max(0, min(1, 1 - Double(distance) / 40)))
        }
        return FrameSimilarityAggregator.aggregate(similarities)
    }
}

actor FrameFeatureCache {
    private struct CachedTask {
        let id: UUID
        let task: Task<FrameFeatures, Error>
        var waiterIDs: Set<UUID>
    }

    private struct TaskLease: Sendable {
        let taskID: UUID
        let waiterID: UUID
        let task: Task<FrameFeatures, Error>
    }

    private let extractor: any FrameFeatureExtracting
    private var storage: [URL: CachedTask] = [:]
    private let persistentCache: (any HashCaching)?

    init(
        extractor: any FrameFeatureExtracting = FrameFeatureExtractor(),
        persistentCache: (any HashCaching)? = nil
    ) {
        self.extractor = extractor
        self.persistentCache = persistentCache
    }

    func features(for url: URL) async throws -> FrameFeatures {
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
        let task = Task.detached(priority: .utility) {
            try await Self.loadFeatures(
                for: url,
                extractor: extractor,
                persistentCache: persistentCache
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

    private static func loadFeatures(
        for url: URL,
        extractor: any FrameFeatureExtracting,
        persistentCache: (any HashCaching)?
    ) async throws -> FrameFeatures {
        try Task.checkCancellation()
        if let persistentCache,
           let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
           let data = await persistentCache.lookupFrameFeature(
               filePath: url.path,
               fileSize: Int64(values.fileSize ?? 0),
               modifiedAt: values.contentModificationDate
           ),
           let cached = try? FrameFeatureSerializer.deserialize(data) {
            try Task.checkCancellation()
            return cached
        }

        let value = try await extractor.features(for: url)
        try Task.checkCancellation()
        if let persistentCache,
           let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
           let data = try? FrameFeatureSerializer.serialize(value) {
            await persistentCache.upsertFrameFeature(
                filePath: url.path,
                fileSize: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate,
                featureData: data
            )
        }
        try Task.checkCancellation()
        return value
    }

    func similarity(between firstURL: URL, and secondURL: URL) async throws -> Double? {
        let first = try await features(for: firstURL)
        let second = try await features(for: secondURL)
        return try await extractor.similarity(between: first, and: second)
    }
}
