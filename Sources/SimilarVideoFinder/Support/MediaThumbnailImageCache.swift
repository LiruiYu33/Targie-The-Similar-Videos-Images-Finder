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
    }

    private let cache = NSCache<NSString, NSImage>()
    private let dataLoader: MediaThumbnailDataLoader
    private var inFlightLoads: [NSString: InFlightLoad] = [:]

    init(dataLoader: MediaThumbnailDataLoader? = nil) {
        self.dataLoader = dataLoader ?? MediaThumbnailImageCache.loadThumbnailData
        cache.countLimit = 2_000
        cache.totalCostLimit = 128 * 1024 * 1024
    }

    func image(for item: MediaItem) -> NSImage? {
        let key = cacheKey(for: item)
        if let image = cache.object(forKey: key) {
            return image
        }
        guard let data = item.thumbnailData, let image = NSImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: key, cost: data.count)
        return image
    }

    func image(for item: MediaItem, repairingMissingVideoThumbnail: Bool) async -> NSImage? {
        if let image = image(for: item) {
            return image
        }

        let key = cacheKey(for: item)
        if let existing = inFlightLoads[key] {
            return await cacheImage(from: existing.task, loadID: existing.id, forKey: key)
        }

        let loadID = UUID()
        let dataLoader = self.dataLoader
        let task = Task<ThumbnailImageBox?, Never> {
            guard let data = await dataLoader(item, repairingMissingVideoThumbnail) else {
                return nil
            }
            return await MediaThumbnailImageCache.decodeImage(data)
        }
        inFlightLoads[key] = InFlightLoad(id: loadID, task: task)
        let image = await cacheImage(from: task, loadID: loadID, forKey: key)
        if inFlightLoads[key]?.id == loadID {
            inFlightLoads.removeValue(forKey: key)
        }
        return image
    }

    func removeAll() {
        for load in inFlightLoads.values {
            load.task.cancel()
        }
        inFlightLoads.removeAll()
        cache.removeAllObjects()
    }

    private func cacheImage(
        from task: Task<ThumbnailImageBox?, Never>,
        loadID: UUID,
        forKey key: NSString
    ) async -> NSImage? {
        guard let box = await task.value else { return nil }
        guard inFlightLoads[key]?.id == loadID else {
            return cache.object(forKey: key)
        }
        cache.setObject(box.image, forKey: key, cost: box.cost)
        return box.image
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
        await Task.detached(priority: .utility) {
            guard
                let source = CGImageSourceCreateWithData(data as CFData, [
                    kCGImageSourceShouldCache: false
                ] as CFDictionary),
                let image = CGImageSourceCreateImageAtIndex(source, 0, [
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary)
            else { return nil }
            let nsImage = NSImage(
                cgImage: image,
                size: NSSize(width: image.width, height: image.height)
            )
            return ThumbnailImageBox(image: nsImage, cost: data.count)
        }.value
    }

    private func cacheKey(for item: MediaItem) -> NSString {
        if let thumbnailURL = item.thumbnailURL {
            return thumbnailURL.path as NSString
        }
        return item.id.uuidString as NSString
    }
}
