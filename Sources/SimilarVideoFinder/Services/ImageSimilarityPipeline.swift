// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import Foundation

struct ImagePipelineResult: Sendable {
    let images: [MediaItem]
    let relations: [SimilarityRelation]
}

struct ImageSimilarityPipeline: Sendable {
    static let algorithmVersion = "image-phash-v1"
    static let pairRelationAlgorithmVersion = "image-pair-relation-v2"
    static let maxDistance = 20
    fileprivate static let relationStorageFloor = 0.60
    private static let pairRelationWriteBatchSize = 512
    private let cache: (any HashCaching)?
    private let featureExtractor: any ImageFeatureExtracting
    private let perceptualHashProvider: @Sendable (URL, UUID) async throws -> ImagePerceptualHash?

    init(
        cache: (any HashCaching)? = nil,
        featureExtractor: any ImageFeatureExtracting = ImageFeatureExtractor(),
        perceptualHashProvider: @escaping @Sendable (URL, UUID) async throws -> ImagePerceptualHash? = {
            try ImagePerceptualHasher.hash(for: $0, id: $1)
        }
    ) {
        self.cache = cache
        self.featureExtractor = featureExtractor
        self.perceptualHashProvider = perceptualHashProvider
    }

    static func comparisonConcurrencyLimit(
        processorCount: Int,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState,
        scanIntensity: ScanIntensity = .balanced
    ) -> Int {
        scanIntensity.comparisonConcurrencyLimit(processorCount: processorCount, thermalState: thermalState)
    }

    static func hashConcurrencyLimit(
        processorCount: Int,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState,
        scanIntensity: ScanIntensity = .balanced
    ) -> Int {
        scanIntensity.hashConcurrencyLimit(processorCount: processorCount, thermalState: thermalState)
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

    func process(
        images: [MediaItem],
        threshold: Double,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> ImagePipelineResult {
        try await process(images: images, threshold: threshold, scanIntensity: .balanced, progress: progress)
    }

    func process(
        images: [MediaItem],
        threshold: Double,
        scanIntensity: ScanIntensity,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> ImagePipelineResult {
        let images = images.filter { $0.kind == .image }
        await progress(ScanProgress(stage: .hashing, fraction: 0, discoveredCount: images.count))
        let hashes = try await computeHashes(images: images, scanIntensity: scanIntensity, progress: progress)
        let hashDataByID = hashes.mapValues { Data($0.hashBits) }
        let indexSignature = Self.scanRelationSignature(
            items: images,
            hashes: hashDataByID,
            algorithmVersion: Self.pairRelationAlgorithmVersion
        )
        if let cachedIndex = await cache?.lookupScanRelationIndex(
            signature: indexSignature,
            mediaKind: .image,
            algorithmVersion: Self.pairRelationAlgorithmVersion
        ) {
            let itemsByPath = Dictionary(uniqueKeysWithValues: images.map { ($0.url.path, $0) })
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
                discoveredCount: images.count,
                cacheHits: cachedIndex.candidateCount,
                cacheTotal: cachedIndex.candidateCount,
                cacheKind: .relation,
                comparisonPhase: .checkingPairCache
            ))
            try Task.checkCancellation()
            return ImagePipelineResult(images: images, relations: cachedRelations)
        }

        var tree = BKTree<ImagePerceptualHash>()
        for hash in hashes.values { tree.insert(hash) { $0.hammingDistance(to: $1) } }

        try Task.checkCancellation()
        await progress(ScanProgress(
            stage: .comparing,
            fraction: 0,
            discoveredCount: images.count,
            comparisonPhase: .findingCandidates,
            comparisonCompleted: 0,
            comparisonTotal: max(images.count, 1)
        ))
        let byID = Dictionary(uniqueKeysWithValues: images.map { ($0.id, $0) })
        let featureCache = ImageFeatureCache(
            extractor: featureExtractor,
            persistentCache: cache,
            maxConcurrentExtractions: scanIntensity.visionFeatureConcurrencyLimit()
        )
        defer {
            Task { await featureCache.cancelAll() }
        }
        var seen = Set<ImagePairKey>()
        var relations: [SimilarityRelation] = []
        var pairCacheHits = 0
        var pairCacheTotal = 0
        var pendingPairRelationUpserts: [PairRelationCacheUpsert] = []
        var pendingComparisonCandidates: [(candidate: ImageComparisonCandidate, relationKey: PairRelationCacheKey?)] = []
        for (index, image) in images.enumerated() {
            try Task.checkCancellation()
            guard let hash = hashes[image.id] else { continue }
            for neighbor in tree.search(hash, maxDistance: Self.maxDistance, distance: { $0.hammingDistance(to: $1) }) where neighbor.item.mediaID != image.id {
                let key = ImagePairKey(image.id, neighbor.item.mediaID)
                guard seen.insert(key).inserted, let other = byID[neighbor.item.mediaID] else { continue }
                pendingComparisonCandidates.append((
                    candidate: ImageComparisonCandidate(
                        first: image,
                        second: other,
                        firstHash: hash,
                        secondHash: neighbor.item,
                        neighborDistance: neighbor.dist
                    ),
                    relationKey: PairRelationCacheKey(first: image, second: other, algorithmVersion: Self.pairRelationAlgorithmVersion)
                ))
            }

            if ScanProgressReporting.shouldReport(completed: index + 1, total: images.count) {
                await progress(ScanProgress(
                    stage: .comparing,
                    fraction: images.isEmpty ? 1 : Double(index + 1) / Double(images.count) * 0.2,
                    currentFile: image.filename,
                    discoveredCount: images.count,
                    cacheHits: pairCacheHits,
                    cacheTotal: pairCacheTotal,
                    cacheKind: cache != nil && pairCacheTotal > 0 ? .relation : nil,
                    comparisonPhase: .findingCandidates,
                    comparisonCompleted: index + 1,
                    comparisonTotal: max(images.count, 1)
                ))
            }
        }

        let relationKeys = pendingComparisonCandidates.compactMap(\.relationKey)
        let relationCache: [PairRelationCacheKey: PairRelationCacheEntry] = cache == nil || relationKeys.isEmpty
            ? [:]
            : await cache?.lookupPairRelations(keys: relationKeys) ?? [:]
        var misses: [ImageComparisonCandidate] = []
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

        let cacheProgressFile = pendingComparisonCandidates.first?.candidate.first.filename ?? ""
        if misses.isEmpty {
            await progress(ScanProgress(
                stage: .comparing,
                fraction: 1,
                currentFile: cacheProgressFile,
                discoveredCount: images.count,
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
                discoveredCount: images.count,
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
            try await withThrowingTaskGroup(of: (ImageComparisonCandidate, SimilarityRelation?).self) { group in
                var iterator = misses.makeIterator()
                for _ in 0..<min(comparisonLimit, misses.count) {
                    guard let next = iterator.next() else { break }
                    group.addTask {
                        let relation = try await compareImageCandidate(next, cache: cache, featureCache: featureCache)
                        return (next, relation)
                    }
                }

                while let (completedCandidate, relation) = try await group.next() {
                    completedMisses += 1
                    if let relation { relations.append(relation) }
                    pendingPairRelationUpserts.append(PairRelationCacheUpsert(
                        first: completedCandidate.first,
                        second: completedCandidate.second,
                        algorithmVersion: Self.pairRelationAlgorithmVersion,
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
                            discoveredCount: images.count,
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
                            let relation = try await compareImageCandidate(next, cache: cache, featureCache: featureCache)
                            return (next, relation)
                        }
                    }
                }
            }
            await flushPairRelationUpserts(&pendingPairRelationUpserts, cache: cache)
        }
        try Task.checkCancellation()
        let scanIndexRelations = relations.compactMap { relation -> CachedScanRelation? in
            guard let first = byID[relation.firstID],
                  let second = byID[relation.secondID]
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
            mediaKind: .image,
            algorithmVersion: Self.pairRelationAlgorithmVersion,
            fileCount: images.count,
            candidateCount: pairCacheTotal,
            relations: scanIndexRelations
        )
        try Task.checkCancellation()
        return ImagePipelineResult(images: images, relations: relations)
    }

    private func computeHashes(
        images: [MediaItem],
        scanIntensity: ScanIntensity,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> [UUID: ImagePerceptualHash] {
        var hashes: [UUID: ImagePerceptualHash] = [:]
        var missing: [MediaItem] = []
        let keysByID = Dictionary(uniqueKeysWithValues: images.map {
            (
                $0.id,
                MediaHashCacheKey(
                    filePath: $0.url.path,
                    fileSize: $0.fileSize,
                    modifiedAt: $0.modifiedAt,
                    mediaKind: .image,
                    algorithmVersion: Self.algorithmVersion
                )
            )
        })
        let batch: [MediaHashCacheKey: CacheRecord] = cache == nil
            ? [:]
            : await cache?.lookupHashes(keys: Array(keysByID.values)) ?? [:]
        for image in images {
            if let key = keysByID[image.id], let record = batch[key] {
                hashes[image.id] = ImagePerceptualHash(mediaID: image.id, hashBits: Array(record.perceptualHash))
            } else if let record = await cache?.lookup(filePath: image.url.path, fileSize: image.fileSize, modifiedAt: image.modifiedAt, mediaKind: .image, algorithmVersion: Self.algorithmVersion) {
                hashes[image.id] = ImagePerceptualHash(mediaID: image.id, hashBits: Array(record.perceptualHash))
            } else { missing.append(image) }
        }
        let cacheHits = hashes.count
        if cache != nil, !images.isEmpty {
            await progress(ScanProgress(
                stage: .hashing,
                fraction: Double(cacheHits) / Double(images.count),
                discoveredCount: images.count,
                cacheHits: cacheHits,
                cacheTotal: images.count,
                cacheKind: .fingerprint
            ))
        }
        let concurrencyLimit = Self.hashConcurrencyLimit(
            processorCount: ProcessInfo.processInfo.activeProcessorCount,
            scanIntensity: scanIntensity
        )
        let perceptualHashProvider = perceptualHashProvider
        try await withThrowingTaskGroup(of: (MediaItem, ImagePerceptualHash?).self) { group in
            var iterator = missing.makeIterator()
            for _ in 0..<min(concurrencyLimit, missing.count) {
                try Task.checkCancellation()
                if let item = iterator.next() {
                    group.addTask {
                        try Task.checkCancellation()
                        do {
                            return (item, try await perceptualHashProvider(item.url, item.id))
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            return (item, nil)
                        }
                    }
                }
            }
            var completed = hashes.count
            while let (item, hash) = try await group.next() {
                try Task.checkCancellation()
                completed += 1
                if let hash {
                    hashes[item.id] = hash
                    var record = CacheRecord(filePath: item.url.path, fileSize: item.fileSize, modifiedAt: item.modifiedAt, perceptualHash: Data(hash.hashBits), prehashDurationBucket: 0, prehashSizeBucket: 0, prehashAspectBucket: 0, prehashThumbnailMean: 0, prehashThumbnailVariance: 0)
                    record.mediaKind = MediaKind.image.rawValue
                    record.algorithmVersion = Self.algorithmVersion
                    await cache?.upsert(record)
                }
                if ScanProgressReporting.shouldReport(completed: completed, total: images.count) {
                    await progress(ScanProgress(
                        stage: .hashing,
                        fraction: images.isEmpty ? 1 : Double(completed) / Double(images.count),
                        currentFile: item.filename,
                        discoveredCount: images.count,
                        cacheHits: cacheHits,
                        cacheTotal: images.count,
                        cacheKind: cache != nil && !images.isEmpty ? .fingerprint : nil
                    ))
                }
                if let next = iterator.next() {
                    try Task.checkCancellation()
                    group.addTask {
                        try Task.checkCancellation()
                        do {
                            return (next, try await perceptualHashProvider(next.url, next.id))
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            return (next, nil)
                        }
                    }
                }
            }
        }
        return hashes
    }
}

private struct ImagePairKey: Hashable {
    let first: UUID
    let second: UUID
    init(_ lhs: UUID, _ rhs: UUID) {
        if lhs.uuidString < rhs.uuidString { first = lhs; second = rhs } else { first = rhs; second = lhs }
    }
}

private func compareImageCandidate(
    _ candidate: ImageComparisonCandidate,
    cache: (any HashCaching)?,
    featureCache: ImageFeatureCache
) async throws -> SimilarityRelation? {
    try Task.checkCancellation()
    let perceptual = candidate.firstHash.similarity(to: candidate.secondHash)
    var exact = false
    if candidate.first.fileSize > 0,
       candidate.first.fileSize == candidate.second.fileSize,
       candidate.neighborDistance == 0 {
        let firstHash: String?
        let secondHash: String?
        do {
            firstHash = try await FileHasher.sha256(of: candidate.first.url, mediaKind: .image, cache: cache)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            firstHash = nil
        }
        do {
            secondHash = try await FileHasher.sha256(of: candidate.second.url, mediaKind: .image, cache: cache)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            secondHash = nil
        }
        exact = firstHash != nil && firstHash == secondHash
    }

    let feature = !exact && perceptual >= 0.72
        ? try await featureCache.similarity(between: candidate.first.url, and: candidate.second.url)
        : nil
    let score = SimilarityScorer.score(
        candidate.first,
        candidate.second,
        hashesMatch: exact,
        perceptualSimilarity: perceptual,
        frameSimilarity: feature
    )
    let relation: SimilarityRelation?
    if score.score >= ImageSimilarityPipeline.relationStorageFloor {
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

private struct ImageComparisonCandidate: Sendable {
    let first: MediaItem
    let second: MediaItem
    let firstHash: ImagePerceptualHash
    let secondHash: ImagePerceptualHash
    let neighborDistance: Int
}
