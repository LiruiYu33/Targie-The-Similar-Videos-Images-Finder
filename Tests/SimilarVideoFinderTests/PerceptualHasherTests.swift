// Targie — Find similar videos on macOS.
// Copyright (C) 2026 Lirui Yu
//
// This file is part of Targie.
//
// Targie is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// by the Free Software Foundation, either version 3 of the License, or
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

final class PerceptualHasherTests: XCTestCase {

    // MARK: - 1D-DCT Tests

    func testDCT1DConstantInputProducesDCOnly() {
        // Constant input [5, 5, 5, 5]: only the DC coefficient (k=0) is non-zero.
        let input = [5.0, 5.0, 5.0, 5.0]
        let result = PerceptualHasher.dct1D(input)
        // DC coefficient = sum x[n] * cos(0) = 4 * 5 = 20.
        XCTAssertEqual(result[0], 20.0, accuracy: 0.01)
        // High-frequency coefficients should be close to 0.
        for k in 1..<result.count {
            XCTAssertAbsLessThan(result[k], 0.01)
        }
    }

    func testDCT1DSingleFrequency() {
        // Input [1, 0, -1, 0]: DC should be 0, with a high-frequency peak.
        let input = [1.0, 0.0, -1.0, 0.0]
        let result = PerceptualHasher.dct1D(input)
        // DC coefficient (k=0) should be close to 0 because the input sums to 0.
        XCTAssertAbsLessThan(result[0], 0.01)
        // At least one high-frequency coefficient should have a significant value.
        let maxHigh = (1..<result.count).map { abs(result[$0]) }.max() ?? 0
        XCTAssertGreaterThan(maxHigh, 0.5)
    }

    func testDCT1DEmptyInput() {
        let result = PerceptualHasher.dct1D([])
        XCTAssertEqual(result.count, 0)
    }

    // MARK: - 2D-DCT Tests

    func testDCT2DConstantImage() {
        // 4x4 constant image, all values 100.
        let N = 4
        let input = [Double](repeating: 100.0, count: N * N)
        let result = PerceptualHasher.dct2D(input, rows: N, cols: N)
        // DC coefficient at [0,0] should be 4*4*100 = 1600.
        XCTAssertEqual(result[0], 1600.0, accuracy: 1.0)
        // All other coefficients should be close to 0.
        for i in 1..<result.count {
            XCTAssertAbsLessThan(result[i], 1.0)
        }
    }

    func testDCT2DWrongSizeReturnsEmpty() {
        let input = [1.0, 2.0, 3.0]  // 3 elements, not 2x4.
        let result = PerceptualHasher.dct2D(input, rows: 2, cols: 4)
        XCTAssertEqual(result.count, 0)
    }

    // MARK: - Hamming Distance Tests

    func testHammingDistanceIdenticalIsZero() {
        let a: [UInt8] = [0xFF, 0x00, 0x12]
        let b: [UInt8] = [0xFF, 0x00, 0x12]
        XCTAssertEqual(PerceptualHasher.hammingDistance(a, b), 0)
    }

    func testHammingDistanceAllDifferent() {
        let a: [UInt8] = [0xFF, 0xFF]
        let b: [UInt8] = [0x00, 0x00]
        // 0xFF ^ 0x00 = 0xFF → 8 bits, × 2 bytes = 16
        XCTAssertEqual(PerceptualHasher.hammingDistance(a, b), 16)
    }

    func testHammingDistancePartialDifference() {
        let a: [UInt8] = [0b10101010]
        let b: [UInt8] = [0b01010101]
        // XOR = 0b11111111 → 8 bits
        XCTAssertEqual(PerceptualHasher.hammingDistance(a, b), 8)
    }

    func testHammingDistanceOneBit() {
        let a: [UInt8] = [0b00000000]
        let b: [UInt8] = [0b00000001]
        XCTAssertEqual(PerceptualHasher.hammingDistance(a, b), 1)
    }

    func testHammingDistanceUnequalLengths() {
        let a: [UInt8] = [0xFF]
        let b: [UInt8] = [0xFF, 0x00]
        // Different lengths return max length * 8 = 16.
        XCTAssertEqual(PerceptualHasher.hammingDistance(a, b), 16)
    }

    // MARK: - Hash Computation Tests

    func testComputeHashProducesDeterministicResult() throws {
        // Running the same frame data twice should produce the same hash.
        let frames = makeTestFrames(seed: 42, count: 5)
        let hash1 = try XCTUnwrap(PerceptualHasher.computeHash(frames: frames))
        let hash2 = try XCTUnwrap(PerceptualHasher.computeHash(frames: frames))
        XCTAssertEqual(hash1.hashBits, hash2.hashBits)
    }

    func testComputeHashDifferentFramesProduceDifferentHashes() throws {
        let framesA = makeTestFrames(seed: 42, count: 5)
        let framesB = makeTestFrames(seed: 99, count: 5)
        let hashA = try XCTUnwrap(PerceptualHasher.computeHash(frames: framesA))
        let hashB = try XCTUnwrap(PerceptualHasher.computeHash(frames: framesB))
        XCTAssertGreaterThan(hashA.hammingDistance(to: hashB), 0)
    }

    func testComputeHashIdenticalFramesProduceSameHash() throws {
        let framesA = makeTestFrames(seed: 42, count: 5)
        let hashA = try XCTUnwrap(PerceptualHasher.computeHash(frames: framesA))

        // Copy identical frame data.
        let framesB = framesA.map { PerceptualHasher.GrayFrame(pixels: $0.pixels) }
        let hashB = try XCTUnwrap(PerceptualHasher.computeHash(frames: framesB))
        XCTAssertEqual(hashA.hammingDistance(to: hashB), 0)
    }

    func testVideoPerceptualHashSimilarity() throws {
        let framesA = makeTestFrames(seed: 42, count: 5)
        let framesB = makeTestFrames(seed: 42, count: 5)
        let hashA = try XCTUnwrap(PerceptualHasher.computeHash(frames: framesA))
        let hashB = try XCTUnwrap(PerceptualHasher.computeHash(frames: framesB))
        XCTAssertEqual(hashA.similarity(to: hashB), 1.0, accuracy: 0.01)
    }

    func testHashBitCountMatchesExpected() throws {
        // Each frame keeps 4x4 = 16 coefficients; five frames keep the first four temporal terms.
        // Binarization gives 16x4 = 64 bits -> 8 bytes.
        let frames = makeTestFrames(seed: 42, count: 5)
        let hash = try XCTUnwrap(PerceptualHasher.computeHash(frames: frames))
        // 64 bits / 8 = 8 bytes
        XCTAssertEqual(hash.hashBits.count, 8)
    }

    func testNormalizeSampleSlotsRequiresAtLeastTwoDecodedFrames() {
        let frame = makeTestFrames(seed: 1, count: 1)[0]

        XCTAssertNil(PerceptualHasher.normalizeSampleSlots([frame, nil, nil, nil, nil]))
        XCTAssertNil(PerceptualHasher.normalizeSampleSlots([nil, nil, nil, nil, nil]))
    }

    func testNormalizeSampleSlotsPreservesAllFiveOriginalSlots() throws {
        let frames = makeTestFrames(seed: 2, count: 5)

        let normalized = try XCTUnwrap(PerceptualHasher.normalizeSampleSlots(frames.map(Optional.some)))

        XCTAssertEqual(normalized.map(\.pixels), frames.map(\.pixels))
    }

    func testNormalizeSampleSlotsFillsMissingMiddleSlotWithoutShiftingLaterFrames() throws {
        let frames = makeTestFrames(seed: 3, count: 5)
        let normalized = try XCTUnwrap(PerceptualHasher.normalizeSampleSlots([
            frames[0],
            frames[1],
            nil,
            frames[3],
            frames[4]
        ]))

        XCTAssertEqual(normalized[2].pixels, frames[1].pixels)
        XCTAssertEqual(normalized[3].pixels, frames[3].pixels)
        XCTAssertEqual(normalized[4].pixels, frames[4].pixels)
    }

    func testNormalizeSampleSlotsUsesDeterministicNearestFrameAtEdges() throws {
        let frames = makeTestFrames(seed: 4, count: 5)
        let normalized = try XCTUnwrap(PerceptualHasher.normalizeSampleSlots([
            nil,
            frames[1],
            frames[2],
            frames[3],
            nil
        ]))

        XCTAssertEqual(normalized[0].pixels, frames[1].pixels)
        XCTAssertEqual(normalized[4].pixels, frames[3].pixels)
    }

    func testNormalizedTwoThreeFourAndFiveFrameInputsProduceEightByteHashes() throws {
        let frames = makeSmoothTestFrames()
        let slotSets: [[PerceptualHasher.GrayFrame?]] = [
            [frames[0], nil, nil, nil, frames[4]],
            [frames[0], nil, frames[2], nil, frames[4]],
            [frames[0], frames[1], nil, frames[3], frames[4]],
            frames.map(Optional.some)
        ]

        for slots in slotSets {
            let normalized = try XCTUnwrap(PerceptualHasher.normalizeSampleSlots(slots))
            let hash = try XCTUnwrap(PerceptualHasher.computeHash(frames: normalized))
            XCTAssertEqual(normalized.count, PerceptualHasher.sampleCount)
            XCTAssertEqual(hash.hashBits.count, PerceptualHasher.hashByteCount)
        }
    }

    func testComputeHashRejectsNonCanonicalFrameCount() {
        XCTAssertNil(PerceptualHasher.computeHash(frames: makeTestFrames(seed: 5, count: 4)))
        XCTAssertNil(PerceptualHasher.computeHash(frames: makeTestFrames(seed: 5, count: 6)))
    }

    func testUnequalLengthVideoHashSimilarityReturnsZero() {
        let short = VideoPerceptualHash(videoID: UUID(), hashBits: [UInt8](repeating: 0, count: 4))
        let canonical = VideoPerceptualHash(videoID: UUID(), hashBits: [UInt8](repeating: 0, count: 8))

        XCTAssertEqual(short.similarity(to: canonical), 0)
        XCTAssertEqual(canonical.similarity(to: short), 0)
    }

    func testNormalizedMissingSlotsRemainWithinCandidateDistance() throws {
        let frames = makeSmoothTestFrames()
        let completeFrames = try XCTUnwrap(PerceptualHasher.normalizeSampleSlots(frames.map(Optional.some)))
        let partialFrames = try XCTUnwrap(PerceptualHasher.normalizeSampleSlots([
            frames[0],
            nil,
            frames[2],
            nil,
            frames[4]
        ]))
        let completeHash = try XCTUnwrap(PerceptualHasher.computeHash(frames: completeFrames))
        let partialHash = try XCTUnwrap(PerceptualHasher.computeHash(frames: partialFrames))
        var tree = BKTree<VideoPerceptualHash>()
        tree.insert(completeHash, distance: { $0.hammingDistance(to: $1) })

        let matches = tree.search(
            partialHash,
            maxDistance: SimilarityPipeline.perceptualMaxDistance,
            distance: { $0.hammingDistance(to: $1) }
        )

        XCTAssertTrue(matches.contains { $0.item.videoID == completeHash.videoID })
    }

    // MARK: - Grayscale Downsampling Tests

    func testDownsampleToGrayProducesCorrectCount() {
        // Create a simple CGImage and test downsampling.
        let size = 32
        let result = PerceptualHasher.downsampleToGray(makeSolidCGImage(value: 128, width: 64, height: 64), size: size)
        XCTAssertEqual(result.count, size * size)
    }

    func testDownsampleToGrayConstantImage() {
        let result = PerceptualHasher.downsampleToGray(makeSolidCGImage(value: 200, width: 100, height: 100), size: 8)
        for pixel in result {
            XCTAssertEqual(pixel, 200.0, accuracy: 2.0)  // Allow scaling error.
        }
    }

    // MARK: - Helpers

    private func makeTestFrames(seed: Int, count: Int) -> [PerceptualHasher.GrayFrame] {
        // Use simple pseudo-random data to generate dctSize x dctSize grayscale frames.
        let N = PerceptualHasher.dctSize
        var frames: [PerceptualHasher.GrayFrame] = []
        for i in 0..<count {
            var pixels = [Double]()
            for j in 0..<N * N {
                // Pseudo-random: combine seed and position to produce distinct deterministic values.
                pixels.append(Double((seed * 31 + i * 17 + j * 7) % 256))
            }
            frames.append(PerceptualHasher.GrayFrame(pixels: pixels))
        }
        return frames
    }

    private func makeSmoothTestFrames() -> [PerceptualHasher.GrayFrame] {
        let size = PerceptualHasher.dctSize
        return (0..<PerceptualHasher.sampleCount).map { frameIndex in
            let pixels = (0..<size * size).map { pixelIndex in
                Double((pixelIndex * 3 + frameIndex * 5) % 256)
            }
            return PerceptualHasher.GrayFrame(pixels: pixels)
        }
    }

    private func makeSolidCGImage(value: UInt8, width: Int, height: Int) -> CGImage {
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        // Fill with gray value in BGRA format
        for i in 0..<width * height {
            buffer[i * 4 + 0] = value  // B
            buffer[i * 4 + 1] = value  // G
            buffer[i * 4 + 2] = value  // R
            buffer[i * 4 + 3] = 255    // A
        }

        let data = Data(buffer) as CFData
        let provider = CGDataProvider(data: data)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}

// MARK: - Helper Assertions

private func XCTAssertAbsLessThan(_ value: Double, _ threshold: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssert(abs(value) < threshold, "|\(value)| >= \(threshold)", file: (file), line: line)
}
