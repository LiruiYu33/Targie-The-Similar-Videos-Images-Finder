// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import CoreGraphics
import Foundation
import ImageIO

struct ImagePerceptualHash: Hashable, Sendable {
    let mediaID: UUID
    let hashBits: [UInt8]

    func hammingDistance(to other: ImagePerceptualHash) -> Int {
        PerceptualHasher.hammingDistance(hashBits, other.hashBits)
    }

    func similarity(to other: ImagePerceptualHash) -> Double {
        let bitCount = hashBits.count * 8
        guard bitCount > 0 else { return 0 }
        return 1 - Double(hammingDistance(to: other)) / Double(bitCount)
    }
}

enum ImagePerceptualHasher {
    static let inputSize = 32
    static let coefficientSize = 8

    static func hash(for url: URL, id: UUID = UUID()) throws -> ImagePerceptualHash? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return hash(image: image, id: id)
    }

    static func hash(image: CGImage, id: UUID = UUID()) -> ImagePerceptualHash {
        let gray = PerceptualHasher.downsampleToGray(image, size: inputSize)
        let transformed = PerceptualHasher.dct2D(gray, rows: inputSize, cols: inputSize)
        var coefficients: [Double] = []
        coefficients.reserveCapacity(coefficientSize * coefficientSize)
        for row in 0..<coefficientSize {
            for column in 0..<coefficientSize {
                coefficients.append(transformed[row * inputSize + column])
            }
        }

        let thresholdValues = Array(coefficients.dropFirst())
        let sorted = thresholdValues.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        let bits = coefficients.map { $0 >= median }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(8)
        for offset in stride(from: 0, to: bits.count, by: 8) {
            var byte: UInt8 = 0
            for bit in 0..<8 where offset + bit < bits.count {
                if bits[offset + bit] { byte |= UInt8(1 << (7 - bit)) }
            }
            bytes.append(byte)
        }
        return ImagePerceptualHash(mediaID: id, hashBits: bytes)
    }
}
