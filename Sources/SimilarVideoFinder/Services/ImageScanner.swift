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

    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "webp", "tif", "tiff", "gif", "bmp"
    ]

    private let maxConcurrentLoads: Int
    private let loader: ImageLoader

    init(
        maxConcurrentLoads: Int = min(4, max(2, ProcessInfo.processInfo.activeProcessorCount / 2)),
        loader: ImageLoader? = nil
    ) {
        self.maxConcurrentLoads = max(1, maxConcurrentLoads)
        self.loader = loader ?? { url in try Self.loadImage(at: url) }
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
                  supportedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            return url
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func scan(
        folder: URL,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> ImageScanResult {
        let urls = try Self.discoverImageURLs(in: folder)
        await progress(ScanProgress(stage: .readingMetadata, fraction: 0, discoveredCount: urls.count))

        let loader = self.loader
        let limit = maxConcurrentLoads
        let results = try await withThrowingTaskGroup(of: LoadedImage.self) { group in
            var iterator = Array(urls.enumerated()).makeIterator()
            var collected: [LoadedImage] = []
            var completed = 0

            for _ in 0..<min(limit, urls.count) {
                guard let next = iterator.next() else { break }
                group.addTask { await Self.load(index: next.offset, url: next.element, using: loader) }
            }

            while let result = try await group.next() {
                collected.append(result)
                completed += 1
                await progress(ScanProgress(
                    stage: .readingMetadata,
                    fraction: urls.isEmpty ? 1 : Double(completed) / Double(urls.count),
                    currentFile: result.url.lastPathComponent,
                    discoveredCount: urls.count
                ))
                if let next = iterator.next() {
                    group.addTask { await Self.load(index: next.offset, url: next.element, using: loader) }
                }
            }
            return collected.sorted { $0.index < $1.index }
        }

        return ImageScanResult(
            images: results.compactMap(\.image),
            issues: results.compactMap(\.issue)
        )
    }

    private static func load(index: Int, url: URL, using loader: ImageLoader) async -> LoadedImage {
        do {
            return LoadedImage(index: index, url: url, image: try await loader(url), issue: nil)
        } catch {
            return LoadedImage(
                index: index,
                url: url,
                image: nil,
                issue: ScanIssue(url: url, reason: .unreadableImage)
            )
        }
    }

    private static func loadImage(at url: URL) throws -> MediaItem {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let rawWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
        let rawHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw ImageScannerError.unreadableImage
        }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapsDimensions = [5, 6, 7, 8].contains(orientation)
        let width = swapsDimensions ? rawHeight.intValue : rawWidth.intValue
        let height = swapsDimensions ? rawWidth.intValue : rawHeight.intValue

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 720,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw ImageScannerError.unreadableImage
        }
        let representation = NSBitmapImageRep(cgImage: thumbnail)
        let thumbnailData = representation.representation(using: .jpeg, properties: [.compressionFactor: 0.78])

        return MediaItem(
            kind: .image,
            url: url,
            fileSize: Int64(values.fileSize ?? 0),
            duration: nil,
            width: width,
            height: height,
            modifiedAt: values.contentModificationDate,
            thumbnailData: thumbnailData
        )
    }
}

private struct LoadedImage: Sendable {
    let index: Int
    let url: URL
    let image: MediaItem?
    let issue: ScanIssue?
}

private enum ImageScannerError: Error {
    case unreadableImage
}
