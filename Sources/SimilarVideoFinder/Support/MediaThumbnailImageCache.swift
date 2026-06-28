// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import AppKit

@MainActor
final class MediaThumbnailImageCache {
    static let shared = MediaThumbnailImageCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
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

    func removeAll() {
        cache.removeAllObjects()
    }

    private func cacheKey(for item: MediaItem) -> NSString {
        if let thumbnailURL = item.thumbnailURL {
            return thumbnailURL.path as NSString
        }
        return item.id.uuidString as NSString
    }
}
