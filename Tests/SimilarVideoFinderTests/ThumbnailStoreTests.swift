// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SimilarVideoFinder

final class ThumbnailStoreTests: XCTestCase {
    func testDiskBackedThumbnailLoadsAsynchronouslyThroughMediaItem() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThumbnailStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data([1, 2, 3, 4])
        let thumbnailURL = root.appendingPathComponent("thumbnail.jpg")
        try data.write(to: thumbnailURL)

        let item = MediaItem(
            kind: .image,
            url: URL(fileURLWithPath: "/media/example.jpg"),
            fileSize: 4,
            duration: nil,
            width: 1,
            height: 1,
            modifiedAt: Date(timeIntervalSince1970: 123),
            thumbnailData: nil,
            thumbnailURL: thumbnailURL
        )

        XCTAssertTrue(item.isThumbnailDiskBacked)
        XCTAssertNil(item.thumbnailData)
        let loadedData = await item.loadThumbnailData()
        XCTAssertEqual(loadedData, data)
        XCTAssertEqual(item.thumbnailData, data)

        try FileManager.default.removeItem(at: thumbnailURL)
        let missingData = await ThumbnailStore.loadPersistedData(at: thumbnailURL)
        XCTAssertNil(missingData)
    }

    func testImageThumbnailDataRebuildsMissingDiskBackedThumbnail() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThumbnailStoreRepairTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source.png")
        try writePNG(width: 40, height: 20, to: sourceURL)
        let date = Date(timeIntervalSince1970: 789)
        let thumbnailURL = root
            .appendingPathComponent("thumbnails", isDirectory: true)
            .appendingPathComponent("missing.jpg")

        let data = await ThumbnailStore.imageThumbnailData(
            sourceURL: sourceURL,
            modifiedAt: date,
            thumbnailURL: thumbnailURL
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnailURL.path))
        XCTAssertNotNil(NSImage(data: try XCTUnwrap(data)))
    }

    func testPruneStaleRemovesThumbnailsOutsideValidSourceSet() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThumbnailStorePruneTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ThumbnailStore(directoryURL: root)
        let date = Date(timeIntervalSince1970: 456)
        let keepSource = URL(fileURLWithPath: "/media/keep.jpg")
        let staleSource = URL(fileURLWithPath: "/media/stale.jpg")
        let keepThumbnail = try store.persist(Data([1]), sourceURL: keepSource, modifiedAt: date)
        let staleThumbnail = try store.persist(Data([2]), sourceURL: staleSource, modifiedAt: date)

        try store.pruneStale(validSourceURLs: [keepSource])

        XCTAssertTrue(FileManager.default.fileExists(atPath: keepThumbnail.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleThumbnail.path))
        XCTAssertEqual(store.count(), 1)
    }

    func testAsyncSizeAndClearAllCoverPersistedThumbnails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThumbnailStoreClearTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ThumbnailStore(directoryURL: root)
        let date = Date(timeIntervalSince1970: 654)
        _ = try store.persist(
            Data([1, 2, 3]),
            sourceURL: URL(fileURLWithPath: "/media/first.jpg"),
            modifiedAt: date
        )
        _ = try store.persist(
            Data([4, 5]),
            sourceURL: URL(fileURLWithPath: "/media/second.jpg"),
            modifiedAt: date
        )

        let size = await store.totalSize()
        XCTAssertEqual(size, 5)

        try await store.clearAll()
        XCTAssertEqual(store.count(), 0)
    }

    func testPersistLoadsDirectoryIndexOnlyOnceAndRemovesStaleVersion() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThumbnailStoreIndexTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ThumbnailStore(directoryURL: root)
        let firstSource = URL(fileURLWithPath: "/media/first.jpg")
        let secondSource = URL(fileURLWithPath: "/media/second.jpg")

        let staleThumbnail = try store.persist(
            Data([1]),
            sourceURL: firstSource,
            modifiedAt: Date(timeIntervalSince1970: 1)
        )
        let currentThumbnail = try store.persist(
            Data([2]),
            sourceURL: firstSource,
            modifiedAt: Date(timeIntervalSince1970: 2)
        )
        _ = try store.persist(
            Data([3]),
            sourceURL: secondSource,
            modifiedAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(store.directoryIndexLoadCountForTesting, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleThumbnail.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentThumbnail.path))
        XCTAssertEqual(store.count(), 2)
    }

    private func writePNG(width: Int, height: Int, to url: URL) throws {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
