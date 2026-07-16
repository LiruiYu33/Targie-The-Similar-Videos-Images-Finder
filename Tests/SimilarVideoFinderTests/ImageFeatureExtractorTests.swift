// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SimilarVideoFinder

final class ImageFeatureExtractorTests: XCTestCase {
    func testVisionInputIsDownsampledAndAppliesOrientation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageFeatureExtractorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rotated-large.jpg")
        try writeJPEG(to: url, width: 2_048, height: 1_024, orientation: 6)

        let image = try XCTUnwrap(ImageFeatureExtractor.inputImage(for: url))

        XCTAssertLessThanOrEqual(max(image.width, image.height), ImageFeatureExtractor.maximumInputPixelSize)
        XCTAssertLessThan(image.width, image.height)
    }

    func testVisionFeatureExtractionAcceptsDownsampledLargeImage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageFeatureExtractorVisionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("large.jpg")
        try writeJPEG(to: url, width: 2_048, height: 1_024, orientation: 1)

        _ = try await ImageFeatureExtractor().feature(for: url)
    }

    func testFeatureCacheLimitsConcurrentExtractions() async {
        let extractor = ConcurrencyTrackingImageFeatureExtractor()
        let cache = ImageFeatureCache(extractor: extractor, maxConcurrentExtractions: 2)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<8 {
                group.addTask {
                    _ = try? await cache.feature(
                        for: URL(fileURLWithPath: "/tmp/limited-feature-\(index).jpg")
                    )
                }
            }
        }

        let maximumConcurrentCount = await extractor.maximumConcurrentCount
        XCTAssertEqual(maximumConcurrentCount, 2)
    }

    private func writeJPEG(to url: URL, width: Int, height: Int, orientation: Int) throws {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(CGColor(red: 0.12, green: 0.35, blue: 0.72, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor.white)
        context.fillEllipse(in: CGRect(x: width / 5, y: height / 4, width: width / 3, height: height / 2))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL,
                  UTType.jpeg.identifier as CFString,
                  1,
                  nil
              )
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyOrientation: orientation
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}

private actor ConcurrencyTrackingImageFeatureExtractor: ImageFeatureExtracting {
    private var activeCount = 0
    private(set) var maximumConcurrentCount = 0

    func feature(for url: URL) async throws -> ImageFeature {
        _ = url
        activeCount += 1
        maximumConcurrentCount = max(maximumConcurrentCount, activeCount)
        defer { activeCount -= 1 }
        try await Task.sleep(for: .milliseconds(25))
        throw CocoaError(.fileReadCorruptFile)
    }

    nonisolated func similarity(between first: ImageFeature, and second: ImageFeature) throws -> Double {
        _ = first
        _ = second
        throw CocoaError(.featureUnsupported)
    }
}
