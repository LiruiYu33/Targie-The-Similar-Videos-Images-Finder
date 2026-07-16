// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import AppKit
import Foundation
import ImageIO

typealias MediaThumbnailDataLoader = @Sendable (MediaItem, Bool) async -> Data?

private final class ThumbnailImageBox: @unchecked Sendable {
    let image: NSImage
    let cost: Int

    init(image: NSImage, cost: Int) {
        self.image = image
        self.cost = cost
    }
}

@MainActor
final class MediaThumbnailImageCache {
    static let shared = MediaThumbnailImageCache()

    private struct InFlightLoad {
        let id: UUID
        let task: Task<ThumbnailImageBox?, Never>
        var waiterIDs: Set<UUID>
    }

    private struct LoadLease: Sendable {
        let loadID: UUID
        let waiterID: UUID
        let task: Task<ThumbnailImageBox?, Never>
    }

    private let cache = NSCache<NSString, NSImage>()
    private let dataLoader: MediaThumbnailDataLoader
    private var inFlightLoads: [String: InFlightLoad] = [:]

    init(dataLoader: MediaThumbnailDataLoader? = nil) {
        self.dataLoader = dataLoader ?? MediaThumbnailImageCache.loadThumbnailData
        cache.countLimit = 2_000
        cache.totalCostLimit = 128 * 1024 * 1024
    }

    func image(for item: MediaItem) -> NSImage? {
        let key = cacheKey(for: item)
        if let image = cache.object(forKey: key as NSString) {
            return image
        }
        guard let data = item.thumbnailData, let image = NSImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: key as NSString, cost: data.count)
        return image
    }

    func image(for item: MediaItem, repairingMissingVideoThumbnail: Bool) async -> NSImage? {
        if let image = image(for: item) {
            return image
        }

        let key = cacheKey(for: item)
        let lease = acquireLoad(
            for: item,
            repairingMissingVideoThumbnail: repairingMissingVideoThumbnail,
            key: key
        )
        let box = await withTaskCancellationHandler {
            await lease.task.value
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelWaiter(lease, forKey: key)
            }
        }
        guard !Task.isCancelled else {
            finishWaiter(lease, forKey: key)
            return nil
        }
        if let box {
            cache.setObject(box.image, forKey: key as NSString, cost: box.cost)
        }
        finishWaiter(lease, forKey: key)
        return box?.image
    }

    func removeAll() {
        for load in inFlightLoads.values {
            load.task.cancel()
        }
        inFlightLoads.removeAll()
        cache.removeAllObjects()
    }

    private func acquireLoad(
        for item: MediaItem,
        repairingMissingVideoThumbnail: Bool,
        key: String
    ) -> LoadLease {
        let waiterID = UUID()
        if var existing = inFlightLoads[key] {
            existing.waiterIDs.insert(waiterID)
            inFlightLoads[key] = existing
            return LoadLease(loadID: existing.id, waiterID: waiterID, task: existing.task)
        }

        let loadID = UUID()
        let dataLoader = self.dataLoader
        let task = Task<ThumbnailImageBox?, Never> {
            guard !Task.isCancelled,
                  let data = await dataLoader(item, repairingMissingVideoThumbnail),
                  !Task.isCancelled
            else { return nil }
            return await MediaThumbnailImageCache.decodeImage(data)
        }
        inFlightLoads[key] = InFlightLoad(id: loadID, task: task, waiterIDs: [waiterID])
        return LoadLease(loadID: loadID, waiterID: waiterID, task: task)
    }

    private func finishWaiter(_ lease: LoadLease, forKey key: String) {
        guard var existing = inFlightLoads[key], existing.id == lease.loadID else { return }
        existing.waiterIDs.remove(lease.waiterID)
        inFlightLoads.removeValue(forKey: key)
    }

    private func cancelWaiter(_ lease: LoadLease, forKey key: String) {
        guard var existing = inFlightLoads[key], existing.id == lease.loadID else { return }
        existing.waiterIDs.remove(lease.waiterID)
        if existing.waiterIDs.isEmpty {
            existing.task.cancel()
            inFlightLoads.removeValue(forKey: key)
        } else {
            inFlightLoads[key] = existing
        }
    }

    private nonisolated static func loadThumbnailData(
        for item: MediaItem,
        repairingMissingVideoThumbnail: Bool
    ) async -> Data? {
        if !item.isThumbnailDiskBacked, let data = item.thumbnailData {
            return data
        }
        switch item.kind {
        case .image:
            return await ThumbnailStore.imageThumbnailData(
                sourceURL: item.url,
                modifiedAt: item.modifiedAt,
                thumbnailURL: item.thumbnailURL
            )
        case .video:
            if repairingMissingVideoThumbnail {
                return await ThumbnailStore.shared.videoThumbnailData(
                    for: item.url,
                    duration: item.duration,
                    modifiedAt: item.modifiedAt
                )
            }
            guard let thumbnailURL = item.thumbnailURL else { return nil }
            return await ThumbnailStore.loadPersistedData(at: thumbnailURL)
        }
    }

    private nonisolated static func decodeImage(_ data: Data) async -> ThumbnailImageBox? {
        let worker = Task.detached(priority: .utility) { () -> ThumbnailImageBox? in
            guard !Task.isCancelled else { return nil }
            guard
                let source = CGImageSourceCreateWithData(data as CFData, [
                    kCGImageSourceShouldCache: false
                ] as CFDictionary),
                let image = CGImageSourceCreateImageAtIndex(source, 0, [
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary)
            else { return nil }
            guard !Task.isCancelled else { return nil }
            let nsImage = NSImage(
                cgImage: image,
                size: NSSize(width: image.width, height: image.height)
            )
            return ThumbnailImageBox(image: nsImage, cost: data.count)
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private func cacheKey(for item: MediaItem) -> String {
        if let thumbnailURL = item.thumbnailURL {
            return thumbnailURL.path
        }
        return item.id.uuidString
    }
}
