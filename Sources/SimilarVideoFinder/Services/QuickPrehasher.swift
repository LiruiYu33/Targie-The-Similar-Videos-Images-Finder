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

// MARK: - Quick Prehash (Low-Cost Fingerprint from Metadata and Thumbnails)

/// Extremely lightweight signature used before perceptual hashing to filter obviously dissimilar video pairs.
/// It only uses existing `MediaItem` data (thumbnail and metadata), so it does not read the video file again.
struct QuickPrehash: Hashable, Sendable {
    let videoID: UUID
    let durationBucket: Int     // Duration bucket (5% step).
    let sizeBucket: Int         // Size bucket (log-scaled).
    let aspectBucket: Int       // Aspect-ratio bucket (3% step).
    let thumbnailMean: UInt8    // Grayscale thumbnail mean (0-255).
    let thumbnailVariance: UInt16  // Approximate grayscale thumbnail variance (0-65535).

    /// Checks whether two prehashes are within tolerance and therefore potentially similar.
    /// The tolerance is intentionally loose: it only filters impossible matches and avoids dropping true matches.
    func isCompatible(with other: QuickPrehash) -> Bool {
        // Duration tolerance: +/-2 buckets (about 10%).
        guard abs(durationBucket - other.durationBucket) <= 2 else { return false }
        // Size tolerance: +/-3 buckets in log space, roughly up to a 2x size difference.
        guard abs(sizeBucket - other.sizeBucket) <= 3 else { return false }
        // Aspect-ratio tolerance: +/-2 buckets (about 6%).
        guard abs(aspectBucket - other.aspectBucket) <= 2 else { return false }
        // Thumbnail mean tolerance: +/-40, allowing encoding differences.
        guard abs(Int(thumbnailMean) - Int(other.thumbnailMean)) <= 40 else { return false }
        return true
    }
}

// MARK: - QuickPrehasher

enum QuickPrehasher {

    /// Computes a `QuickPrehash` from a `MediaItem` synchronously using only in-memory data.
    static func prehash(for video: MediaItem) -> QuickPrehash {
        let (mean, variance) = thumbnailStats(video.thumbnailData)
        return QuickPrehash(
            videoID: video.id,
            durationBucket: durationBucket(video.duration ?? 0),
            sizeBucket: sizeBucket(video.fileSize),
            aspectBucket: aspectBucket(width: video.width, height: video.height),
            thumbnailMean: mean,
            thumbnailVariance: variance
        )
    }

    // MARK: - Bucket Calculations

    /// Buckets duration by 5% geometric steps: bucket = round(20 * log(duration)).
    /// 0s → 0, 1s → ~0, 60s → ~82, 600s → ~128
    static func durationBucket(_ duration: Double) -> Int {
        guard duration > 0 else { return 0 }
        return Int((20.0 * log(duration + 1.0)).rounded())
    }

    /// Buckets file size with log scaling: bucket = round(10 * log10(size)).
    /// 1 KB → 30, 1 MB → 60, 1 GB → 90
    static func sizeBucket(_ size: Int64) -> Int {
        guard size > 0 else { return 0 }
        return Int((10.0 * log10(Double(size))).rounded())
    }

    /// Buckets aspect ratio by 3% steps: bucket = round(33 * aspect).
    /// 1.0 → 33, 16/9 ≈ 1.778 → 59, 4/3 ≈ 1.333 → 44
    static func aspectBucket(width: Int, height: Int) -> Int {
        guard width > 0, height > 0 else { return 0 }
        let aspect = Double(width) / Double(height)
        return Int((33.0 * aspect).rounded())
    }

    // MARK: - Thumbnail Stats

    /// Decodes JPEG thumbnail data and computes grayscale mean and variance.
    /// Returns the neutral value (128, 0) when the thumbnail is missing or cannot be decoded.
    static func thumbnailStats(_ data: Data?) -> (mean: UInt8, variance: UInt16) {
        guard let data, let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return (128, 0)
        }
        return computeStats(cgImage: cgImage)
    }

    /// Computes grayscale mean and variance for a CGImage, downsampling to a fixed 16x16 grid for speed.
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
