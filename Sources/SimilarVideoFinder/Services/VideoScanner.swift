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

import AppKit
import AVFoundation
import Foundation

struct VideoScanResult: Sendable {
    let videos: [MediaItem]
    let issues: [ScanIssue]
}

struct VideoScanner {
    typealias VideoLoader = @Sendable (URL) async throws -> MediaItem
    private typealias VideoProgressLoader = @Sendable (URL) async throws -> LoadedVideoMedia

    static let supportedExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm", "mpeg", "mpg", "3gp"
    ]

    let maxConcurrentLoads: Int
    let loader: VideoLoader
    let metadataCache: (any HashCaching)?
    let usesDefaultLoader: Bool
    private let thumbnailStore: ThumbnailStore
    private let progressLoader: VideoProgressLoader

    init(
        maxConcurrentLoads: Int = min(4, max(2, ProcessInfo.processInfo.activeProcessorCount / 2)),
        thumbnailStore: ThumbnailStore = .shared,
        metadataCache: (any HashCaching)? = nil,
        loader: VideoLoader? = nil
    ) {
        self.maxConcurrentLoads = max(1, maxConcurrentLoads)
        self.metadataCache = metadataCache
        self.usesDefaultLoader = loader == nil
        self.thumbnailStore = thumbnailStore
        if let loader {
            self.loader = loader
            self.progressLoader = { url in
                LoadedVideoMedia(video: try await loader(url), metadataCacheHit: false)
            }
        } else {
            self.progressLoader = { url in
                try await Self.loadVideo(at: url, thumbnailStore: thumbnailStore, metadataCache: metadataCache)
            }
            self.loader = { url in
                try await Self.loadVideo(at: url, thumbnailStore: thumbnailStore, metadataCache: metadataCache).video
            }
        }
    }

    static func discoverVideoURLs(in folder: URL) throws -> [URL] {
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
                  Self.supportedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            return url
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func scan(
        folder: URL,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> VideoScanResult {
        let urls = try Self.discoverVideoURLs(in: folder)
        let reportsMetadataCache = metadataCache != nil && usesDefaultLoader
        let metadataKeysByPath = reportsMetadataCache ? Self.metadataKeysByPath(urls: urls, mediaKind: .video) : [:]
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
        let results = try await withThrowingTaskGroup(of: LoadedVideo.self) { group in
            var iterator = Array(urls.enumerated()).makeIterator()
            var collected: [LoadedVideo] = []
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
                        thumbnailStore: thumbnailStore,
                        metadataCache: metadataCache
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
                            thumbnailStore: thumbnailStore,
                            metadataCache: metadataCache
                        )
                    }
                }
            }
            return collected.sorted { $0.index < $1.index }
        }

        return VideoScanResult(
            videos: results.compactMap(\.video),
            issues: results.compactMap(\.issue)
        )
    }

    private static func load(index: Int, url: URL, using loader: VideoProgressLoader) async throws -> LoadedVideo {
        try await load(index: index, url: url, using: loader, cachedMetadata: nil, thumbnailStore: nil, metadataCache: nil)
    }

    private static func load(
        index: Int,
        url: URL,
        using loader: VideoProgressLoader,
        cachedMetadata: (key: MediaMetadataCacheKey, entry: MediaMetadataCacheEntry)?,
        thumbnailStore: ThumbnailStore?,
        metadataCache: (any HashCaching)?
    ) async throws -> LoadedVideo {
        do {
            if let cachedMetadata,
               let thumbnailStore,
               let metadataCache,
               let duration = cachedMetadata.entry.duration,
               let width = cachedMetadata.entry.width,
               let height = cachedMetadata.entry.height {
                let video = try await finishLoadVideo(
                    url: url,
                    fileSize: cachedMetadata.key.fileSize,
                    modifiedAt: cachedMetadata.key.modifiedAt,
                    duration: duration,
                    width: width,
                    height: height,
                    thumbnailStore: thumbnailStore,
                    metadataCache: metadataCache
                )
                return LoadedVideo(index: index, url: url, video: video, metadataCacheHit: true, issue: nil)
            }
            let loaded = try await loader(url)
            return LoadedVideo(index: index, url: url, video: loaded.video, metadataCacheHit: loaded.metadataCacheHit, issue: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch ScannerError.noVideoTrack {
            return LoadedVideo(index: index, url: url, video: nil, metadataCacheHit: false, issue: ScanIssue(url: url, reason: .noVideoTrack))
        } catch {
            return LoadedVideo(index: index, url: url, video: nil, metadataCacheHit: false, issue: ScanIssue(url: url, reason: .message(error.localizedDescription)))
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

    private static func loadVideo(
        at url: URL,
        thumbnailStore: ThumbnailStore,
        metadataCache: (any HashCaching)?
    ) async throws -> LoadedVideoMedia {
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize = Int64(values.fileSize ?? 0)
        let modifiedAt = values.contentModificationDate

        // Metadata cache hit: skip all AVFoundation I/O.
        if let cache = metadataCache,
           let meta = await cache.lookupMetadata(
               filePath: url.path, fileSize: fileSize,
               modifiedAt: modifiedAt, mediaKind: .video
           ),
           let duration = meta.duration, let width = meta.width, let height = meta.height
        {
            let video = try await finishLoadVideo(
                url: url, fileSize: fileSize, modifiedAt: modifiedAt,
                duration: duration, width: width, height: height,
                thumbnailStore: thumbnailStore, metadataCache: cache
            )
            return LoadedVideoMedia(video: video, metadataCacheHit: true)
        }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        try Task.checkCancellation()
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw ScannerError.noVideoTrack }
        let naturalSize = try await track.load(.naturalSize)
        try Task.checkCancellation()
        let transform = try await track.load(.preferredTransform)
        let transformed = naturalSize.applying(transform)
        let width = Int(abs(transformed.width).rounded())
        let height = Int(abs(transformed.height).rounded())

        // Cache the metadata so the next re-scan skips AVFoundation entirely.
        if let cache = metadataCache {
            await cache.upsertMetadata(
                filePath: url.path, fileSize: fileSize, modifiedAt: modifiedAt,
                mediaKind: .video, duration: duration, width: width, height: height
            )
        }
        let video = try await finishLoadVideo(
            url: url, fileSize: fileSize, modifiedAt: modifiedAt,
            duration: duration, width: width, height: height,
            thumbnailStore: thumbnailStore, metadataCache: metadataCache
        )
        return LoadedVideoMedia(video: video, metadataCacheHit: false)
    }
    /// Common tail — thumbnail lookup + MediaItem assembly — shared by the
    /// cache-hit and cache-miss paths in `loadVideo`.
    private static func finishLoadVideo(
        url: URL, fileSize: Int64, modifiedAt: Date?,
        duration: Double, width: Int, height: Int,
        thumbnailStore: ThumbnailStore, metadataCache: (any HashCaching)?
    ) async throws -> MediaItem {
        // Reuse a persisted thumbnail if one exists for this (path, modifiedAt)
        // — avoids the expensive AVAssetImageGenerator frame decode on re-scan.
        let existingURL = thumbnailStore.existingThumbnailURL(for: url, modifiedAt: modifiedAt)
        let thumbnail: Data?
        let thumbnailURL: URL?
        if let existingURL {
            thumbnail = nil
            thumbnailURL = existingURL
        } else if let cache = metadataCache,
                  let oldPath = await cache.detectMove(
                      filePath: url.path,
                      fileSize: fileSize,
                      modifiedAt: modifiedAt,
                      mediaKind: .video,
                      algorithmVersion: "video-dct3d-v1"
                  ),
                  let migrated = thumbnailStore.migrateFromOldPath(oldPath, to: url, modifiedAt: modifiedAt) {
            thumbnail = nil
            thumbnailURL = migrated
        } else {
            let asset = AVURLAsset(url: url)
            thumbnail = await thumbnailData(asset: asset, duration: duration)
            thumbnailURL = thumbnail.flatMap {
                try? thumbnailStore.persist($0, sourceURL: url, modifiedAt: modifiedAt)
            }
        }
        return MediaItem(
            kind: .video,
            url: url,
            fileSize: fileSize,
            duration: duration,
            width: width,
            height: height,
            modifiedAt: modifiedAt,
            thumbnailData: thumbnailURL == nil ? thumbnail : nil,
            thumbnailURL: thumbnailURL
        )
    }

    private static func thumbnailData(asset: AVAsset, duration: Double) async -> Data? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 405)
        let time = CMTime(seconds: max(0, duration * 0.35), preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        return representation.representation(using: .jpeg, properties: [.compressionFactor: 0.78])
    }
}

private struct LoadedVideo: Sendable {
    let index: Int
    let url: URL
    let video: MediaItem?
    let metadataCacheHit: Bool
    let issue: ScanIssue?
}

private struct LoadedVideoMedia: Sendable {
    let video: MediaItem
    let metadataCacheHit: Bool
}

enum ScannerError: Error {
    case noVideoTrack
}
