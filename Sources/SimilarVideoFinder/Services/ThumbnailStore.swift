// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import CryptoKit
import AppKit
import AVFoundation
import Foundation
import ImageIO

struct ThumbnailStore: Sendable {
    static let shared = ThumbnailStore(directoryURL: CachePaths.thumbnailDirectoryURL())

    let directoryURL: URL
    private let fileIndex: ThumbnailFileIndex

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.fileIndex = ThumbnailFileIndex(directoryURL: directoryURL)
    }

    func persist(_ data: Data, sourceURL: URL, modifiedAt: Date?) throws -> URL {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let pathKey = pathKey(for: sourceURL)
        let destination = destinationURL(pathKey: pathKey, modifiedAt: modifiedAt)
        try fileIndex.withFiles { filesByPathKey in
            for url in filesByPathKey[pathKey, default: []] where url != destination {
                try? FileManager.default.removeItem(at: url)
                ThumbnailDataCache.shared.remove(url)
            }
            filesByPathKey[pathKey] = []
            if !FileManager.default.fileExists(atPath: destination.path) {
                try data.write(to: destination, options: .atomic)
            }
            filesByPathKey[pathKey] = [destination]
        }
        ThumbnailDataCache.shared.insert(data, for: destination)
        return destination
    }

    /// Returns the persisted thumbnail URL for `sourceURL` if one already exists
    /// on disk, without generating anything. Lets scanners skip the expensive
    /// thumbnail generation (video frame decode / image downscale) on re-scan.
    func existingThumbnailURL(for sourceURL: URL, modifiedAt: Date?) -> URL? {
        let pathKey = pathKey(for: sourceURL)
        let expected = destinationURL(pathKey: pathKey, modifiedAt: modifiedAt)
        return fileIndex.withFiles { filesByPathKey in
            guard FileManager.default.fileExists(atPath: expected.path) else {
                filesByPathKey[pathKey]?.remove(expected)
                return nil
            }
            filesByPathKey[pathKey, default: []].insert(expected)
            return expected
        }
    }

    /// Migrates a thumbnail from a known old path to the new source URL.
    /// Called when `HashCache.detectMove` confirms the file was relocated.
    /// Returns the new thumbnail URL on success, nil if the old thumbnail
    /// doesn't exist or copy fails.
    func migrateFromOldPath(_ oldPath: String, to newURL: URL, modifiedAt: Date?) -> URL? {
        let oldPathKey = pathKey(for: URL(fileURLWithPath: oldPath))
        let oldURL = directoryURL.appendingPathComponent("\(oldPathKey)_\(modifiedKey(for: modifiedAt)).jpg")
        let newPathKey = pathKey(for: newURL)
        let destination = destinationURL(pathKey: newPathKey, modifiedAt: modifiedAt)

        return fileIndex.withFiles { filesByPathKey in
            guard FileManager.default.fileExists(atPath: oldURL.path) else { return nil }
            if FileManager.default.fileExists(atPath: destination.path) {
                filesByPathKey[newPathKey, default: []].insert(destination)
                return destination
            }

            do {
                try FileManager.default.copyItem(at: oldURL, to: destination)
                try? FileManager.default.removeItem(at: oldURL)
                filesByPathKey[oldPathKey]?.remove(oldURL)
                if filesByPathKey[oldPathKey]?.isEmpty == true {
                    filesByPathKey.removeValue(forKey: oldPathKey)
                }
                filesByPathKey[newPathKey, default: []].insert(destination)
                ThumbnailDataCache.shared.remove(oldURL)
                if let data = try? Data(contentsOf: destination) {
                    ThumbnailDataCache.shared.insert(data, for: destination)
                }
                return destination
            } catch {
                return nil
            }
        }
    }

    /// Explicit maintenance operation for a caller that owns a complete source
    /// universe. Normal folder scans retain thumbnails from earlier folders.
    func pruneStale(validSourceURLs: Set<URL>) throws {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        let validPathKeys = Set(validSourceURLs.map { pathKey(for: $0) })
        fileIndex.withFiles { filesByPathKey in
            let stalePathKeys = filesByPathKey.keys.filter { !validPathKeys.contains($0) }
            for pathKey in stalePathKeys {
                for url in filesByPathKey[pathKey, default: []] {
                    try? FileManager.default.removeItem(at: url)
                    ThumbnailDataCache.shared.remove(url)
                }
                filesByPathKey.removeValue(forKey: pathKey)
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
    func totalSize() async -> Int64 {
        let directoryURL = directoryURL
        return await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: directoryURL.path),
                  let contents = try? FileManager.default.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: [.fileSizeKey]
                  )
            else { return 0 }
            return contents.filter { $0.pathExtension == "jpg" }.reduce(0) { total, url in
                total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }.value
    }

    /// Number of cached thumbnails currently on disk.
    func count() -> Int {
        fileIndex.count
    }

    /// Removes every cached thumbnail from disk and the in-memory cache.
    func clearAll() async throws {
        let directoryURL = directoryURL
        let fileIndex = fileIndex
        try await Task.detached(priority: .utility) {
            ThumbnailDataCache.shared.removeAll()
            try fileIndex.withFiles { filesByPathKey in
                guard FileManager.default.fileExists(atPath: directoryURL.path) else {
                    filesByPathKey.removeAll()
                    return
                }
                let contents = try FileManager.default.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: nil
                )
                for url in contents where url.pathExtension == "jpg" {
                    try? FileManager.default.removeItem(at: url)
                }
                filesByPathKey.removeAll()
            }
        }.value
    }

    var directoryIndexLoadCountForTesting: Int {
        fileIndex.directoryLoadCount
    }

    static func cachedData(at url: URL) -> Data? {
        ThumbnailDataCache.shared.cachedData(at: url)
    }

    static func loadPersistedData(at url: URL) async -> Data? {
        await ThumbnailDataCache.shared.loadData(at: url)
    }

    func imageThumbnailData(for sourceURL: URL, modifiedAt: Date?) async -> Data? {
        guard !Task.isCancelled else { return nil }
        if let existingURL = existingThumbnailURL(for: sourceURL, modifiedAt: modifiedAt),
           let data = await Self.loadPersistedData(at: existingURL),
           await Self.isDecodableImageData(data) {
            guard !Task.isCancelled else { return nil }
            return data
        }
        guard let data = await Self.makeImageThumbnailDataOffMain(for: sourceURL) else { return nil }
        guard !Task.isCancelled else { return nil }
        _ = try? persist(data, sourceURL: sourceURL, modifiedAt: modifiedAt)
        return data
    }

    static func imageThumbnailData(sourceURL: URL, modifiedAt: Date?, thumbnailURL: URL?) async -> Data? {
        guard !Task.isCancelled else { return nil }
        guard let thumbnailURL else {
            return await shared.imageThumbnailData(for: sourceURL, modifiedAt: modifiedAt)
        }
        if let data = await loadPersistedData(at: thumbnailURL),
           await isDecodableImageData(data) {
            guard !Task.isCancelled else { return nil }
            return data
        }
        guard let data = await makeImageThumbnailDataOffMain(for: sourceURL) else { return nil }
        guard !Task.isCancelled else { return nil }
        do {
            try FileManager.default.createDirectory(
                at: thumbnailURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: thumbnailURL, options: .atomic)
            ThumbnailDataCache.shared.insert(data, for: thumbnailURL)
            shared.fileIndex.recordIfRecognized(thumbnailURL)
        } catch {
            return data
        }
        return data
    }

    func videoThumbnailData(for sourceURL: URL, duration: Double?, modifiedAt: Date?) async -> Data? {
        guard !Task.isCancelled else { return nil }
        if let existingURL = existingThumbnailURL(for: sourceURL, modifiedAt: modifiedAt),
           let data = await Self.loadPersistedData(at: existingURL),
           await Self.isDecodableImageData(data) {
            guard !Task.isCancelled else { return nil }
            return data
        }
        guard let data = await Self.makeVideoThumbnailData(sourceURL: sourceURL, duration: duration) else {
            return nil
        }
        guard !Task.isCancelled else { return nil }
        _ = try? persist(data, sourceURL: sourceURL, modifiedAt: modifiedAt)
        return data
    }

    private static func makeImageThumbnailDataOffMain(for sourceURL: URL) async -> Data? {
        await Task.detached(priority: .utility) {
            makeImageThumbnailData(for: sourceURL)
        }.value
    }

    private static func isDecodableImageData(_ data: Data) async -> Bool {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData, [
                kCGImageSourceShouldCache: false
            ] as CFDictionary) else { return false }
            return CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCache: false
            ] as CFDictionary) != nil
        }.value
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

    static func makeVideoThumbnailData(sourceURL: URL, duration: Double?) async -> Data? {
        guard !Task.isCancelled else { return nil }
        let asset = AVURLAsset(url: sourceURL)
        let resolvedDuration: Double
        if let duration, duration.isFinite, duration > 0 {
            resolvedDuration = duration
        } else {
            do {
                resolvedDuration = try await asset.load(.duration).seconds
            } catch {
                if Task.isCancelled { return nil }
                resolvedDuration = 0
            }
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 405)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        for time in videoThumbnailCandidateTimes(duration: resolvedDuration) {
            guard !Task.isCancelled else { return nil }
            let cgImage: CGImage
            do {
                cgImage = try await CancellableAssetImageGenerator.image(at: time, using: generator)
            } catch is CancellationError {
                return nil
            } catch {
                continue
            }
            let representation = NSBitmapImageRep(cgImage: cgImage)
            if let data = representation.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.78]
            ) {
                return data
            }
        }
        return nil
    }

    private static func videoThumbnailCandidateTimes(duration: Double) -> [CMTime] {
        let safeDuration = duration.isFinite && duration > 0 ? duration : 0
        let fractions = safeDuration > 0 ? [0.35, 0.10, 0.50, 0.75, 0.02, 0.0] : [0.0]
        var seen = Set<Int64>()
        return fractions.compactMap { fraction in
            let time = CMTime(seconds: max(0, safeDuration * fraction), preferredTimescale: 600)
            guard seen.insert(time.value).inserted else { return nil }
            return time
        }
    }

}

private final class ThumbnailFileIndex: @unchecked Sendable {
    private let directoryURL: URL
    private let lock = NSLock()
    private var filesByPathKey: [String: Set<URL>] = [:]
    private var hasLoadedDirectory = false
    private var loadCount = 0

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func withFiles<T>(
        _ operation: (inout [String: Set<URL>]) throws -> T
    ) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        loadDirectoryIfNeeded()
        return try operation(&filesByPathKey)
    }

    func record(_ url: URL, pathKey: String) {
        _ = withFiles { filesByPathKey in
            filesByPathKey[pathKey, default: []].insert(url)
        }
    }

    func recordIfRecognized(_ url: URL) {
        guard url.deletingLastPathComponent().standardizedFileURL == directoryURL.standardizedFileURL,
              let pathKey = Self.pathKey(from: url)
        else { return }
        record(url, pathKey: pathKey)
    }

    var count: Int {
        withFiles { filesByPathKey in
            filesByPathKey.values.reduce(0) { $0 + $1.count }
        }
    }

    var directoryLoadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return loadCount
    }

    private func loadDirectoryIfNeeded() {
        guard !hasLoadedDirectory else { return }
        hasLoadedDirectory = true
        loadCount += 1
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in contents {
            guard let pathKey = Self.pathKey(from: url) else { continue }
            filesByPathKey[pathKey, default: []].insert(url)
        }
    }

    private static func pathKey(from url: URL) -> String? {
        guard url.pathExtension.lowercased() == "jpg",
              let pathKey = url.lastPathComponent.split(separator: "_", maxSplits: 1).first,
              !pathKey.isEmpty
        else { return nil }
        return String(pathKey)
    }
}

private final class ThumbnailDataCache: @unchecked Sendable {
    static let shared = ThumbnailDataCache()

    private let cache = NSCache<NSURL, NSData>()
    private let stateLock = NSLock()
    private var generation = 0

    private init() {
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func insert(_ data: Data, for url: URL) {
        stateLock.lock()
        defer { stateLock.unlock() }
        cache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
    }

    func remove(_ url: URL) {
        stateLock.lock()
        defer { stateLock.unlock() }
        cache.removeObject(forKey: url as NSURL)
    }

    func removeAll() {
        stateLock.lock()
        defer { stateLock.unlock() }
        generation &+= 1
        cache.removeAllObjects()
    }

    func cachedData(at url: URL) -> Data? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let cached = cache.object(forKey: url as NSURL) else { return nil }
        return cached as Data
    }

    func loadData(at url: URL) async -> Data? {
        let loadGeneration = generationSnapshot()
        if let cached = cachedData(at: url) {
            let fileExists = await Task.detached(priority: .utility) {
                FileManager.default.fileExists(atPath: url.path)
            }.value
            guard !Task.isCancelled, isCurrent(loadGeneration) else { return nil }
            if fileExists { return cached }
            remove(url)
            return nil
        }
        let data = await Task.detached(priority: .utility) {
            try? Data(contentsOf: url, options: [.mappedIfSafe])
        }.value
        guard
            !Task.isCancelled,
            let data,
            insert(data, for: url, ifCurrent: loadGeneration)
        else { return nil }
        return data
    }

    private func generationSnapshot() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return generation
    }

    private func isCurrent(_ expectedGeneration: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return generation == expectedGeneration
    }

    private func insert(_ data: Data, for url: URL, ifCurrent expectedGeneration: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard generation == expectedGeneration else { return false }
        cache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        return true
    }
}
