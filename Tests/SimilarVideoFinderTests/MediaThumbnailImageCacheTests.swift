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
