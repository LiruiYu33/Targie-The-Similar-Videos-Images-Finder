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

import AVFoundation
import Foundation

// MARK: - Video Perceptual Hash Type

struct VideoPerceptualHash: Hashable, Sendable {
    let videoID: UUID
    let hashBits: [UInt8]  // Compact byte vector for the binarized DCT-3D fingerprint.

    /// Computes the Hamming distance to another hash, measured as differing bit count.
    func hammingDistance(to other: VideoPerceptualHash) -> Int {
        PerceptualHasher.hammingDistance(hashBits, other.hashBits)
    }

    /// Converts Hamming distance to a 0...1 similarity score (0 = entirely different, 1 = identical).
    func similarity(to other: VideoPerceptualHash) -> Double {
        guard !hashBits.isEmpty, hashBits.count == other.hashBits.count else { return 0 }
        let distance = hammingDistance(to: other)
        let maxBits = hashBits.count * 8
        return max(0, 1.0 - Double(distance) / Double(maxBits))
    }
}

// MARK: - Perceptual Hasher

enum PerceptualHasher {
    static let algorithmVersion = "video-dct3d-v2"
    static let sampleCount = 5
    static let hashByteCount = 8
    private static let temporalCoefficientCount = 4
    private static let standardFrameTolerance = CMTime(seconds: 0.35, preferredTimescale: 600)

    // Extract frames -> downsample to grayscale -> DCT-3D -> binarize -> byte vector.
    static func hash(for url: URL, id: UUID = UUID()) async throws -> VideoPerceptualHash? {
        let frames = try await extractGrayFrames(from: url)
        return computeHash(frames: frames, id: id)
    }

    // MARK: - Hamming Distance

    static func hammingDistance(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return max(a.count, b.count) * 8 }
        var count = 0
        for i in a.indices {
            let xor = a[i] ^ b[i]
            // popcount: count the 1 bits in the xor value.
            count += xor.nonzeroBitCount
        }
        return count
    }

    // MARK: - Frame Extraction (Grayscale)

    private static let samplePositions = [0.08, 0.28, 0.50, 0.72, 0.92]

    private static func extractGrayFrames(from url: URL) async throws -> [GrayFrame] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        var sampleSlots: [GrayFrame?] = []
        sampleSlots.reserveCapacity(sampleCount)
        for position in samplePositions {
            let time = CMTime(seconds: duration * position, preferredTimescale: 600)
            sampleSlots.append(extractGrayFrame(at: time, using: generator))
        }
        return normalizeSampleSlots(sampleSlots) ?? []
    }

    private static func extractGrayFrame(
        at time: CMTime,
        using generator: AVAssetImageGenerator
    ) -> GrayFrame? {
        generator.requestedTimeToleranceBefore = standardFrameTolerance
        generator.requestedTimeToleranceAfter = standardFrameTolerance
        if let frame = decodeGrayFrame(at: time, using: generator) {
            return frame
        }

        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        defer {
            generator.requestedTimeToleranceBefore = standardFrameTolerance
            generator.requestedTimeToleranceAfter = standardFrameTolerance
        }
        return decodeGrayFrame(at: time, using: generator)
    }

    private static func decodeGrayFrame(
        at time: CMTime,
        using generator: AVAssetImageGenerator
    ) -> GrayFrame? {
        guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        let pixels = downsampleToGray(image, size: dctSize)
        guard pixels.count == dctSize * dctSize else { return nil }
        return GrayFrame(pixels: pixels)
    }

    static func normalizeSampleSlots(_ sampleSlots: [GrayFrame?]) -> [GrayFrame]? {
        guard sampleSlots.count == sampleCount else { return nil }
        let decodedIndices = sampleSlots.indices.filter { sampleSlots[$0] != nil }
        guard decodedIndices.count >= 2 else { return nil }

        var normalized: [GrayFrame] = []
        normalized.reserveCapacity(sampleCount)
        for index in sampleSlots.indices {
            if let frame = sampleSlots[index] {
                normalized.append(frame)
                continue
            }
            let nearestIndex = decodedIndices.min { lhs, rhs in
                let lhsDistance = abs(samplePositions[lhs] - samplePositions[index])
                let rhsDistance = abs(samplePositions[rhs] - samplePositions[index])
                if lhsDistance == rhsDistance { return lhs < rhs }
                return lhsDistance < rhsDistance
            }
            guard let nearestIndex, let frame = sampleSlots[nearestIndex] else { return nil }
            normalized.append(frame)
        }
        return normalized
    }

    // MARK: - Grayscale Downsampling

    /// DCT input size: 8x8 grayscale pixels.
    static let dctSize = 8

    /// Downsamples a CGImage into a dctSize x dctSize grayscale pixel array.
    static func downsampleToGray(_ image: CGImage, size: Int) -> [Double] {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return [] }

        // Simple area-mean scaling: each output pixel is the average brightness of the corresponding input region.
        var result = [Double]()
        result.reserveCapacity(size * size)

        let blockW = Double(width) / Double(size)
        let blockH = Double(height) / Double(size)

        // Extract full-resolution grayscale pixels first.
        let fullGray = fullGrayPixels(image)
        guard fullGray.count == width * height else { return [] }

        for y in 0..<size {
            for x in 0..<size {
                let startX = Int(Double(x) * blockW)
                let startY = Int(Double(y) * blockH)
                let endX = min(Int(Double(x + 1) * blockW), width)
                let endY = min(Int(Double(y + 1) * blockH), height)

                var sum = 0.0
                var count = 0
                for py in startY..<endY {
                    for px in startX..<endX {
                        sum += fullGray[py * width + px]
                        count += 1
                    }
                }
                result.append(count > 0 ? sum / Double(count) : 0)
            }
        }
        return result
    }

    /// Extracts full-resolution grayscale pixels from a CGImage (0-255 -> 0.0-255.0).
    private static func fullGrayPixels(_ image: CGImage) -> [Double] {
        let width = image.width
        let height = image.height

        // Render through RGB and derive grayscale values for better compatibility without relying on a grayscale color space.
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        let byteCount = height * bytesPerRow
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
        buffer.initialize(repeating: 0, count: byteCount)
        defer {
            buffer.deinitialize(count: byteCount)
            buffer.deallocate()
        }
        guard let context = CGContext(
            data: buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return [] }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // BGRA32Little: B=idx+0, G=idx+1, R=idx+2, A=idx+3
        // Grayscale = 0.299*R + 0.587*G + 0.114*B.
        var gray = [Double]()
        gray.reserveCapacity(width * height)
        for i in 0..<width * height {
            let b = Double(buffer[i * 4 + 0])
            let g = Double(buffer[i * 4 + 1])
            let r = Double(buffer[i * 4 + 2])
            gray.append(0.114 * b + 0.587 * g + 0.299 * r)
        }
        return gray
    }

    // MARK: - DCT-3D Hash Computation

    /// Grayscale frame data.
    struct GrayFrame {
        let pixels: [Double]  // dctSize × dctSize
    }

    /// Computes a 3D-DCT perceptual hash from multiple grayscale frames.
    static func computeHash(frames: [GrayFrame], id: UUID = UUID()) -> VideoPerceptualHash? {
        guard frames.count == sampleCount,
              frames.allSatisfy({ $0.pixels.count == dctSize * dctSize })
        else { return nil }

        // Step 1: Run 2D-DCT on each frame and keep the low-frequency coefficients in the top-left corner.
        let frameCoeffs: [[Double]] = frames.map { frame in
            let dct2d = dct2D(frame.pixels, rows: dctSize, cols: dctSize)
            // Keep the top-left 4x4 = 16 low-frequency coefficients.
            var coeffs = [Double]()
            for row in 0..<4 {
                for col in 0..<4 {
                    coeffs.append(dct2d[row * dctSize + col])
                }
            }
            return coeffs
        }

        // Step 2: Temporal DCT.
        // Each frame has 16 coefficients, forming a 5x16 matrix for five frames.
        // Run 1D-DCT on each column, i.e. on 16 temporal series.
        let numFrames = frameCoeffs.count
        let numCoeffs = frameCoeffs[0].count

        // Run 1D-DCT on each column and keep the first four temporal low-frequency coefficients.
        // This produces 16 x 4 = 64 values.
        var finalCoeffs = [Double]()
        finalCoeffs.reserveCapacity(numCoeffs * temporalCoefficientCount)

        for col in 0..<numCoeffs {
            var column = [Double]()
            for row in 0..<numFrames {
                column.append(frameCoeffs[row][col])
            }
            let dct1d = dct1D(column)
            guard dct1d.count >= temporalCoefficientCount else { return nil }
            finalCoeffs.append(contentsOf: dct1d.prefix(temporalCoefficientCount))
        }
        guard finalCoeffs.count == hashByteCount * 8 else { return nil }

        // Step 3: Binarize using the median as threshold.
        let sorted = finalCoeffs.sorted()
        let median = sorted[sorted.count / 2]

        // Step 4: Pack bits into bytes (8 bits -> 1 byte).
        let bits = finalCoeffs.map { $0 >= median ? 1 : 0 }
        var hashBytes = [UInt8]()
        for i in stride(from: 0, to: bits.count, by: 8) {
            var byte: UInt8 = 0
            for j in 0..<8 where i + j < bits.count {
                if bits[i + j] == 1 { byte |= UInt8(1 << (7 - j)) }
            }
            hashBytes.append(byte)
        }
        guard hashBytes.count == hashByteCount else { return nil }

        return VideoPerceptualHash(videoID: id, hashBits: hashBytes)
    }

    // MARK: - 1D-DCT Type-II

    /// Standard DCT Type-II: X[k] = sum x[n] * cos(pi*(2n+1)*k / 2N).
    static func dct1D(_ input: [Double]) -> [Double] {
        let N = input.count
        guard N > 0 else { return [] }
        var output = [Double]()
        output.reserveCapacity(N)
        for k in 0..<N {
            var sum = 0.0
            for n in 0..<N {
                sum += input[n] * cos(Double.pi * Double(2 * n + 1) * Double(k) / Double(2 * N))
            }
            output.append(sum)
        }
        return output
    }

    // MARK: - 2D-DCT

    /// 2D-DCT: run 1D-DCT on each row, then on each column.
    static func dct2D(_ input: [Double], rows: Int, cols: Int) -> [Double] {
        guard input.count == rows * cols else { return [] }

        // Step 1: Run 1D-DCT on each row.
        var intermediate = [Double]()
        intermediate.reserveCapacity(rows * cols)
        for row in 0..<rows {
            let rowSlice = Array(input[row * cols..<(row + 1) * cols])
            let dctRow = dct1D(rowSlice)
            intermediate.append(contentsOf: dctRow)
        }

        // Step 2: Run 1D-DCT on each column.
        var output = [Double]()
        output.reserveCapacity(rows * cols)
        for col in 0..<cols {
            let column = (0..<rows).map { intermediate[$0 * cols + col] }
            let dctCol = dct1D(column)
            output.append(contentsOf: dctCol)
        }

        // The output is column-major; convert it back to row-major order.
        var rowMajor = [Double]()
        rowMajor.reserveCapacity(rows * cols)
        for row in 0..<rows {
            for col in 0..<cols {
                rowMajor.append(output[col * rows + row])
            }
        }
        return rowMajor
    }
}
