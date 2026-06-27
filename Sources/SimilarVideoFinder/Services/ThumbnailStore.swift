// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import CryptoKit
import AppKit
import Foundation
import ImageIO

struct ThumbnailStore: Sendable {
    static let shared = ThumbnailStore(directoryURL: defaultDirectoryURL())

    let directoryURL: URL

    func persist(_ data: Data, sourceURL: URL, modifiedAt: Date?) throws -> URL {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let pathKey = pathKey(for: sourceURL)
        let destination = destinationURL(pathKey: pathKey, modifiedAt: modifiedAt)
        // Remove every thumbnail for this source file that differs from the
        // current modification time — those are stale because the file changed.
        if let existing = try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) {
            for url in existing where url.lastPathComponent.hasPrefix("\(pathKey)_") && url != destination {
                try? FileManager.default.removeItem(at: url)
                ThumbnailDataCache.shared.remove(url)
            }
        }
        if !FileManager.default.fileExists(atPath: destination.path) {
            try data.write(to: destination, options: .atomic)
        }
        ThumbnailDataCache.shared.insert(data, for: destination)
        return destination
    }

    /// Returns the persisted thumbnail URL for `sourceURL` if one already exists
    /// on disk, without generating anything. Lets scanners skip the expensive
    /// thumbnail generation (video frame decode / image downscale) on re-scan.
    func existingThumbnailURL(for sourceURL: URL, modifiedAt: Date?) -> URL? {
        let expected = destinationURL(pathKey: pathKey(for: sourceURL), modifiedAt: modifiedAt)
        return FileManager.default.fileExists(atPath: expected.path) ? expected : nil
    }

    /// Migrates a thumbnail from a known old path to the new source URL.
    /// Called when `HashCache.detectMove` confirms the file was relocated.
    /// Returns the new thumbnail URL on success, nil if the old thumbnail
    /// doesn't exist or copy fails.
    func migrateFromOldPath(_ oldPath: String, to newURL: URL, modifiedAt: Date?) -> URL? {
        let oldPathKey = pathKey(for: URL(fileURLWithPath: oldPath))
        let oldURL = directoryURL.appendingPathComponent("\(oldPathKey)_\(modifiedKey(for: modifiedAt)).jpg")
        guard FileManager.default.fileExists(atPath: oldURL.path) else { return nil }

        let destination = destinationURL(pathKey: pathKey(for: newURL), modifiedAt: modifiedAt)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return destination }

        do {
            try FileManager.default.copyItem(at: oldURL, to: destination)
            try? FileManager.default.removeItem(at: oldURL)
            ThumbnailDataCache.shared.remove(oldURL)
            if let data = try? Data(contentsOf: destination) {
                ThumbnailDataCache.shared.insert(data, for: destination)
            }
            return destination
        } catch {
            return nil
        }
    }

    /// Removes cached thumbnails whose source path is no longer part of the
    /// current library scan.
    func pruneStale(validSourceURLs: Set<URL>) throws {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        let validPathKeys = Set(validSourceURLs.map { pathKey(for: $0) })
        let contents = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        for url in contents where url.pathExtension == "jpg" {
            guard let pathKey = url.lastPathComponent.split(separator: "_", maxSplits: 1).first else { continue }
            if !validPathKeys.contains(String(pathKey)) {
                try? FileManager.default.removeItem(at: url)
                ThumbnailDataCache.shared.remove(url)
            }
        }
    }

    /// Stable hash of the canonical source path — used as a prefix so we can
    /// find (and clean up) all thumbnails belonging to the same file.
    private func pathKey(for sourceURL: URL) -> String {
        SHA256.hash(data: Data(sourceURL.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Filename: `{pathKey}_{modifiedKey}.jpg`.  The modifiedKey changes when
    /// the file's content-modification date changes, so a new thumbnail gets
    /// a different name and `persist` cleans up the previous one.
    private func destinationURL(pathKey: String, modifiedAt: Date?) -> URL {
        directoryURL.appendingPathComponent("\(pathKey)_\(modifiedKey(for: modifiedAt)).jpg")
    }

    private func modifiedKey(for modifiedAt: Date?) -> String {
        SHA256.hash(data: Data("\(modifiedAt?.timeIntervalSince1970 ?? 0)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Total size of cached thumbnail files, in bytes.
    func totalSize() -> Int64 {
        guard FileManager.default.fileExists(atPath: directoryURL.path),
              let contents = try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        return contents.filter { $0.pathExtension == "jpg" }.reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// Number of cached thumbnails currently on disk.
    func count() -> Int {
        guard FileManager.default.fileExists(atPath: directoryURL.path),
              let contents = try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        else { return 0 }
        return contents.filter { $0.pathExtension == "jpg" }.count
    }

    /// Removes every cached thumbnail from disk and the in-memory cache.
    func clearAll() throws {
        ThumbnailDataCache.shared.removeAll()
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        let contents = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        for url in contents where url.pathExtension == "jpg" {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func data(at url: URL) -> Data? {
        ThumbnailDataCache.shared.data(at: url)
    }

    static func persistedData(at url: URL) -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            ThumbnailDataCache.shared.remove(url)
            return nil
        }
        return data(at: url)
    }

    func imageThumbnailData(for sourceURL: URL, modifiedAt: Date?) -> Data? {
        if let existingURL = existingThumbnailURL(for: sourceURL, modifiedAt: modifiedAt),
           let data = Self.data(at: existingURL) {
            return data
        }
        guard let data = Self.makeImageThumbnailData(for: sourceURL) else { return nil }
        return (try? persist(data, sourceURL: sourceURL, modifiedAt: modifiedAt)).flatMap(Self.data(at:)) ?? data
    }

    static func imageThumbnailData(sourceURL: URL, modifiedAt: Date?, thumbnailURL: URL?) -> Data? {
        guard let thumbnailURL else {
            return shared.imageThumbnailData(for: sourceURL, modifiedAt: modifiedAt)
        }
        if let data = persistedData(at: thumbnailURL) { return data }
        guard let data = makeImageThumbnailData(for: sourceURL) else { return nil }
        do {
            try FileManager.default.createDirectory(
                at: thumbnailURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: thumbnailURL, options: .atomic)
            ThumbnailDataCache.shared.insert(data, for: thumbnailURL)
        } catch {
            return data
        }
        return data
    }

    private static func makeImageThumbnailData(for sourceURL: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 720,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSBitmapImageRep(cgImage: thumbnail).representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.78]
        )
    }

    private static func defaultDirectoryURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Targie", isDirectory: true)
            .appendingPathComponent("thumbnails", isDirectory: true)
    }
}

private final class ThumbnailDataCache: @unchecked Sendable {
    static let shared = ThumbnailDataCache()

    private let cache = NSCache<NSURL, NSData>()

    private init() {
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func insert(_ data: Data, for url: URL) {
        cache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
    }

    func remove(_ url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    func data(at url: URL) -> Data? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached as Data
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        insert(data, for: url)
        return data
    }
}
