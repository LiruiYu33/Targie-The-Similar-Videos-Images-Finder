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
}

protocol SimilarityProcessing: Sendable {
    func process(
        videos: [MediaItem],
        threshold: Double,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> PipelineResult

    func process(
        videos: [MediaItem],
        threshold: Double,
        scanIntensity: ScanIntensity,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> PipelineResult
}

extension SimilarityProcessing {
    func process(
        videos: [MediaItem],
        threshold: Double,
        scanIntensity: ScanIntensity,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> PipelineResult {
        try await process(videos: videos, threshold: threshold, progress: progress)
    }
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

        update("scan-relation-signature-v2")
        update(algorithmVersion)
        for item in items.sorted(by: { $0.url.path < $1.url.path }) {
            update(item.url.path)
            update(String(item.fileSize))
            update(FileCacheIdentity.modifiedAtSignature(item.modifiedAt))
            if let hash = hashes[item.id] {
                update("fingerprint")
                hasher.update(data: hash)
                hasher.update(data: Data([0xff]))
            } else {
                update("missing-fingerprint")
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Three-stage similarity pipeline:
/// 1. **Prehash phase**: computes QuickPrehash from existing metadata and thumbnails, then buckets candidate pairs.
/// 2. **Hash phase**: computes DCT-3D perceptual hashes in parallel and inserts them into a BK-Tree.
/// 3. **Comparison phase**: searches prehash candidates with the BK-Tree and optionally verifies them with Vision.
///
/// Key performance optimizations:
/// - QuickPrehash is a low-cost prefilter that avoids expensive work across all O(n^2) pairs.
/// - PerceptualHash computation runs in parallel with TaskGroup to use multiple cores.
/// - BK-Tree search is O(n log n), replacing an O(n^2) full comparison.
/// - Vision FeaturePrint is only used as a final verification layer, greatly reducing calls.
struct SimilarityPipeline: SimilarityProcessing {
    private let extractor: any FrameFeatureExtracting
    private let cache: (any HashCaching)?
    private let usesFrameVerification: Bool
    private let perceptualHashProvider: @Sendable (URL, UUID) async throws -> VideoPerceptualHash?
    /// Maximum Hamming distance for two perceptual hashes to be considered potentially similar.
    /// For 64-bit hashes, this allows up to 24 different bits.
    static let perceptualMaxDistance = 24
    fileprivate static let relationStorageFloor = 0.60
    fileprivate static let pairRelationWriteBatchSize = 512

    static func pairRelationAlgorithmVersion(usesFrameVerification: Bool) -> String {
        usesFrameVerification ? "video-pair-relation-v2-frame" : "video-pair-relation-v2-perceptual"
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
        usesFrameVerification: Bool = false,
        perceptualHashProvider: @escaping @Sendable (URL, UUID) async throws -> VideoPerceptualHash? = {
            try await PerceptualHasher.hash(for: $0, id: $1)
        }
    ) {
        self.cache = cache
        self.extractor = extractor
        self.usesFrameVerification = usesFrameVerification
        self.perceptualHashProvider = perceptualHashProvider
    }

    static func hashConcurrencyLimit(
        processorCount: Int,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState,
        scanIntensity: ScanIntensity = .balanced
    ) -> Int {
        scanIntensity.hashConcurrencyLimit(processorCount: processorCount, thermalState: thermalState)
    }

    static func comparisonConcurrencyLimit(
        processorCount: Int,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState,
        scanIntensity: ScanIntensity = .balanced
    ) -> Int {
        scanIntensity.comparisonConcurrencyLimit(processorCount: processorCount, thermalState: thermalState)
    }

    func process(
        videos: [MediaItem],
        threshold: Double,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> PipelineResult {
        try await process(videos: videos, threshold: threshold, scanIntensity: .balanced, progress: progress)
    }

    func process(
        videos: [MediaItem],
        threshold: Double,
        scanIntensity: ScanIntensity,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> PipelineResult {
        // ---- Phase A: QuickPrehash (low-cost, with bounded async thumbnail reads) ----
        await progress(ScanProgress(
            stage: .prehashing,
            fraction: 0,
            currentFile: "",
            discoveredCount: videos.count
        ))

        let prehashes = try await Self.computeQuickPrehashes(
            videos: videos,
            maxConcurrentLoads: scanIntensity.hashConcurrencyLimit(
                processorCount: ProcessInfo.processInfo.activeProcessorCount
            )
        )

        // Filter candidate pairs through QuickPrehash.
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

        // ---- Phase B: Perceptual hashes (parallel) ----
        // Only compute perceptual hashes for videos that appear in at least one candidate pair.
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
            scanIntensity: scanIntensity,
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
            try Task.checkCancellation()
            return PipelineResult(videos: videos, relations: cachedRelations)
        }

        // Build a BK-Tree for nearest-neighbor search.
        var bkTree = BKTree<VideoPerceptualHash>()
        for hash in perceptualHashes.values {
            bkTree.insert(hash, distance: { $0.hammingDistance(to: $1) })
        }

        // ---- Phase C: Candidate-pair comparison (BK-Tree + Vision) ----
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
        defer {
            Task { await frameFeatureCache.cancelAll() }
        }
        var pairCacheHits = 0
        var pairCacheTotal = 0
        var pendingPairRelationUpserts: [PairRelationCacheUpsert] = []

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
            let firstHash: String?
            let secondHash: String?
            do {
                firstHash = try await fileSHA256(for: candidate.first, memoizedHashes: &fileHashes)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                firstHash = nil
            }
            do {
                secondHash = try await fileSHA256(for: candidate.second, memoizedHashes: &fileHashes)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                secondHash = nil
            }
            guard let firstHash, firstHash == secondHash else { continue }
            processedPairs.insert(candidate.key)
            let relation = SimilarityRelation(
                firstID: candidate.first.id,
                secondID: candidate.second.id,
                score: 1,
                evidence: [.identicalContentHash]
            )
            relations.append(relation)
            pendingPairRelationUpserts.append(PairRelationCacheUpsert(
                first: candidate.first,
                second: candidate.second,
                algorithmVersion: pairRelationAlgorithmVersion,
                relation: relation
            ))
            if pendingPairRelationUpserts.count >= Self.pairRelationWriteBatchSize {
                await flushPairRelationUpserts(&pendingPairRelationUpserts, cache: cache)
            }
        }
        await flushPairRelationUpserts(&pendingPairRelationUpserts, cache: cache)

        // For each video with a perceptual hash, search for nearby hashes in the BK-Tree.
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

            if ScanProgressReporting.shouldReport(completed: qIndex + 1, total: totalQueries) {
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
                processorCount: ProcessInfo.processInfo.activeProcessorCount,
                scanIntensity: scanIntensity
            )
            var completedMisses = 0
            try await withThrowingTaskGroup(of: (VideoComparisonCandidate, SimilarityRelation?).self) { group in
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
                        return (next, relation)
                    }
                }

                while let (completedCandidate, relation) = try await group.next() {
                    completedMisses += 1
                    if let relation { relations.append(relation) }
                    pendingPairRelationUpserts.append(PairRelationCacheUpsert(
                        first: completedCandidate.first,
                        second: completedCandidate.second,
                        algorithmVersion: completedCandidate.algorithmVersion,
                        relation: relation
                    ))
                    if pendingPairRelationUpserts.count >= Self.pairRelationWriteBatchSize {
                        await flushPairRelationUpserts(&pendingPairRelationUpserts, cache: cache)
                    }
                    if ScanProgressReporting.shouldReport(completed: completedMisses, total: misses.count) {
                        await progress(ScanProgress(
                            stage: .comparing,
                            fraction: 0.2 + 0.8 * Double(completedMisses) / Double(misses.count),
                            currentFile: completedCandidate.first.filename,
                            discoveredCount: videos.count,
                            cacheHits: 0,
                            cacheTotal: 0,
                            cacheKind: nil,
                            comparisonPhase: .comparingUncached,
                            comparisonCompleted: completedMisses,
                            comparisonTotal: misses.count
                        ))
                    }
                    if let next = iterator.next() {
                        group.addTask {
                            let relation = try await compareVideoCandidate(
                                next,
                                cache: cache,
                                frameFeatureCache: frameFeatureCache,
                                usesFrameVerification: usesFrameVerification
                            )
                            return (next, relation)
                        }
                    }
                }
            }
            await flushPairRelationUpserts(&pendingPairRelationUpserts, cache: cache)
        }

        try Task.checkCancellation()
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

        try Task.checkCancellation()
        return PipelineResult(videos: videos, relations: relations)
    }

    /// Extracts every video that needs perceptual hashing from candidate pairs, removing duplicates.
    private func uniqueVideos(in pairs: [(MediaItem, MediaItem)]) -> [MediaItem] {
        var seen = Set<UUID>()
        var result: [MediaItem] = []
        for (first, second) in pairs {
            if seen.insert(first.id).inserted { result.append(first) }
            if seen.insert(second.id).inserted { result.append(second) }
        }
        return result
    }

    // MARK: - Phase A helpers

    private static func computeQuickPrehashes(
        videos: [MediaItem],
        maxConcurrentLoads: Int
    ) async throws -> [UUID: QuickPrehash] {
        try await withThrowingTaskGroup(of: (UUID, QuickPrehash).self) { group in
            var iterator = videos.makeIterator()
            let concurrencyLimit = max(1, maxConcurrentLoads)

            for _ in 0..<min(concurrencyLimit, videos.count) {
                guard let video = iterator.next() else { break }
                group.addTask {
                    try Task.checkCancellation()
                    let thumbnailData = await video.loadThumbnailData()
                    try Task.checkCancellation()
                    return (
                        video.id,
                        QuickPrehasher.prehash(for: video, thumbnailData: thumbnailData)
                    )
                }
            }

            var result: [UUID: QuickPrehash] = [:]
            result.reserveCapacity(videos.count)
            while let (id, prehash) = try await group.next() {
                result[id] = prehash
                if let video = iterator.next() {
                    group.addTask {
                        try Task.checkCancellation()
                        let thumbnailData = await video.loadThumbnailData()
                        try Task.checkCancellation()
                        return (
                            video.id,
                            QuickPrehasher.prehash(for: video, thumbnailData: thumbnailData)
                        )
                    }
                }
            }
            return result
        }
    }

    // MARK: - Phase B helpers

    /// Computes `PerceptualHash` values in parallel and reports progress.
    /// Videos that hit the cache skip hash computation.
    private func computePerceptualHashesInParallel(
        videos: [MediaItem],
        prehashes: [UUID: QuickPrehash],
        scanIntensity: ScanIntensity,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> [UUID: VideoPerceptualHash] {
        let total = max(videos.count, 1)
        let cacheTotal = videos.count
        let counter = ProgressCounter()

        // ---- Stage 1: filter cache hits ----
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
                        algorithmVersion: PerceptualHasher.algorithmVersion
                    )
                )
            })
            let batch = await cache.lookupHashes(keys: Array(keysByID.values))
            for video in videos {
                if let key = keysByID[video.id],
                   let record = batch[key],
                   let hash = record.toPerceptualHash(videoID: video.id) {
                    cached[video.id] = hash
                    continue
                }
                if let record = await cache.lookup(
                    filePath: video.url.path,
                    fileSize: video.fileSize,
                    modifiedAt: video.modifiedAt
                ), let hash = record.toPerceptualHash(videoID: video.id) {
                    cached[video.id] = hash
                    continue
                }
                needsHashing.append(video)
            }
        } else {
            needsHashing = videos
        }

        // Cache hits still count toward progress.
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

        // ---- Stage 2: compute missing hashes in parallel ----
        let concurrencyCap = Self.hashConcurrencyLimit(
            processorCount: ProcessInfo.processInfo.activeProcessorCount,
            scanIntensity: scanIntensity
        )
        let filenamesByID = Dictionary(uniqueKeysWithValues: needsHashing.map { ($0.id, $0.filename) })
        let perceptualHashProvider = perceptualHashProvider

        let computed = try await withThrowingTaskGroup(of: (UUID, VideoPerceptualHash?).self) { group in
            var iterator = needsHashing.makeIterator()
            var inFlight = 0

            while inFlight < concurrencyCap, let next = iterator.next() {
                try Task.checkCancellation()
                group.addTask {
                    try Task.checkCancellation()
                    let hash = try await perceptualHashProvider(next.url, next.id)
                    return (next.id, hash)
                }
                inFlight += 1
            }

            var results: [UUID: VideoPerceptualHash] = [:]
            while let (id, hash) = try await group.next() {
                try Task.checkCancellation()
                if let hash { results[id] = hash }

                let done = await counter.increment()
                if ScanProgressReporting.shouldReport(completed: done, total: total) {
                    await progress(ScanProgress(
                        stage: .hashing,
                        fraction: Double(done) / Double(total),
                        currentFile: filenamesByID[id] ?? "",
                        discoveredCount: total,
                        cacheHits: cached.count,
                        cacheTotal: cacheTotal,
                        cacheKind: cache != nil && cacheTotal > 0 ? .fingerprint : nil
                    ))
                }

                if let next = iterator.next() {
                    try Task.checkCancellation()
                    group.addTask {
                        try Task.checkCancellation()
                        let hash = try await perceptualHashProvider(next.url, next.id)
                        return (next.id, hash)
                    }
                }
            }

            return results
        }

        // ---- Stage 3: write computed hashes back to the cache ----
        if let cache {
            for video in needsHashing {
                guard let hash = computed[video.id], let prehash = prehashes[video.id] else { continue }
                let record = CacheRecord.make(video: video, perceptualHash: hash, quickPrehash: prehash)
                await cache.upsert(record)
            }
        }

        // Merge cache hits and newly computed hashes.
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
        let firstHash: String?
        let secondHash: String?
        do {
            firstHash = try await FileHasher.sha256(of: candidate.first.url, mediaKind: .video, cache: cache)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            firstHash = nil
        }
        do {
            secondHash = try await FileHasher.sha256(of: candidate.second.url, mediaKind: .video, cache: cache)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            secondHash = nil
        }
        hashMatch = firstHash != nil && firstHash == secondHash
    }

    let frameScore: Double?
    if !usesFrameVerification || hashMatch || percSimilarity >= 0.92 {
        frameScore = nil
    } else {
        do {
            frameScore = try await frameFeatureCache.similarity(
                between: candidate.first.url,
                and: candidate.second.url
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            frameScore = nil
        }
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
    return relation
}

private func flushPairRelationUpserts(
    _ pending: inout [PairRelationCacheUpsert],
    cache: (any HashCaching)?
) async {
    guard !pending.isEmpty else { return }
    let batch = pending
    pending.removeAll(keepingCapacity: true)
    await cache?.upsertPairRelations(batch)
}

private struct VideoComparisonCandidate: Sendable {
    let first: MediaItem
    let second: MediaItem
    let firstHash: VideoPerceptualHash
    let secondHash: VideoPerceptualHash
    let algorithmVersion: String
}

// MARK: - PairKey

/// Unique key for an unordered pair: (a, b) == (b, a).
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

/// Concurrency-safe progress counter shared across TaskGroup tasks.
private actor ProgressCounter {
    private var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}
