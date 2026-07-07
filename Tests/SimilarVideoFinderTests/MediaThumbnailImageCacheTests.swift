// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import AppKit
import XCTest
@testable import SimilarVideoFinder

@MainActor
final class MediaThumbnailImageCacheTests: XCTestCase {
    func testRepeatedThumbnailDecodeReusesImageObjectForSameMediaItem() throws {
        MediaThumbnailImageCache.shared.removeAll()
        defer { MediaThumbnailImageCache.shared.removeAll() }

        let data = try makeJPEGData()
        let item = MediaItem(
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/cache-test.mov"),
            fileSize: 100,
            duration: 1,
            width: 64,
            height: 64,
            modifiedAt: nil,
            thumbnailData: data
        )

        let first = try XCTUnwrap(MediaThumbnailImageCache.shared.image(for: item))
        let second = try XCTUnwrap(MediaThumbnailImageCache.shared.image(for: item))

        XCTAssertTrue(first === second)
    }

    func testMissingVideoThumbnailCanBeGeneratedFromSourceFile() async throws {
        let ffmpeg = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        guard FileManager.default.isExecutableFile(atPath: ffmpeg.path) else {
            throw XCTSkip("ffmpeg is unavailable")
        }
        MediaThumbnailImageCache.shared.removeAll()
        defer { MediaThumbnailImageCache.shared.removeAll() }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoThumbnailRepair-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let videoURL = root.appendingPathComponent("missing-thumbnail.mp4")
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=size=240x320:rate=12",
            "-t", "1", "-pix_fmt", "yuv420p", "-y", videoURL.path
        ]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let values = try videoURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let item = MediaItem(
            kind: .video,
            url: videoURL,
            fileSize: Int64(values.fileSize ?? 0),
            duration: 1,
            width: 240,
            height: 320,
            modifiedAt: values.contentModificationDate,
            thumbnailData: nil
        )

        let image = await MediaThumbnailImageCache.shared.image(for: item, repairingMissingVideoThumbnail: true)

        XCTAssertNotNil(image)
    }

    private func makeJPEGData() throws -> Data {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 8, height: 8)).fill()
        image.unlockFocus()

        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(rep.representation(using: .jpeg, properties: [:]))
    }
}
