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

import XCTest
@testable import SimilarVideoFinder

final class VideoScannerTests: XCTestCase {
    func testDiscoversSupportedVideosRecursivelyInStableOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for path in ["b.mov", "nested/a.mp4", "nested/c.M4V", "notes.txt"] {
            let url = root.appendingPathComponent(path)
            try Data("fixture".utf8).write(to: url)
        }

        let found = try VideoScanner.discoverVideoURLs(in: root)
        XCTAssertEqual(found.map(\.lastPathComponent), ["b.mov", "a.mp4", "c.M4V"])
    }

    func testDiscoveryIgnoresDirectoriesWithVideoExtensions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("not-a-video.mp4"),
            withIntermediateDirectories: true
        )
        try Data().write(to: root.appendingPathComponent("real.mp4"))

        let found = try VideoScanner.discoverVideoURLs(in: root)

        XCTAssertEqual(found.map(\.lastPathComponent), ["real.mp4"])
    }

    func testScanLoadsMetadataConcurrentlyAndKeepsStableOrder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["c.mp4", "a.mp4", "b.mp4"] {
            try Data().write(to: root.appendingPathComponent(name))
        }

        let tracker = LoadConcurrencyTracker()
        let scanner = VideoScanner(maxConcurrentLoads: 3) { url in
            await tracker.started()
            try await Task.sleep(for: .milliseconds(40))
            await tracker.finished()
            return MediaItem(
            kind: .video,
                url: url,
                fileSize: 1,
                duration: 1,
                width: 1,
                height: 1,
                modifiedAt: nil,
                thumbnailData: nil
            )
        }

        let result = try await scanner.scan(folder: root) { _ in }

        XCTAssertEqual(result.videos.map(\.filename), ["a.mp4", "b.mp4", "c.mp4"])
        let maximum = await tracker.maximum
        XCTAssertGreaterThan(maximum, 1)
        XCTAssertLessThanOrEqual(maximum, 3)
    }

    func testScanProgressReportsMetadataCacheHits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let thumbnailRoot = root.appendingPathComponent("thumbs", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("cached.mp4"))
        let cache = VideoMetadataHitCache()
        let progress = VideoScannerProgressRecorder()
        let scanner = VideoScanner(
            maxConcurrentLoads: 1,
            thumbnailStore: ThumbnailStore(directoryURL: thumbnailRoot),
            metadataCache: cache
        )

        _ = try await scanner.scan(folder: root) {
            await progress.append($0)
        }

        let readingUpdates = await progress.updates(for: .readingMetadata)
        let finalReading = try XCTUnwrap(readingUpdates.last)
        XCTAssertEqual(finalReading.cacheKind, .metadata)
        XCTAssertEqual(finalReading.cacheHits, 1)
        XCTAssertEqual(finalReading.cacheTotal, 1)
        let moveAlgorithmVersions = await cache.moveAlgorithmVersions
        XCTAssertEqual(moveAlgorithmVersions, [PerceptualHasher.algorithmVersion])
    }

    func testLargeScanThrottlesMetadataProgressUpdates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<250 {
            try Data().write(to: root.appendingPathComponent("video-\(index).mp4"))
        }
        let progress = VideoScannerProgressRecorder()
        let scanner = VideoScanner(maxConcurrentLoads: 8) { url in
            MediaItem(
                kind: .video,
                url: url,
                fileSize: 1,
                duration: 1,
                width: 16,
                height: 9,
                modifiedAt: nil,
                thumbnailData: nil
            )
        }

        _ = try await scanner.scan(folder: root) {
            await progress.append($0)
        }

        let updates = await progress.updates(for: .readingMetadata)
        XCTAssertLessThanOrEqual(updates.count, 102)
        XCTAssertEqual(updates.last?.fraction, 1)
    }
}

private actor LoadConcurrencyTracker {
    private(set) var current = 0
    private(set) var maximum = 0

    func started() {
        current += 1
        maximum = max(maximum, current)
    }

    func finished() {
        current -= 1
    }
}

private actor VideoScannerProgressRecorder {
    private var updates: [ScanProgress] = []

    func append(_ update: ScanProgress) {
        updates.append(update)
    }

    func updates(for stage: ScanStage) -> [ScanProgress] {
        updates.filter { $0.stage == stage }
    }
}

private actor VideoMetadataHitCache: HashCaching {
    private(set) var moveAlgorithmVersions: [String] = []

    func lookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, algorithmVersion: String) -> CacheRecord? {
        nil
    }

    func upsert(_ record: CacheRecord) {}

    func pruneStale(validPaths: Set<String>) {}

    func count() -> Int { 0 }

    func clearAll() {}

    func sizeInBytes() -> Int64 { 0 }

    func lookupMetadata(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) -> (duration: Double?, width: Int?, height: Int?)? {
        mediaKind == .video ? (duration: 8, width: 1280, height: 720) : nil
    }

    func detectMove(
        filePath: String,
        fileSize: Int64,
        modifiedAt: Date?,
        mediaKind: MediaKind,
        algorithmVersion: String
    ) -> String? {
        moveAlgorithmVersions.append(algorithmVersion)
        return nil
    }
}
