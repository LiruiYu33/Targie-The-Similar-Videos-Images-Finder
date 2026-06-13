// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import CoreGraphics
import XCTest
@testable import SimilarVideoFinder

final class ImagePerceptualHasherTests: XCTestCase {
    func testIdenticalPixelsProduceIdenticalHashes() throws {
        let image = try makePattern(width: 64, height: 64, inverted: false)
        let first = ImagePerceptualHasher.hash(image: image)
        let second = ImagePerceptualHasher.hash(image: image)
        XCTAssertEqual(first.hashBits, second.hashBits)
        XCTAssertEqual(first.hammingDistance(to: second), 0)
    }

    func testResizedPatternRemainsHighlySimilar() throws {
        let small = ImagePerceptualHasher.hash(image: try makePattern(width: 64, height: 64, inverted: false))
        let large = ImagePerceptualHasher.hash(image: try makePattern(width: 256, height: 256, inverted: false))
        XCTAssertGreaterThanOrEqual(small.similarity(to: large), 0.85)
    }

    func testDifferentPatternsDoNotLookIdentical() throws {
        let normal = ImagePerceptualHasher.hash(image: try makePattern(width: 128, height: 128, inverted: false))
        let inverted = ImagePerceptualHasher.hash(image: try makePattern(width: 128, height: 128, inverted: true))
        XCTAssertLessThan(normal.similarity(to: inverted), 0.9)
    }

    private func makePattern(width: Int, height: Int, inverted: Bool) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw FixtureError.creation }

        context.setFillColor((inverted ? CGColor.white : CGColor.black))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor((inverted ? CGColor.black : CGColor.white))
        context.fill(CGRect(x: 0, y: 0, width: width * 2 / 3, height: height / 3))
        context.fillEllipse(in: CGRect(x: width / 3, y: height / 2, width: width / 3, height: height / 3))
        guard let image = context.makeImage() else { throw FixtureError.creation }
        return image
    }
}

private enum FixtureError: Error { case creation }
