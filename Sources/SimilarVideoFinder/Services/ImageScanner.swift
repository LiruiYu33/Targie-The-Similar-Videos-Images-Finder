// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import AppKit
import Foundation
import ImageIO

struct ImageScanResult: Sendable {
    let images: [MediaItem]
    let issues: [ScanIssue]
}

struct ImageScanner: Sendable {
    typealias ImageLoader = @Sendable (URL) async throws -> MediaItem
    private typealias ImageProgressLoader = @Sendable (URL) async throws -> LoadedImageMedia

    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "tif", "tiff", "gif", "bmp"
    ]

    let maxConcurrentLoads: Int
    let loader: ImageLoader
    let metadataCache: (any HashCaching)?
    let usesDefaultLoader: Bool
    private let thumbnailStore: ThumbnailStore
    private let progressLoader: ImageProgressLoader

    init(
        maxConcurrentLoads: Int = min(4, max(2, ProcessInfo.processInfo.activeProcessorCount / 2)),
        thumbnailStore: ThumbnailStore = .shared,
        metadataCache: (any HashCaching)? = nil,
        loader: ImageLoader? = nil
    ) {
        self.maxConcurrentLoads = max(1, maxConcurrentLoads)
        self.metadataCache = metadataCache
        self.usesDefaultLoader = loader == nil
        self.thumbnailStore = thumbnailStore
        if let loader {
            self.loader = loader
            self.progressLoader = { url in
                LoadedImageMedia(image: try await loader(url), metadataCacheHit: false)
            }
        } else {
            self.progressLoader = { url in
                try await Self.loadImage(at: url, thumbnailStore: thumbnailStore, metadataCache: metadataCache)
            }
            self.loader = { url in
                try await Self.loadImage(at: url, thumbnailStore: thumbnailStore, metadataCache: metadataCache).image
            }
        }
    }

    static func discoverImageURLs(in folder: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        return enumerator.compactMap { element -> URL? in
            guard let url = element as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  supportedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            return url
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func scan(
        folder: URL,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> ImageScanResult {
        let urls = try Self.discoverImageURLs(in: folder)
        let reportsMetadataCache = metadataCache != nil && usesDefaultLoader
        let metadataKeysByPath = reportsMetadataCache ? Self.metadataKeysByPath(urls: urls, mediaKind: .image) : [:]
        let prefetchedMetadata = reportsMetadataCache
            ? await metadataCache?.lookupMetadata(keys: Array(metadataKeysByPath.values)) ?? [:]
            : [:]
        await progress(ScanProgress(
            stage: .readingMetadata,
            fraction: 0,
            discoveredCount: urls.count,
            cacheTotal: reportsMetadataCache ? urls.count : 0,
            cacheKind: reportsMetadataCache ? .metadata : nil
        ))

        let loader = self.progressLoader
        let limit = maxConcurrentLoads
        let results = try await withThrowingTaskGroup(of: LoadedImage.self) { group in
            var iterator = Array(urls.enumerated()).makeIterator()
            var collected: [LoadedImage] = []
            var completed = 0
            var metadataCacheHits = 0

            for _ in 0..<min(limit, urls.count) {
                guard let next = iterator.next() else { break }
                group.addTask {
                    try await Self.load(
                        index: next.offset,
                        url: next.element,
                        using: loader,
                        cachedMetadata: Self.cachedMetadata(
                            for: next.element,
                            keysByPath: metadataKeysByPath,
                            prefetchedMetadata: prefetchedMetadata
                        ),
                        thumbnailStore: thumbnailStore
                    )
                }
            }

            while let result = try await group.next() {
                try Task.checkCancellation()
                collected.append(result)
                completed += 1
                if result.metadataCacheHit { metadataCacheHits += 1 }
                await progress(ScanProgress(
                    stage: .readingMetadata,
                    fraction: urls.isEmpty ? 1 : Double(completed) / Double(urls.count),
                    currentFile: result.url.lastPathComponent,
                    discoveredCount: urls.count,
                    cacheHits: metadataCacheHits,
                    cacheTotal: reportsMetadataCache ? urls.count : 0,
                    cacheKind: reportsMetadataCache ? .metadata : nil
                ))
                if let next = iterator.next() {
                    group.addTask {
                        try await Self.load(
                            index: next.offset,
                            url: next.element,
                            using: loader,
                            cachedMetadata: Self.cachedMetadata(
                                for: next.element,
                                keysByPath: metadataKeysByPath,
                                prefetchedMetadata: prefetchedMetadata
                            ),
                            thumbnailStore: thumbnailStore
                        )
                    }
                }
            }
            return collected.sorted { $0.index < $1.index }
        }

        return ImageScanResult(
            images: results.compactMap(\.image),
            issues: results.compactMap(\.issue)
        )
    }

    private static func load(index: Int, url: URL, using loader: ImageProgressLoader) async throws -> LoadedImage {
        try await load(index: index, url: url, using: loader, cachedMetadata: nil, thumbnailStore: nil)
    }

    private static func load(
        index: Int,
        url: URL,
        using loader: ImageProgressLoader,
        cachedMetadata: (key: MediaMetadataCacheKey, entry: MediaMetadataCacheEntry)?,
        thumbnailStore: ThumbnailStore?
    ) async throws -> LoadedImage {
        do {
            if let cachedMetadata,
               let thumbnailStore,
               let width = cachedMetadata.entry.width,
               let height = cachedMetadata.entry.height,
               let existingURL = thumbnailStore.existingThumbnailURL(for: url, modifiedAt: cachedMetadata.key.modifiedAt) {
                let image = MediaItem(
                    kind: .image,
                    url: url,
                    fileSize: cachedMetadata.key.fileSize,
                    duration: nil,
                    width: width,
                    height: height,
                    modifiedAt: cachedMetadata.key.modifiedAt,
                    thumbnailData: nil,
                    thumbnailURL: existingURL
                )
                return LoadedImage(index: index, url: url, image: image, metadataCacheHit: true, issue: nil)
            }
            let loaded = try await loader(url)
            return LoadedImage(index: index, url: url, image: loaded.image, metadataCacheHit: loaded.metadataCacheHit, issue: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return LoadedImage(
                index: index,
                url: url,
                image: nil,
                metadataCacheHit: false,
                issue: ScanIssue(url: url, reason: .unreadableImage)
            )
        }
    }

    private static func metadataKeysByPath(urls: [URL], mediaKind: MediaKind) -> [String: MediaMetadataCacheKey] {
        urls.reduce(into: [:]) { result, url in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
            result[url.path] = MediaMetadataCacheKey(
                filePath: url.path,
                fileSize: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate,
                mediaKind: mediaKind
            )
        }
    }

    private static func cachedMetadata(
        for url: URL,
        keysByPath: [String: MediaMetadataCacheKey],
        prefetchedMetadata: [MediaMetadataCacheKey: MediaMetadataCacheEntry]
    ) -> (key: MediaMetadataCacheKey, entry: MediaMetadataCacheEntry)? {
        guard let key = keysByPath[url.path], let entry = prefetchedMetadata[key] else { return nil }
        return (key, entry)
    }

    private static func loadImage(at url: URL, thumbnailStore: ThumbnailStore, metadataCache: (any HashCaching)?) async throws -> LoadedImageMedia {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize = Int64(values.fileSize ?? 0)
        let modifiedAt = values.contentModificationDate
        let cachedMetadata = await metadataCache?.lookupMetadata(
            filePath: url.path,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            mediaKind: .image
        )
        let metadataCacheHit = cachedMetadata?.width != nil && cachedMetadata?.height != nil

        if metadataCacheHit,
           let width = cachedMetadata?.width,
           let height = cachedMetadata?.height,
           let existingURL = thumbnailStore.existingThumbnailURL(for: url, modifiedAt: modifiedAt) {
            return LoadedImageMedia(
                image: MediaItem(
                    kind: .image,
                    url: url,
                    fileSize: fileSize,
                    duration: nil,
                    width: width,
                    height: height,
                    modifiedAt: modifiedAt,
                    thumbnailData: nil,
                    thumbnailURL: existingURL
                ),
                metadataCacheHit: true
            )
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            throw ImageScannerError.unreadableImage
        }

        let width: Int
        let height: Int
        if metadataCacheHit, let cachedWidth = cachedMetadata?.width, let cachedHeight = cachedMetadata?.height {
            width = cachedWidth
            height = cachedHeight
        } else {
            guard
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                let rawWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                let rawHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber
            else {
                throw ImageScannerError.unreadableImage
            }
            let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            let swapsDimensions = [5, 6, 7, 8].contains(orientation)
            width = swapsDimensions ? rawHeight.intValue : rawWidth.intValue
            height = swapsDimensions ? rawWidth.intValue : rawHeight.intValue
        }

        // Store minimal metadata so `detectMove` can locate the old path when
        // this image is later moved to a different folder.
        if let cache = metadataCache, !metadataCacheHit {
            await cache.upsertMetadata(
                filePath: url.path,
                fileSize: fileSize,
                modifiedAt: modifiedAt,
                mediaKind: .image,
                duration: nil,
                width: width,
                height: height
            )
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 720,
            kCGImageSourceShouldCacheImmediately: true
        ]
        // Reuse a persisted thumbnail if one exists for this (path, modifiedAt)
        // — avoids re-decoding and re-downscaling the image on re-scan.
        if let existingURL = thumbnailStore.existingThumbnailURL(for: url, modifiedAt: modifiedAt) {
            return LoadedImageMedia(
                image: MediaItem(
                    kind: .image,
                    url: url,
                    fileSize: fileSize,
                    duration: nil,
                    width: width,
                    height: height,
                    modifiedAt: modifiedAt,
                    thumbnailData: nil,
                    thumbnailURL: existingURL
                ),
                metadataCacheHit: metadataCacheHit
            )
        }
        // Move detection: the file may have been relocated from another folder.
        // Ask HashCache for the old path and migrate the thumbnail precisely
        // (avoids the race condition of a fuzzy modifiedAt scan).
        let migratedURL: URL?
        if let cache = metadataCache,
           let oldPath = await cache.detectMove(
               filePath: url.path,
               fileSize: fileSize,
               modifiedAt: modifiedAt,
               mediaKind: .image,
               algorithmVersion: ImageSimilarityPipeline.algorithmVersion
           ) {
            migratedURL = thumbnailStore.migrateFromOldPath(oldPath, to: url, modifiedAt: modifiedAt)
        } else {
            migratedURL = nil
        }
        if let migratedURL {
            return LoadedImageMedia(
                image: MediaItem(
                    kind: .image,
                    url: url,
                    fileSize: fileSize,
                    duration: nil,
                    width: width,
                    height: height,
                    modifiedAt: modifiedAt,
                    thumbnailData: nil,
                    thumbnailURL: migratedURL
                ),
                metadataCacheHit: metadataCacheHit
            )
        }
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw ImageScannerError.unreadableImage
        }
        let representation = NSBitmapImageRep(cgImage: thumbnail)
        let thumbnailData = representation.representation(using: .jpeg, properties: [.compressionFactor: 0.78])
        let thumbnailURL = thumbnailData.flatMap {
            try? thumbnailStore.persist($0, sourceURL: url, modifiedAt: modifiedAt)
        }

        return LoadedImageMedia(
            image: MediaItem(
                kind: .image,
                url: url,
                fileSize: fileSize,
                duration: nil,
                width: width,
                height: height,
                modifiedAt: modifiedAt,
                thumbnailData: thumbnailURL == nil ? thumbnailData : nil,
                thumbnailURL: thumbnailURL
            ),
            metadataCacheHit: metadataCacheHit
        )
    }
}

private struct LoadedImage: Sendable {
    let index: Int
    let url: URL
    let image: MediaItem?
    let metadataCacheHit: Bool
    let issue: ScanIssue?
}

private struct LoadedImageMedia: Sendable {
    let image: MediaItem
    let metadataCacheHit: Bool
}

private enum ImageScannerError: Error {
    case unreadableImage
}
