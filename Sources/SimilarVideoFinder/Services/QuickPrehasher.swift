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

import AppKit
import Foundation

// MARK: - Quick Prehash (基于元数据 + 缩略图的零成本快速指纹)

/// 极轻量级签名：用于在感知哈希之前快速过滤大量明显不相似的视频对。
/// 完全基于已有的 VideoItem 数据（缩略图 + 元数据），无需再访问视频文件。
struct QuickPrehash: Hashable, Sendable {
    let videoID: UUID
    let durationBucket: Int     // 时长分桶 (5% 步长)
    let sizeBucket: Int         // 大小分桶 (按 log 缩放)
    let aspectBucket: Int       // 宽高比分桶 (3% 步长)
    let thumbnailMean: UInt8    // 缩略图灰度均值 (0-255)
    let thumbnailVariance: UInt16  // 缩略图灰度方差近似值 (0-65535)

    /// 检查两个 prehash 是否在容差范围内（即"潜在相似"）。
    /// 容差宽松设计 — 仅过滤明显不可能相似的对，绝不漏掉真匹配。
    func isCompatible(with other: QuickPrehash) -> Bool {
        // 时长容差 ±2 桶 (≈ 10%)
        guard abs(durationBucket - other.durationBucket) <= 2 else { return false }
        // 大小容差 ±3 桶 (log 域, 即文件大小可在 ~2x 范围内)
        guard abs(sizeBucket - other.sizeBucket) <= 3 else { return false }
        // 宽高比容差 ±2 桶 (≈ 6%)
        guard abs(aspectBucket - other.aspectBucket) <= 2 else { return false }
        // 缩略图均值容差 ±40 (允许编码差异)
        guard abs(Int(thumbnailMean) - Int(other.thumbnailMean)) <= 40 else { return false }
        return true
    }
}

// MARK: - QuickPrehasher

enum QuickPrehasher {

    /// 从 VideoItem 计算 QuickPrehash（同步，纯内存操作）。
    static func prehash(for video: VideoItem) -> QuickPrehash {
        let (mean, variance) = thumbnailStats(video.thumbnailData)
        return QuickPrehash(
            videoID: video.id,
            durationBucket: durationBucket(video.duration),
            sizeBucket: sizeBucket(video.fileSize),
            aspectBucket: aspectBucket(width: video.width, height: video.height),
            thumbnailMean: mean,
            thumbnailVariance: variance
        )
    }

    // MARK: - Bucket Calculations

    /// 时长按 5% 几何步长分桶: bucket = round(20 * log(duration))
    /// 0s → 0, 1s → ~0, 60s → ~82, 600s → ~128
    static func durationBucket(_ duration: Double) -> Int {
        guard duration > 0 else { return 0 }
        return Int((20.0 * log(duration + 1.0)).rounded())
    }

    /// 文件大小按 log 缩放分桶: bucket = round(10 * log10(size))
    /// 1 KB → 30, 1 MB → 60, 1 GB → 90
    static func sizeBucket(_ size: Int64) -> Int {
        guard size > 0 else { return 0 }
        return Int((10.0 * log10(Double(size))).rounded())
    }

    /// 宽高比按 3% 步长分桶: bucket = round(33 * aspect)
    /// 1.0 → 33, 16/9 ≈ 1.778 → 59, 4/3 ≈ 1.333 → 44
    static func aspectBucket(width: Int, height: Int) -> Int {
        guard width > 0, height > 0 else { return 0 }
        let aspect = Double(width) / Double(height)
        return Int((33.0 * aspect).rounded())
    }

    // MARK: - Thumbnail Stats

    /// 解码 JPEG 缩略图，计算灰度均值和方差。
    /// 缩略图缺失或解码失败时返回 (128, 0) 作为中性值。
    static func thumbnailStats(_ data: Data?) -> (mean: UInt8, variance: UInt16) {
        guard let data, let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return (128, 0)
        }
        return computeStats(cgImage: cgImage)
    }

    /// 在 CGImage 上计算灰度均值和方差。下采样到固定 16×16 以保证速度。
    static func computeStats(cgImage: CGImage) -> (mean: UInt8, variance: UInt16) {
        let pixels = PerceptualHasher.downsampleToGray(cgImage, size: 16)
        guard !pixels.isEmpty else { return (128, 0) }

        let count = Double(pixels.count)
        let mean = pixels.reduce(0.0, +) / count
        let varSum = pixels.reduce(0.0) { acc, p in acc + (p - mean) * (p - mean) }
        let variance = varSum / count

        let clampedMean = max(0, min(255, mean))
        let clampedVariance = max(0, min(65535, variance))
        return (UInt8(clampedMean), UInt16(clampedVariance))
    }
}
