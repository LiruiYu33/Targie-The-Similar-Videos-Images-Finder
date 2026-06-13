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
    let videos: [VideoItem]
    let issues: [ScanIssue]
}

struct VideoScanner {
    typealias VideoLoader = @Sendable (URL) async throws -> VideoItem

    static let supportedExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm", "mpeg", "mpg", "3gp"
    ]

    private let maxConcurrentLoads: Int
    private let loader: VideoLoader

    init(
        maxConcurrentLoads: Int = min(4, max(2, ProcessInfo.processInfo.activeProcessorCount / 2)),
        loader: VideoLoader? = nil
    ) {
        self.maxConcurrentLoads = max(1, maxConcurrentLoads)
        self.loader = loader ?? { url in try await Self.loadVideo(at: url) }
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
                  Self.supportedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            return url
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func scan(
        folder: URL,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> VideoScanResult {
        let urls = try Self.discoverVideoURLs(in: folder)
        await progress(ScanProgress(stage: .readingMetadata, fraction: 0, discoveredCount: urls.count))
        let loader = self.loader
        let limit = maxConcurrentLoads
        let results = try await withThrowingTaskGroup(of: LoadedVideo.self) { group in
            var iterator = Array(urls.enumerated()).makeIterator()
            var collected: [LoadedVideo] = []
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

        return VideoScanResult(
            videos: results.compactMap(\.video),
            issues: results.compactMap(\.issue)
        )
    }

    private static func load(index: Int, url: URL, using loader: VideoLoader) async -> LoadedVideo {
        do {
            return LoadedVideo(index: index, url: url, video: try await loader(url), issue: nil)
        } catch ScannerError.noVideoTrack {
            return LoadedVideo(index: index, url: url, video: nil, issue: ScanIssue(url: url, reason: .noVideoTrack))
        } catch {
            return LoadedVideo(index: index, url: url, video: nil, issue: ScanIssue(url: url, reason: .message(error.localizedDescription)))
        }
    }

    private static func loadVideo(at url: URL) async throws -> VideoItem {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw ScannerError.noVideoTrack }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformed = naturalSize.applying(transform)
        let width = Int(abs(transformed.width).rounded())
        let height = Int(abs(transformed.height).rounded())
        let thumbnail = await thumbnailData(asset: asset, duration: duration)
        return VideoItem(
            url: url,
            fileSize: Int64(values.fileSize ?? 0),
            duration: duration,
            width: width,
            height: height,
            modifiedAt: values.contentModificationDate,
            thumbnailData: thumbnail
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
    let video: VideoItem?
    let issue: ScanIssue?
}

enum ScannerError: Error {
    case noVideoTrack
}
