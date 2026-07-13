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

    func testDiskBackedThumbnailLoadsOnlyThroughAsyncPath() async throws {
        let data = try makeJPEGData()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AsyncThumbnailLoad-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let thumbnailURL = root.appendingPathComponent("thumbnail.jpg")
        try data.write(to: thumbnailURL)
        let item = MediaItem(
            kind: .image,
            url: root.appendingPathComponent("source.png"),
            fileSize: 100,
            duration: nil,
            width: 64,
            height: 64,
            modifiedAt: nil,
            thumbnailData: nil,
            thumbnailURL: thumbnailURL
        )
        let cache = MediaThumbnailImageCache()

        XCTAssertNil(cache.image(for: item))
        let image = await cache.image(for: item, repairingMissingVideoThumbnail: true)

        XCTAssertNotNil(image)
        XCTAssertTrue(cache.image(for: item) === image)
    }

    func testConcurrentRequestsForSameKeyShareOneLoad() async throws {
        let probe = BlockingThumbnailDataLoader(data: try makeJPEGData())
        let cache = MediaThumbnailImageCache { item, _ in
            await probe.load(item)
        }
        let item = MediaItem(
            kind: .image,
            url: URL(fileURLWithPath: "/tmp/deduplicated-thumbnail.png"),
            fileSize: 100,
            duration: nil,
            width: 64,
            height: 64,
            modifiedAt: nil,
            thumbnailData: nil
        )

        let firstTask = Task<ObjectIdentifier?, Never> { @MainActor in
            guard let image = await cache.image(for: item, repairingMissingVideoThumbnail: true) else {
                return nil
            }
            return ObjectIdentifier(image)
        }
        let secondTask = Task<ObjectIdentifier?, Never> { @MainActor in
            guard let image = await cache.image(for: item, repairingMissingVideoThumbnail: true) else {
                return nil
            }
            return ObjectIdentifier(image)
        }
        try await waitUntilAsync { await probe.hasBlockedFirstLoad }

        let heartbeat = expectation(description: "main actor remains responsive")
        Task { @MainActor in heartbeat.fulfill() }
        await fulfillment(of: [heartbeat], timeout: 1)

        await probe.releaseFirstLoad()
        let firstImageID = await firstTask.value
        let secondImageID = await secondTask.value
        let loadCount = await probe.loadCount

        XCTAssertNotNil(firstImageID)
        XCTAssertEqual(firstImageID, secondImageID)
        XCTAssertEqual(loadCount, 1)
    }

    func testReusedLoaderDoesNotPublishPreviousItemsImage() async throws {
        let probe = BlockingThumbnailDataLoader(data: try makeJPEGData())
        let cache = MediaThumbnailImageCache { item, _ in
            await probe.load(item)
        }
        let loader = MediaThumbnailLoader(cache: cache)
        let first = MediaItem(
            kind: .image,
            url: URL(fileURLWithPath: "/tmp/first.png"),
            fileSize: 100,
            duration: nil,
            width: 64,
            height: 64,
            modifiedAt: nil,
            thumbnailData: nil
        )
        let second = MediaItem(
            kind: .image,
            url: URL(fileURLWithPath: "/tmp/second.png"),
            fileSize: 100,
            duration: nil,
            width: 64,
            height: 64,
            modifiedAt: nil,
            thumbnailData: nil
        )

        let firstTask = Task { await loader.load(first) }
        try await waitUntilAsync { await probe.hasBlockedFirstLoad }
        await loader.load(second)
        let secondImage = loader.loadedImage
        firstTask.cancel()
        await probe.releaseFirstLoad()
        await firstTask.value

        XCTAssertEqual(loader.loadedItemID, second.id)
        XCTAssertNotNil(secondImage)
        XCTAssertTrue(loader.loadedImage === secondImage)
    }

    func testRemoveAllPreventsInFlightLoadFromRepopulatingCache() async throws {
        let probe = BlockingThumbnailDataLoader(data: try makeJPEGData())
        let cache = MediaThumbnailImageCache { item, _ in
            await probe.load(item)
        }
        let item = MediaItem(
            kind: .image,
            url: URL(fileURLWithPath: "/tmp/clear-in-flight.png"),
            fileSize: 100,
            duration: nil,
            width: 64,
            height: 64,
            modifiedAt: nil,
            thumbnailData: nil
        )

        let loadTask = Task<Bool, Never> { @MainActor in
            await cache.image(for: item, repairingMissingVideoThumbnail: true) == nil
        }
        try await waitUntilAsync { await probe.hasBlockedFirstLoad }
        cache.removeAll()
        await probe.releaseFirstLoad()
        let loadWasDiscarded = await loadTask.value

        XCTAssertTrue(loadWasDiscarded)
        XCTAssertNil(cache.image(for: item))
    }

    private func waitUntilAsync(
        timeoutIterations: Int = 200,
        condition: () async -> Bool
    ) async throws {
        for _ in 0..<timeoutIterations {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for thumbnail load state")
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

private actor BlockingThumbnailDataLoader {
    private let data: Data
    private var firstLoadContinuation: CheckedContinuation<Void, Never>?
    private(set) var hasBlockedFirstLoad = false
    private(set) var loadCount = 0

    init(data: Data) {
        self.data = data
    }

    func load(_ item: MediaItem) async -> Data? {
        _ = item
        loadCount += 1
        guard loadCount == 1 else { return data }
        hasBlockedFirstLoad = true
        await withCheckedContinuation { continuation in
            firstLoadContinuation = continuation
        }
        return data
    }

    func releaseFirstLoad() {
        firstLoadContinuation?.resume()
        firstLoadContinuation = nil
    }
}
