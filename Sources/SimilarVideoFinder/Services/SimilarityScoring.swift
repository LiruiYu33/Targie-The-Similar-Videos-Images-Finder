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

import Foundation

enum FilenameNormalizer {
    static func normalize(_ filename: String) -> String {
        var value = (filename as NSString).deletingPathExtension.lowercased()
        let patterns = [
            #"(copy|副本|export|导出)[\s_\-]*\d*"#,
            #"[\s_\-]+\d+$"#,
            #"[\s_\-\(\)\[\]\.]+"#
        ]
        for pattern in patterns {
            value = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SimilarityScore: Equatable, Sendable {
    let score: Double
    let evidence: Set<SimilarityEvidence>
}

enum SimilarityScorer {
    /// 评分整合三层证据:
    /// - SHA-256 字节级一致 → 1.0
    /// - 感知哈希 (DCT-3D Hamming 距离): 主信号, 0..1
    /// - Vision FeaturePrint (帧级 CNN 特征): 精确认证层 (可选)
    /// - 元数据 (时长/尺寸/大小/文件名): 辅助证据
    ///
    /// `perceptualSimilarity` 取值 [0, 1]:
    ///   - 1.0 = Hamming 距离 0 (完全相同的指纹)
    ///   - 0.0 = 全比特不同
    ///   - 由 BK-Tree 候选筛选后, 通常 >= 1 - 24/64 ≈ 0.625
    ///
    /// 评分公式:
    ///   - 三层都有时:   score = 0.45·perc + 0.35·frames + 0.20·metadata
    ///   - 仅哈希+元数据: score = 0.65·perc + 0.35·metadata, 上限 0.95 (无 Vision 不能确信完全一致)
    ///   - 仅元数据:     score = 0.78·metadata, 上限 0.78 (不能高过视觉信号)
    static func score(
        _ first: MediaItem,
        _ second: MediaItem,
        hashesMatch: Bool,
        perceptualSimilarity: Double? = nil,
        frameSimilarity: Double?
    ) -> SimilarityScore {
        if hashesMatch {
            return SimilarityScore(score: 1, evidence: [.identicalContentHash])
        }

        let duration = optionalRatioScore(first.duration, second.duration)
        let size = ratioScore(Double(first.fileSize), Double(second.fileSize))
        let dimensions = dimensionScore(first, second)
        let name = nameScore(first.filename, second.filename)
        var evidence = Set<SimilarityEvidence>()
        if let duration, duration >= 0.9 { evidence.insert(.similarDuration) }
        if size >= 0.85 { evidence.insert(.similarSize) }
        if dimensions >= 0.95 { evidence.insert(.similarDimensions) }
        if name >= 0.85 { evidence.insert(.similarName) }

        let metadata: Double
        if let duration {
            metadata = duration * 0.30 + dimensions * 0.20 + size * 0.20 + name * 0.30
        } else {
            // Images have no duration. Re-normalize the remaining metadata weights
            // instead of treating a missing video-only value as a zero score.
            metadata = dimensions * (2.0 / 7.0) + size * (2.0 / 7.0) + name * (3.0 / 7.0)
        }

        let perc = perceptualSimilarity.map { min(max($0, 0), 1) }
        if let perc, perc >= 0.78 { evidence.insert(.similarPerceptualHash) }

        // 三种组合分支
        if let perc, let frame = frameSimilarity {
            let frames = min(max(frame, 0), 1)
            if frames >= 0.82 { evidence.insert(.similarFrames) }
            let combined = perc * 0.45 + frames * 0.35 + metadata * 0.20
            return SimilarityScore(score: min(combined, 1), evidence: evidence)
        }

        if let perc {
            let combined = perc * 0.65 + metadata * 0.35
            return SimilarityScore(score: min(combined, 0.95), evidence: evidence)
        }

        if let frame = frameSimilarity {
            let frames = min(max(frame, 0), 1)
            if frames >= 0.82 { evidence.insert(.similarFrames) }
            return SimilarityScore(score: min(frames * 0.70 + metadata * 0.30, 1), evidence: evidence)
        }

        return SimilarityScore(score: min(metadata * 0.78, 0.78), evidence: evidence)
    }

    private static func ratioScore(_ lhs: Double, _ rhs: Double) -> Double {
        guard lhs > 0, rhs > 0 else { return 0 }
        return min(lhs, rhs) / max(lhs, rhs)
    }

    private static func optionalRatioScore(_ lhs: Double?, _ rhs: Double?) -> Double? {
        guard let lhs, let rhs else { return nil }
        return ratioScore(lhs, rhs)
    }

    private static func dimensionScore(_ first: MediaItem, _ second: MediaItem) -> Double {
        guard first.width > 0, first.height > 0, second.width > 0, second.height > 0 else { return 0 }
        let firstRatio = Double(first.width) / Double(first.height)
        let secondRatio = Double(second.width) / Double(second.height)
        let aspect = min(firstRatio, secondRatio) / max(firstRatio, secondRatio)
        let pixelsA = Double(first.width * first.height)
        let pixelsB = Double(second.width * second.height)
        return aspect * 0.7 + (min(pixelsA, pixelsB) / max(pixelsA, pixelsB)) * 0.3
    }

    private static func nameScore(_ lhs: String, _ rhs: String) -> Double {
        let a = FilenameNormalizer.normalize(lhs)
        let b = FilenameNormalizer.normalize(rhs)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1 }
        if a.contains(b) || b.contains(a) { return 0.85 }
        return 0
    }
}
