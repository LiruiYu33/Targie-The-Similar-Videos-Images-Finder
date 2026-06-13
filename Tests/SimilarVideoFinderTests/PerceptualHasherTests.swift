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
        // 常数输入 [5, 5, 5, 5]: 只有 DC 系数(k=0)非零
        let input = [5.0, 5.0, 5.0, 5.0]
        let result = PerceptualHasher.dct1D(input)
        // DC 系数 = Σ x[n] · cos(0) = 4 × 5 = 20
        XCTAssertEqual(result[0], 20.0, accuracy: 0.01)
        // 高频系数应接近 0
        for k in 1..<result.count {
            XCTAssertAbsLessThan(result[k], 0.01)
        }
    }

    func testDCT1DSingleFrequency() {
        // 输入 [1, 0, -1, 0]: DC 应为 0, 高频应有峰值
        let input = [1.0, 0.0, -1.0, 0.0]
        let result = PerceptualHasher.dct1D(input)
        // DC 系数 (k=0) 应该接近 0 (因为输入和为 0)
        XCTAssertAbsLessThan(result[0], 0.01)
        // 至少一个高频系数应有显著值
        let maxHigh = (1..<result.count).map { abs(result[$0]) }.max() ?? 0
        XCTAssertGreaterThan(maxHigh, 0.5)
    }

    func testDCT1DEmptyInput() {
        let result = PerceptualHasher.dct1D([])
        XCTAssertEqual(result.count, 0)
    }

    // MARK: - 2D-DCT Tests

    func testDCT2DConstantImage() {
        // 4×4 常数图像 (全为 100)
        let N = 4
        let input = [Double](repeating: 100.0, count: N * N)
        let result = PerceptualHasher.dct2D(input, rows: N, cols: N)
        // DC 系数 (位置 [0,0]) 应为 4×4×100 = 1600
        XCTAssertEqual(result[0], 1600.0, accuracy: 1.0)
        // 所有其他系数应接近 0
        for i in 1..<result.count {
            XCTAssertAbsLessThan(result[i], 1.0)
        }
    }

    func testDCT2DWrongSizeReturnsEmpty() {
        let input = [1.0, 2.0, 3.0]  // 3 个元素 ≠ 2×4
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
        // 长度不同 → 返回最大长度 × 8 = 16
        XCTAssertEqual(PerceptualHasher.hammingDistance(a, b), 16)
    }

    // MARK: - Hash Computation Tests

    func testComputeHashProducesDeterministicResult() {
        // 用相同的帧数据两次, 应得到相同哈希
        let frames = makeTestFrames(seed: 42, count: 5)
        let hash1 = PerceptualHasher.computeHash(frames: frames)
        let hash2 = PerceptualHasher.computeHash(frames: frames)
        XCTAssertEqual(hash1.hashBits, hash2.hashBits)
    }

    func testComputeHashDifferentFramesProduceDifferentHashes() {
        let framesA = makeTestFrames(seed: 42, count: 5)
        let framesB = makeTestFrames(seed: 99, count: 5)
        let hashA = PerceptualHasher.computeHash(frames: framesA)
        let hashB = PerceptualHasher.computeHash(frames: framesB)
        XCTAssertGreaterThan(hashA.hammingDistance(to: hashB), 0)
    }

    func testComputeHashIdenticalFramesProduceSameHash() {
        let framesA = makeTestFrames(seed: 42, count: 5)
        let hashA = PerceptualHasher.computeHash(frames: framesA)

        // 复制完全相同的帧数据
        let framesB = framesA.map { PerceptualHasher.GrayFrame(pixels: $0.pixels) }
        let hashB = PerceptualHasher.computeHash(frames: framesB)
        XCTAssertEqual(hashA.hammingDistance(to: hashB), 0)
    }

    func testVideoPerceptualHashSimilarity() {
        let framesA = makeTestFrames(seed: 42, count: 5)
        let framesB = makeTestFrames(seed: 42, count: 5)
        let hashA = PerceptualHasher.computeHash(frames: framesA)
        let hashB = PerceptualHasher.computeHash(frames: framesB)
        XCTAssertEqual(hashA.similarity(to: hashB), 1.0, accuracy: 0.01)
    }

    func testHashBitCountMatchesExpected() {
        // 每帧取 4×4=16 个系数, 5帧, 时间轴取前4 → 16×4=64 个值
        // 二值化 → 64 bits → 8 bytes
        let frames = makeTestFrames(seed: 42, count: 5)
        let hash = PerceptualHasher.computeHash(frames: frames)
        // 64 bits / 8 = 8 bytes
        XCTAssertEqual(hash.hashBits.count, 8)
    }

    // MARK: - Grayscale Downsampling Tests

    func testDownsampleToGrayProducesCorrectCount() {
        // 创建一个简单的 CGImage 并测试缩放
        let size = 32
        let result = PerceptualHasher.downsampleToGray(makeSolidCGImage(value: 128, width: 64, height: 64), size: size)
        XCTAssertEqual(result.count, size * size)
    }

    func testDownsampleToGrayConstantImage() {
        let result = PerceptualHasher.downsampleToGray(makeSolidCGImage(value: 200, width: 100, height: 100), size: 8)
        for pixel in result {
            XCTAssertEqual(pixel, 200.0, accuracy: 2.0)  // 允许缩放误差
        }
    }

    // MARK: - Helpers

    private func makeTestFrames(seed: Int, count: Int) -> [PerceptualHasher.GrayFrame] {
        // 使用简单伪随机生成 dctSize × dctSize 灰度数据
        let N = PerceptualHasher.dctSize
        var frames: [PerceptualHasher.GrayFrame] = []
        for i in 0..<count {
            var pixels = [Double]()
            for j in 0..<N * N {
                // 伪随机: 使用 seed 和位置生成不同但确定性值
                pixels.append(Double((seed * 31 + i * 17 + j * 7) % 256))
            }
            frames.append(PerceptualHasher.GrayFrame(pixels: pixels))
        }
        return frames
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
