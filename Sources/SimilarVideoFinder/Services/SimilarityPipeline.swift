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

struct PipelineResult: Sendable {
    let videos: [VideoItem]
    let relations: [SimilarityRelation]
    let groups: [SimilarityGroup]
}

protocol SimilarityProcessing: Sendable {
    func process(
        videos: [VideoItem],
        threshold: Double,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> PipelineResult
}

/// 三阶段相似度流水线:
/// 1. **Prehash 阶段**: 基于已有元数据/缩略图同步计算 QuickPrehash, 按桶分组得到候选对
/// 2. **Hash 阶段**: 并行计算所有视频的 DCT-3D 感知哈希, 装入 BK-Tree
/// 3. **比较阶段**: 对 prehash 候选对使用 BK-Tree 搜索 + Vision 精确认证
///
/// 关键性能优化:
/// - QuickPrehash 零成本预筛, 避免对所有 O(n²) 对做昂贵操作
/// - PerceptualHash 并行计算 (TaskGroup), 充分利用多核
/// - BK-Tree 搜索 O(n·log n), 替代 O(n²) 全比较
/// - Vision FeaturePrint 仅作精确认证层, 调用次数大幅减少
struct SimilarityPipeline: SimilarityProcessing {
    private let extractor: any FrameFeatureExtracting
    private let cache: (any HashCaching)?
    /// 感知哈希之间被视为"潜在相似"的最大 Hamming 距离 (64-bit 哈希中允许多达 24 bits 不同)
    static let perceptualMaxDistance = 24

    init(
        cache: (any HashCaching)? = nil,
        extractor: any FrameFeatureExtracting = FrameFeatureExtractor()
    ) {
        self.cache = cache
        self.extractor = extractor
    }

    func process(
        videos: [VideoItem],
        threshold: Double,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> PipelineResult {
        // ---- Phase A: QuickPrehash (同步, 零成本) ----
        await progress(ScanProgress(
            stage: .prehashing,
            fraction: 0,
            currentFile: "",
            discoveredCount: videos.count
        ))

        let prehashes: [UUID: QuickPrehash] = videos.reduce(into: [:]) { acc, video in
            acc[video.id] = QuickPrehasher.prehash(for: video)
        }

        // 通过 QuickPrehash 筛选候选对
        let prehashCandidates = PrehashCandidateFinder.find(
            videos: videos,
            prehashes: prehashes
        ).pairs

        await progress(ScanProgress(
            stage: .prehashing,
            fraction: 1,
            currentFile: "",
            discoveredCount: videos.count
        ))

        try Task.checkCancellation()

        // ---- Phase B: 感知哈希 (并行) ----
        // 只对至少出现在一个候选对中的视频计算感知哈希
        let videosNeedingHash = uniqueVideos(in: prehashCandidates)

        await progress(ScanProgress(
            stage: .hashing,
            fraction: 0,
            currentFile: "",
            discoveredCount: videos.count
        ))

        let perceptualHashes = try await computePerceptualHashesInParallel(
            videos: videosNeedingHash,
            prehashes: prehashes,
            progress: progress
        )

        try Task.checkCancellation()

        // 构建 BK-Tree 用于近邻搜索
        var bkTree = BKTree<VideoPerceptualHash>()
        for hash in perceptualHashes.values {
            bkTree.insert(hash, distance: { $0.hammingDistance(to: $1) })
        }

        // ---- Phase C: 候选对比较 (BK-Tree + Vision) ----
        await progress(ScanProgress(
            stage: .comparing,
            fraction: 0,
            currentFile: "",
            discoveredCount: videos.count
        ))

        var relations: [SimilarityRelation] = []
        var fileHashes: [UUID: String] = [:]
        var processedPairs = Set<PairKey>()
        let frameFeatureCache = FrameFeatureCache(extractor: extractor)

        // 对每个有感知哈希的视频, 用 BK-Tree 搜索它的近邻
        let videosByID = Dictionary(uniqueKeysWithValues: videos.map { ($0.id, $0) })
        let queryVideos = videosNeedingHash
        let totalQueries = max(queryVideos.count, 1)

        for (qIndex, video) in queryVideos.enumerated() {
            try Task.checkCancellation()

            guard let queryHash = perceptualHashes[video.id] else { continue }
            let neighbors = bkTree.search(
                queryHash,
                maxDistance: Self.perceptualMaxDistance,
                distance: { $0.hammingDistance(to: $1) }
            )

            for neighbor in neighbors where neighbor.item.videoID != video.id {
                let key = PairKey(video.id, neighbor.item.videoID)
                guard !processedPairs.contains(key) else { continue }
                processedPairs.insert(key)

                guard let other = videosByID[neighbor.item.videoID] else { continue }

                // 感知哈希相似度 (主信号)
                let percSimilarity = queryHash.similarity(to: neighbor.item)

                // 同尺寸文件先做 SHA-256 (检测 byte-identical)
                let sameSize = video.fileSize > 0 && video.fileSize == other.fileSize
                var hashMatch = false
                if sameSize {
                    let firstHash = try await fileSHA256(for: video, cache: &fileHashes)
                    let secondHash = try await fileSHA256(for: other, cache: &fileHashes)
                    hashMatch = firstHash == secondHash
                }

                // Vision 自适应跳过:
                // - 文件 byte-identical → 无需 Vision
                // - 感知哈希极强 (>= 0.92, Hamming ≤ 5) → 已足够确信, 跳过 Vision 加速
                // - 否则用 Vision FeaturePrint 做精确认证
                let frameScore: Double?
                if hashMatch || percSimilarity >= 0.92 {
                    frameScore = nil
                } else {
                    frameScore = try? await frameFeatureCache.similarity(
                        between: video.url,
                        and: other.url
                    )
                }

                let score = SimilarityScorer.score(
                    video,
                    other,
                    hashesMatch: hashMatch,
                    perceptualSimilarity: percSimilarity,
                    frameSimilarity: frameScore
                )

                if score.score >= min(threshold, 0.72) {
                    relations.append(SimilarityRelation(
                        firstID: video.id,
                        secondID: other.id,
                        score: score.score,
                        evidence: score.evidence
                    ))
                }
            }

            await progress(ScanProgress(
                stage: .comparing,
                fraction: Double(qIndex + 1) / Double(totalQueries),
                currentFile: video.filename,
                discoveredCount: videos.count
            ))
        }

        return PipelineResult(
            videos: videos,
            relations: relations,
            groups: SimilarityGrouper.groups(items: videos, relations: relations, threshold: threshold)
        )
    }

    /// 从候选对中提取所有需要计算感知哈希的视频 (去重)。
    private func uniqueVideos(in pairs: [(VideoItem, VideoItem)]) -> [VideoItem] {
        var seen = Set<UUID>()
        var result: [VideoItem] = []
        for (first, second) in pairs {
            if seen.insert(first.id).inserted { result.append(first) }
            if seen.insert(second.id).inserted { result.append(second) }
        }
        return result
    }

    // MARK: - Phase B helpers

    /// 并行计算多个视频的 PerceptualHash, 进度上报。命中缓存的视频跳过哈希计算。
    private func computePerceptualHashesInParallel(
        videos: [VideoItem],
        prehashes: [UUID: QuickPrehash],
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> [UUID: VideoPerceptualHash] {
        let total = max(videos.count, 1)
        let counter = ProgressCounter()

        // ---- 阶段 1: 缓存命中过滤 ----
        var cached: [UUID: VideoPerceptualHash] = [:]
        var needsHashing: [VideoItem] = []
        if let cache {
            for video in videos {
                if let record = await cache.lookup(
                    filePath: video.url.path,
                    fileSize: video.fileSize,
                    modifiedAt: video.modifiedAt
                ) {
                    cached[video.id] = record.toPerceptualHash(videoID: video.id)
                } else {
                    needsHashing.append(video)
                }
            }
        } else {
            needsHashing = videos
        }

        // 缓存命中也要计入进度
        for _ in cached.indices {
            _ = await counter.increment()
        }

        // ---- 阶段 2: 并行计算未命中的哈希 ----
        let concurrencyCap = max(2, ProcessInfo.processInfo.activeProcessorCount)

        let computed = try await withThrowingTaskGroup(of: (UUID, VideoPerceptualHash?).self) { group in
            var iterator = needsHashing.makeIterator()
            var inFlight = 0

            while inFlight < concurrencyCap, let next = iterator.next() {
                group.addTask {
                    let hash = try? await PerceptualHasher.hash(for: next.url, id: next.id)
                    return (next.id, hash)
                }
                inFlight += 1
            }

            var results: [UUID: VideoPerceptualHash] = [:]
            while let (id, hash) = try await group.next() {
                if let hash { results[id] = hash }

                let done = await counter.increment()
                let video = needsHashing.first { $0.id == id }
                await progress(ScanProgress(
                    stage: .hashing,
                    fraction: Double(done) / Double(total),
                    currentFile: video?.filename ?? "",
                    discoveredCount: total
                ))

                if let next = iterator.next() {
                    group.addTask {
                        let hash = try? await PerceptualHasher.hash(for: next.url, id: next.id)
                        return (next.id, hash)
                    }
                }
            }

            return results
        }

        // ---- 阶段 3: 写回缓存 ----
        if let cache {
            for video in needsHashing {
                guard let hash = computed[video.id], let prehash = prehashes[video.id] else { continue }
                let record = CacheRecord.make(video: video, perceptualHash: hash, quickPrehash: prehash)
                await cache.upsert(record)
            }
        }

        // 合并缓存命中与新计算结果
        var all = cached
        for (id, hash) in computed { all[id] = hash }
        return all
    }

    // MARK: - Phase C helpers

    private func fileSHA256(for video: VideoItem, cache: inout [UUID: String]) async throws -> String {
        if let cached = cache[video.id] { return cached }
        let value = try await FileHasher.sha256(of: video.url)
        cache[video.id] = value
        return value
    }
}

// MARK: - PairKey

/// 无序对的唯一键 (a, b) == (b, a)
private struct PairKey: Hashable {
    let lo: UUID
    let hi: UUID

    init(_ a: UUID, _ b: UUID) {
        if a.uuidString < b.uuidString {
            self.lo = a
            self.hi = b
        } else {
            self.lo = b
            self.hi = a
        }
    }
}

// MARK: - ProgressCounter

/// 用于跨 TaskGroup 任务的并发安全进度计数。
private actor ProgressCounter {
    private var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}
