// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SimilarVideoFinder

final class ImageScannerTests: XCTestCase {
    func testDiscoversSupportedImagesRecursivelyInStableOrder() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        let package = root.appendingPathComponent("Hidden.app", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)

        let names = ["z.JPG", "a.jpeg", "b.png", "c.heic", "d.webp", "e.tif", "f.tiff", "g.gif", "h.bmp"]
        for name in names { FileManager.default.createFile(atPath: root.appendingPathComponent(name).path, contents: Data()) }
        FileManager.default.createFile(atPath: nested.appendingPathComponent("i.PNG").path, contents: Data())
        FileManager.default.createFile(atPath: root.appendingPathComponent("ignored.raw").path, contents: Data())
        FileManager.default.createFile(atPath: package.appendingPathComponent("inside.jpg").path, contents: Data())

        let found = try ImageScanner.discoverImageURLs(in: root)

        XCTAssertEqual(found.map(\.lastPathComponent), ["a.jpeg", "b.png", "c.heic", "d.webp", "e.tif", "f.tiff", "g.gif", "h.bmp", "i.PNG", "z.JPG"])
    }

    func testLoadsPNGDimensionsAndThumbnail() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("sample.png")
        try writePNG(width: 40, height: 20, to: url)

        let result = try await ImageScanner().scan(folder: root) { _ in }

        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.images.count, 1)
        XCTAssertEqual(result.images[0].kind, .image)
        XCTAssertNil(result.images[0].duration)
        XCTAssertEqual(result.images[0].width, 40)
        XCTAssertEqual(result.images[0].height, 20)
        XCTAssertNotNil(result.images[0].thumbnailData)
    }

    func testOneUnreadableImageDoesNotAbortOtherLoads() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["bad.jpg", "good.jpg"] {
            FileManager.default.createFile(atPath: root.appendingPathComponent(name).path, contents: Data())
        }
        let scanner = ImageScanner(maxConcurrentLoads: 2) { url in
            if url.lastPathComponent == "bad.jpg" { throw TestError.unreadable }
            return MediaItem(
                kind: .image,
                url: url,
                fileSize: 1,
                duration: nil,
                width: 10,
                height: 10,
                modifiedAt: nil,
                thumbnailData: Data([1])
            )
        }

        let result = try await scanner.scan(folder: root) { _ in }

        XCTAssertEqual(result.images.map(\.filename), ["good.jpg"])
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues[0].url.lastPathComponent, "bad.jpg")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ImageScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writePNG(width: Int, height: Int, to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw TestError.fixtureCreation
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw TestError.fixtureCreation }
    }
}

private enum TestError: Error {
    case unreadable
    case fixtureCreation
}
