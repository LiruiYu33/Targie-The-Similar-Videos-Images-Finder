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
    let hashBits: [UInt8]  // 紧凑字节向量 (DCT-3D 二值化指纹)

    /// 计算与另一个哈希的 Hamming 距离 (不同 bit 数)
    func hammingDistance(to other: VideoPerceptualHash) -> Int {
        PerceptualHasher.hammingDistance(hashBits, other.hashBits)
    }

    /// Hamming 距离转为 0-1 相似度分数 (0 = 完全不同, 1 = 完全相同)
    func similarity(to other: VideoPerceptualHash) -> Double {
        let distance = hammingDistance(to: other)
        let maxBits = hashBits.count * 8
        guard maxBits > 0 else { return 0 }
        return 1.0 - Double(distance) / Double(maxBits)
    }
}

// MARK: - Perceptual Hasher

enum PerceptualHasher {
    // 从视频提取帧 → 缩放灰度 → DCT-3D → 二值化 → 字节向量
    static func hash(for url: URL, id: UUID = UUID()) async throws -> VideoPerceptualHash? {
        let frames = try await extractGrayFrames(from: url)
        guard frames.count >= 2 else { return nil }
        return computeHash(frames: frames, id: id)
    }

    // MARK: - Hamming Distance

    static func hammingDistance(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return max(a.count, b.count) * 8 }
        var count = 0
        for i in a.indices {
            let xor = a[i] ^ b[i]
            // popcount: 统计 xor 中 1-bit 的个数
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
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.35, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.35, preferredTimescale: 600)

        var frames: [GrayFrame] = []
        for position in samplePositions {
            let time = CMTime(seconds: duration * position, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
            let gray = downsampleToGray(cgImage, size: dctSize)
            guard gray.count == dctSize * dctSize else { continue }
            frames.append(GrayFrame(pixels: gray))
        }
        return frames
    }

    // MARK: - Grayscale Downsampling

    /// DCT 输入尺寸: 8×8 灰度像素
    static let dctSize = 8

    /// 将 CGImage 缩放为 dctSize × dctSize 灰度像素数组
    static func downsampleToGray(_ image: CGImage, size: Int) -> [Double] {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return [] }

        // 简单区域均值缩放: 每个输出像素 = 对应输入区域的平均亮度
        var result = [Double]()
        result.reserveCapacity(size * size)

        let blockW = Double(width) / Double(size)
        let blockH = Double(height) / Double(size)

        // 先提取完整灰度像素
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

    /// 提取 CGImage 全尺寸灰度像素 (0-255 → 0.0-255.0)
    private static func fullGrayPixels(_ image: CGImage) -> [Double] {
        let width = image.width
        let height = image.height

        // 使用 RGB 渲染后取灰度分量 (更兼容, 不依赖灰度色彩空间)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return [] }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // BGRA32Little: B=idx+0, G=idx+1, R=idx+2, A=idx+3
        // 灰度 = 0.299*R + 0.587*G + 0.114*B
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

    /// 灰度帧数据
    struct GrayFrame {
        let pixels: [Double]  // dctSize × dctSize
    }

    /// 从多帧灰度数据计算 3D-DCT 感知哈希
    static func computeHash(frames: [GrayFrame], id: UUID = UUID()) -> VideoPerceptualHash {
        // Step 1: 对每帧做 2D-DCT, 取左上角低频系数
        let frameCoeffs: [[Double]] = frames.map { frame in
            let dct2d = dct2D(frame.pixels, rows: dctSize, cols: dctSize)
            // 取左上角 4×4 = 16 个低频系数
            var coeffs = [Double]()
            for row in 0..<4 {
                for col in 0..<4 {
                    coeffs.append(dct2d[row * dctSize + col])
                }
            }
            return coeffs
        }

        // Step 2: 时间轴 DCT
        // 每帧有 16 个系数，5 帧排列为 5×16 矩阵
        // 对每列 (16个时间序列) 做 1D-DCT
        let numFrames = frameCoeffs.count
        let numCoeffs = frameCoeffs[0].count

        // 将帧系数转置为 (numCoeffs × numFrames) 的列向量
        var temporalCoeffs = [Double]()
        temporalCoeffs.reserveCapacity(numCoeffs * numFrames)

        // 对每列做 1D-DCT, 取前 4 个时间低频系数
        // 最终得到 16 × 4 = 64 个值
        var finalCoeffs = [Double]()
        finalCoeffs.reserveCapacity(numCoeffs * 4)

        for col in 0..<numCoeffs {
            var column = [Double]()
            for row in 0..<numFrames {
                column.append(frameCoeffs[row][col])
            }
            let dct1d = dct1D(column)
            // 取前 4 个时间低频系数
            for i in 0..<min(4, dct1d.count) {
                finalCoeffs.append(dct1d[i])
            }
        }

        // Step 3: 二值化 — 取中值阈值
        let sorted = finalCoeffs.sorted()
        let median = sorted[sorted.count / 2]

        // Step 4: 打包为字节 (每 8 个 bit → 1 byte)
        let bits = finalCoeffs.map { $0 >= median ? 1 : 0 }
        var hashBytes = [UInt8]()
        for i in stride(from: 0, to: bits.count, by: 8) {
            var byte: UInt8 = 0
            for j in 0..<8 where i + j < bits.count {
                if bits[i + j] == 1 { byte |= UInt8(1 << (7 - j)) }
            }
            hashBytes.append(byte)
        }

        return VideoPerceptualHash(videoID: id, hashBits: hashBytes)
    }

    // MARK: - 1D-DCT Type-II

    /// 标准 DCT Type-II: X[k] = Σ x[n] · cos(π(2n+1)k / 2N)
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

    /// 2D-DCT = 先对每行做 1D-DCT, 再对每列做 1D-DCT
    static func dct2D(_ input: [Double], rows: Int, cols: Int) -> [Double] {
        guard input.count == rows * cols else { return [] }

        // Step 1: 对每行做 1D-DCT
        var intermediate = [Double]()
        intermediate.reserveCapacity(rows * cols)
        for row in 0..<rows {
            let rowSlice = Array(input[row * cols..<(row + 1) * cols])
            let dctRow = dct1D(rowSlice)
            intermediate.append(contentsOf: dctRow)
        }

        // Step 2: 对每列做 1D-DCT
        var output = [Double]()
        output.reserveCapacity(rows * cols)
        for col in 0..<cols {
            let column = (0..<rows).map { intermediate[$0 * cols + col] }
            let dctCol = dct1D(column)
            output.append(contentsOf: dctCol)
        }

        // 输出是列优先 (column-major), 转为行优先
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
