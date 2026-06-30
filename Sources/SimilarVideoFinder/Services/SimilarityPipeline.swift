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

import CryptoKit
import Foundation

struct PipelineResult: Sendable {
    let videos: [MediaItem]
    let relations: [SimilarityRelation]
    let groups: [SimilarityGroup]
}

protocol SimilarityProcessing: Sendable {
    func process(
        videos: [MediaItem],
        threshold: Double,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> PipelineResult
}

enum ScanRelationSignatureBuilder {
    static func signature(
        items: [MediaItem],
        hashes: [UUID: Data],
        algorithmVersion: String
    ) -> String {
        var hasher = SHA256()
        func update(_ string: String) {
            hasher.update(data: Data(string.utf8))
            hasher.update(data: Data([0]))
        }

        update(algorithmVersion)
        for item in items.sorted(by: { $0.url.path < $1.url.path }) {
            guard let hash = hashes[item.id] else { continue }
            update(item.url.path)
            update(String(item.fileSize))
            hasher.update(data: hash)
            hasher.update(data: Data([0xff]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
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
    private let usesFrameVerification: Bool
    /// 感知哈希之间被视为"潜在相似"的最大 Hamming 距离 (64-bit 哈希中允许多达 24 bits 不同)
    static let perceptualMaxDistance = 24
    fileprivate static let relationStorageFloor = 0.60

    static func pairRelationAlgorithmVersion(usesFrameVerification: Bool) -> String {
        usesFrameVerification ? "video-pair-relation-v1-frame" : "video-pair-relation-v1-perceptual"
    }

    static func scanRelationSignature(
        items: [MediaItem],
        hashes: [UUID: Data],
        algorithmVersion: String
    ) -> String {
        ScanRelationSignatureBuilder.signature(
            items: items,
            hashes: hashes,
            algorithmVersion: algorithmVersion
        )
    }

    init(
        cache: (any HashCaching)? = nil,
        extractor: any FrameFeatureExtracting = FrameFeatureExtractor(),
        usesFrameVerification: Bool = false
    ) {
        self.cache = cache
        self.extractor = extractor
        self.usesFrameVerification = usesFrameVerification
    }

    static func hashConcurrencyLimit(processorCount: Int) -> Int {
        min(4, max(2, processorCount))
    }

    static func comparisonConcurrencyLimit(processorCount: Int) -> Int {
        min(6, max(2, processorCount / 2))
    }

    func process(
        videos: [MediaItem],
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

        let pairRelationAlgorithmVersion = Self.pairRelationAlgorithmVersion(usesFrameVerification: usesFrameVerification)
        let hashDataByID = perceptualHashes.mapValues { Data($0.hashBits) }
        let indexSignature = Self.scanRelationSignature(
            items: videosNeedingHash,
            hashes: hashDataByID,
            algorithmVersion: pairRelationAlgorithmVersion
        )
        if let cachedIndex = await cache?.lookupScanRelationIndex(
            signature: indexSignature,
            mediaKind: .video,
            algorithmVersion: pairRelationAlgorithmVersion
        ) {
            let itemsByPath = Dictionary(uniqueKeysWithValues: videos.map { ($0.url.path, $0) })
            let cachedRelations = cachedIndex.relations.compactMap { cached -> SimilarityRelation? in
                guard let first = itemsByPath[cached.firstPath],
                      let second = itemsByPath[cached.secondPath]
                else { return nil }
                return SimilarityRelation(
                    firstID: first.id,
                    secondID: second.id,
                    score: cached.score,
                    evidence: cached.evidence
                )
            }
            await progress(ScanProgress(
                stage: .comparing,
                fraction: 1,
                currentFile: "",
                discoveredCount: videos.count,
                cacheHits: cachedIndex.candidateCount,
                cacheTotal: cachedIndex.candidateCount,
                cacheKind: .relation,
                comparisonPhase: .checkingPairCache
            ))
            return PipelineResult(
                videos: videos,
                relations: cachedRelations,
                groups: SimilarityGrouper.groups(items: videos, relations: cachedRelations, threshold: threshold)
            )
        }

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
            discoveredCount: videos.count,
            comparisonPhase: .findingCandidates,
            comparisonCompleted: 0,
            comparisonTotal: max(videosNeedingHash.count, 1)
        ))

        var relations: [SimilarityRelation] = []
        var fileHashes: [UUID: String] = [:]
        var processedPairs = Set<PairKey>()
        let frameFeatureCache = FrameFeatureCache(extractor: extractor, persistentCache: cache)
        var pairCacheHits = 0
        var pairCacheTotal = 0

        // Exact duplicates must not depend on video frame extraction succeeding.
        // This also keeps corrupt or partially supported files from aborting the scan.
        var exactCandidates: [(first: MediaItem, second: MediaItem, key: PairKey, relationKey: PairRelationCacheKey?)] = []
        for (first, second) in prehashCandidates where first.fileSize > 0 && first.fileSize == second.fileSize {
            let key = PairKey(first.id, second.id)
            guard !processedPairs.contains(key) else { continue }
            exactCandidates.append((
                first: first,
                second: second,
                key: key,
                relationKey: PairRelationCacheKey(first: first, second: second, algorithmVersion: pairRelationAlgorithmVersion)
            ))
        }
        let exactRelationKeys = exactCandidates.compactMap(\.relationKey)
        let exactRelationCache: [PairRelationCacheKey: PairRelationCacheEntry] = cache == nil || exactRelationKeys.isEmpty
            ? [:]
            : await cache?.lookupPairRelations(keys: exactRelationKeys) ?? [:]
        for candidate in exactCandidates {
            try Task.checkCancellation()
            if let relationKey = candidate.relationKey {
                pairCacheTotal += 1
                if let cached = exactRelationCache[relationKey] {
                    pairCacheHits += 1
                    processedPairs.insert(candidate.key)
                    if let relation = cached.relation(firstID: candidate.first.id, secondID: candidate.second.id) {
                        relations.append(relation)
                    }
                    continue
                }
            }
            let firstHash = try? await fileSHA256(for: candidate.first, memoizedHashes: &fileHashes)
            let secondHash = try? await fileSHA256(for: candidate.second, memoizedHashes: &fileHashes)
            guard let firstHash, firstHash == secondHash else { continue }
            processedPairs.insert(candidate.key)
            let relation = SimilarityRelation(
                firstID: candidate.first.id,
                secondID: candidate.second.id,
                score: 1,
                evidence: [.identicalContentHash]
            )
            relations.append(relation)
            await cache?.upsertPairRelation(first: candidate.first, second: candidate.second, algorithmVersion: pairRelationAlgorithmVersion, relation: relation)
        }

        // 对每个有感知哈希的视频, 用 BK-Tree 搜索它的近邻
        let videosByID = Dictionary(uniqueKeysWithValues: videos.map { ($0.id, $0) })
        let queryVideos = videosNeedingHash
        let totalQueries = max(queryVideos.count, 1)

        var pendingComparisonCandidates: [(candidate: VideoComparisonCandidate, relationKey: PairRelationCacheKey?)] = []
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
                pendingComparisonCandidates.append((
                    candidate: VideoComparisonCandidate(
                        first: video,
                        second: other,
                        firstHash: queryHash,
                        secondHash: neighbor.item,
                        algorithmVersion: pairRelationAlgorithmVersion
                    ),
                    relationKey: PairRelationCacheKey(first: video, second: other, algorithmVersion: pairRelationAlgorithmVersion)
                ))
            }

            await progress(ScanProgress(
                stage: .comparing,
                fraction: Double(qIndex + 1) / Double(totalQueries) * 0.2,
                currentFile: video.filename,
                discoveredCount: videos.count,
                cacheHits: 0,
                cacheTotal: 0,
                cacheKind: nil,
                comparisonPhase: .findingCandidates,
                comparisonCompleted: qIndex + 1,
                comparisonTotal: totalQueries
            ))
        }

        let relationKeys = pendingComparisonCandidates.compactMap(\.relationKey)
        let relationCache: [PairRelationCacheKey: PairRelationCacheEntry] = cache == nil || relationKeys.isEmpty
            ? [:]
            : await cache?.lookupPairRelations(keys: relationKeys) ?? [:]
        var misses: [VideoComparisonCandidate] = []
        for pending in pendingComparisonCandidates {
            if let relationKey = pending.relationKey {
                pairCacheTotal += 1
                if let cached = relationCache[relationKey] {
                    pairCacheHits += 1
                    if let relation = cached.relation(
                        firstID: pending.candidate.first.id,
                        secondID: pending.candidate.second.id
                    ) {
                        relations.append(relation)
                    }
                    continue
                }
            }
            misses.append(pending.candidate)
        }

        let cacheProgressFile = pendingComparisonCandidates.first?.candidate.first.filename
            ?? exactCandidates.first?.first.filename
            ?? ""
        if misses.isEmpty {
            await progress(ScanProgress(
                stage: .comparing,
                fraction: 1,
                currentFile: cacheProgressFile,
                discoveredCount: videos.count,
                cacheHits: pairCacheHits,
                cacheTotal: pairCacheTotal,
                cacheKind: cache != nil && pairCacheTotal > 0 ? .relation : nil,
                comparisonPhase: .checkingPairCache
            ))
        } else {
            await progress(ScanProgress(
                stage: .comparing,
                fraction: 0.2,
                currentFile: cacheProgressFile,
                discoveredCount: videos.count,
                cacheHits: pairCacheHits,
                cacheTotal: pairCacheTotal,
                cacheKind: cache != nil && pairCacheTotal > 0 ? .relation : nil,
                comparisonPhase: .checkingPairCache
            ))

            let comparisonLimit = Self.comparisonConcurrencyLimit(
                processorCount: ProcessInfo.processInfo.activeProcessorCount
            )
            var completedMisses = 0
            try await withThrowingTaskGroup(of: (String, SimilarityRelation?).self) { group in
                var iterator = misses.makeIterator()
                for _ in 0..<min(comparisonLimit, misses.count) {
                    guard let next = iterator.next() else { break }
                    group.addTask {
                        let relation = try await compareVideoCandidate(
                            next,
                            cache: cache,
                            frameFeatureCache: frameFeatureCache,
                            usesFrameVerification: usesFrameVerification
                        )
                        return (next.first.filename, relation)
                    }
                }

                while let (currentFile, relation) = try await group.next() {
                    completedMisses += 1
                    if let relation { relations.append(relation) }
                    await progress(ScanProgress(
                        stage: .comparing,
                        fraction: 0.2 + 0.8 * Double(completedMisses) / Double(misses.count),
                        currentFile: currentFile,
                        discoveredCount: videos.count,
                        cacheHits: 0,
                        cacheTotal: 0,
                        cacheKind: nil,
                        comparisonPhase: .comparingUncached,
                        comparisonCompleted: completedMisses,
                        comparisonTotal: misses.count
                    ))
                    if let next = iterator.next() {
                        group.addTask {
                            let relation = try await compareVideoCandidate(
                                next,
                                cache: cache,
                                frameFeatureCache: frameFeatureCache,
                                usesFrameVerification: usesFrameVerification
                            )
                            return (next.first.filename, relation)
                        }
                    }
                }
            }
        }

        let scanIndexRelations = relations.compactMap { relation -> CachedScanRelation? in
            guard let first = videosByID[relation.firstID],
                  let second = videosByID[relation.secondID]
            else { return nil }
            let ordered = first.url.path < second.url.path ? (first, second) : (second, first)
            return CachedScanRelation(
                firstPath: ordered.0.url.path,
                secondPath: ordered.1.url.path,
                score: relation.score,
                evidence: relation.evidence
            )
        }
        await cache?.upsertScanRelationIndex(
            signature: indexSignature,
            mediaKind: .video,
            algorithmVersion: pairRelationAlgorithmVersion,
            fileCount: videosNeedingHash.count,
            candidateCount: pairCacheTotal,
            relations: scanIndexRelations
        )

        return PipelineResult(
            videos: videos,
            relations: relations,
            groups: SimilarityGrouper.groups(items: videos, relations: relations, threshold: threshold)
        )
    }

    /// 从候选对中提取所有需要计算感知哈希的视频 (去重)。
    private func uniqueVideos(in pairs: [(MediaItem, MediaItem)]) -> [MediaItem] {
        var seen = Set<UUID>()
        var result: [MediaItem] = []
        for (first, second) in pairs {
            if seen.insert(first.id).inserted { result.append(first) }
            if seen.insert(second.id).inserted { result.append(second) }
        }
        return result
    }

    // MARK: - Phase B helpers

    /// 并行计算多个视频的 PerceptualHash, 进度上报。命中缓存的视频跳过哈希计算。
    private func computePerceptualHashesInParallel(
        videos: [MediaItem],
        prehashes: [UUID: QuickPrehash],
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> [UUID: VideoPerceptualHash] {
        let total = max(videos.count, 1)
        let cacheTotal = videos.count
        let counter = ProgressCounter()

        // ---- 阶段 1: 缓存命中过滤 ----
        var cached: [UUID: VideoPerceptualHash] = [:]
        var needsHashing: [MediaItem] = []
        if let cache {
            let keysByID = Dictionary(uniqueKeysWithValues: videos.map {
                (
                    $0.id,
                    MediaHashCacheKey(
                        filePath: $0.url.path,
                        fileSize: $0.fileSize,
                        modifiedAt: $0.modifiedAt,
                        mediaKind: .video,
                        algorithmVersion: "video-dct3d-v1"
                    )
                )
            })
            let batch = await cache.lookupHashes(keys: Array(keysByID.values))
            for video in videos {
                if let key = keysByID[video.id], let record = batch[key] {
                    cached[video.id] = record.toPerceptualHash(videoID: video.id)
                } else if let record = await cache.lookup(
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
        if cache != nil, cacheTotal > 0 {
            await progress(ScanProgress(
                stage: .hashing,
                fraction: Double(cached.count) / Double(total),
                currentFile: "",
                discoveredCount: total,
                cacheHits: cached.count,
                cacheTotal: cacheTotal,
                cacheKind: .fingerprint
            ))
        }

        // ---- 阶段 2: 并行计算未命中的哈希 ----
        let concurrencyCap = Self.hashConcurrencyLimit(
            processorCount: ProcessInfo.processInfo.activeProcessorCount
        )

        let computed = try await withThrowingTaskGroup(of: (UUID, VideoPerceptualHash?).self) { group in
            var iterator = needsHashing.makeIterator()
            var inFlight = 0

            while inFlight < concurrencyCap, let next = iterator.next() {
                group.addTask {
                    let hash = try await PerceptualHasher.hash(for: next.url, id: next.id)
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
                    discoveredCount: total,
                    cacheHits: cached.count,
                    cacheTotal: cacheTotal,
                    cacheKind: cache != nil && cacheTotal > 0 ? .fingerprint : nil
                ))

                if let next = iterator.next() {
                    group.addTask {
                        let hash = try await PerceptualHasher.hash(for: next.url, id: next.id)
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

    private func fileSHA256(for video: MediaItem, memoizedHashes: inout [UUID: String]) async throws -> String {
        if let cached = memoizedHashes[video.id] { return cached }
        let value = try await FileHasher.sha256(of: video.url, mediaKind: .video, cache: self.cache)
        memoizedHashes[video.id] = value
        return value
    }
}

private func compareVideoCandidate(
    _ candidate: VideoComparisonCandidate,
    cache: (any HashCaching)?,
    frameFeatureCache: FrameFeatureCache,
    usesFrameVerification: Bool
) async throws -> SimilarityRelation? {
    try Task.checkCancellation()
    let percSimilarity = candidate.firstHash.similarity(to: candidate.secondHash)
    let sameSize = candidate.first.fileSize > 0 && candidate.first.fileSize == candidate.second.fileSize
    let perceptualHashesMatch = candidate.firstHash.hammingDistance(to: candidate.secondHash) == 0
    var hashMatch = false
    if sameSize && perceptualHashesMatch {
        let firstHash = try? await FileHasher.sha256(of: candidate.first.url, mediaKind: .video, cache: cache)
        let secondHash = try? await FileHasher.sha256(of: candidate.second.url, mediaKind: .video, cache: cache)
        hashMatch = firstHash != nil && firstHash == secondHash
    }

    let frameScore: Double?
    if !usesFrameVerification || hashMatch || percSimilarity >= 0.92 {
        frameScore = nil
    } else {
        frameScore = try? await frameFeatureCache.similarity(
            between: candidate.first.url,
            and: candidate.second.url
        )
    }

    let score = SimilarityScorer.score(
        candidate.first,
        candidate.second,
        hashesMatch: hashMatch,
        perceptualSimilarity: percSimilarity,
        frameSimilarity: frameScore
    )

    let relation: SimilarityRelation?
    if score.score >= SimilarityPipeline.relationStorageFloor {
        relation = SimilarityRelation(
            firstID: candidate.first.id,
            secondID: candidate.second.id,
            score: score.score,
            evidence: score.evidence
        )
    } else {
        relation = nil
    }
    await cache?.upsertPairRelation(
        first: candidate.first,
        second: candidate.second,
        algorithmVersion: candidate.algorithmVersion,
        relation: relation
    )
    return relation
}

private struct VideoComparisonCandidate: Sendable {
    let first: MediaItem
    let second: MediaItem
    let firstHash: VideoPerceptualHash
    let secondHash: VideoPerceptualHash
    let algorithmVersion: String
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
