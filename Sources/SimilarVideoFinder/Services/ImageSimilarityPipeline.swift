// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import Foundation

struct ImagePipelineResult: Sendable {
    let images: [MediaItem]
    let relations: [SimilarityRelation]
    let groups: [SimilarityGroup]
}

struct ImageSimilarityPipeline: Sendable {
    static let algorithmVersion = "image-phash-v1"
    static let pairRelationAlgorithmVersion = "image-pair-relation-v1"
    static let maxDistance = 20
    private static let relationStorageFloor = 0.60
    private let cache: (any HashCaching)?
    private let featureExtractor: any ImageFeatureExtracting

    init(cache: (any HashCaching)? = nil, featureExtractor: any ImageFeatureExtracting = ImageFeatureExtractor()) {
        self.cache = cache
        self.featureExtractor = featureExtractor
    }

    func process(
        images: [MediaItem],
        threshold: Double,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> ImagePipelineResult {
        let images = images.filter { $0.kind == .image }
        await progress(ScanProgress(stage: .hashing, fraction: 0, discoveredCount: images.count))
        let hashes = try await computeHashes(images: images, progress: progress)
        var tree = BKTree<ImagePerceptualHash>()
        for hash in hashes.values { tree.insert(hash) { $0.hammingDistance(to: $1) } }

        try Task.checkCancellation()
        await progress(ScanProgress(stage: .comparing, fraction: 0, discoveredCount: images.count))
        let byID = Dictionary(uniqueKeysWithValues: images.map { ($0.id, $0) })
        let featureCache = ImageFeatureCache(extractor: featureExtractor, persistentCache: cache)
        var seen = Set<ImagePairKey>()
        var relations: [SimilarityRelation] = []
        var pairCacheHits = 0
        var pairCacheTotal = 0
        for (index, image) in images.enumerated() {
            try Task.checkCancellation()
            guard let hash = hashes[image.id] else { continue }
            for neighbor in tree.search(hash, maxDistance: Self.maxDistance, distance: { $0.hammingDistance(to: $1) }) where neighbor.item.mediaID != image.id {
                let key = ImagePairKey(image.id, neighbor.item.mediaID)
                guard seen.insert(key).inserted, let other = byID[neighbor.item.mediaID] else { continue }
                if let cache {
                    pairCacheTotal += 1
                    if let cached = await cache.lookupPairRelation(first: image, second: other, algorithmVersion: Self.pairRelationAlgorithmVersion) {
                        pairCacheHits += 1
                        if let relation = cached.relation(firstID: image.id, secondID: other.id) {
                            relations.append(relation)
                        }
                        continue
                    }
                }
                let perceptual = hash.similarity(to: neighbor.item)
                var exact = false
                if image.fileSize > 0 && image.fileSize == other.fileSize && neighbor.dist == 0,
                   let firstHash = try? await FileHasher.sha256(of: image.url, mediaKind: .image, cache: cache),
                   let secondHash = try? await FileHasher.sha256(of: other.url, mediaKind: .image, cache: cache) {
                    exact = firstHash == secondHash
                }
                try Task.checkCancellation()
                let feature = !exact && perceptual >= 0.72
                    ? await featureCache.similarity(between: image.url, and: other.url)
                    : nil
                let score = SimilarityScorer.score(image, other, hashesMatch: exact, perceptualSimilarity: perceptual, frameSimilarity: feature)
                let relation: SimilarityRelation?
                if score.score >= Self.relationStorageFloor {
                    relation = SimilarityRelation(firstID: image.id, secondID: other.id, score: score.score, evidence: score.evidence)
                    if let relation { relations.append(relation) }
                } else {
                    relation = nil
                }
                await cache?.upsertPairRelation(first: image, second: other, algorithmVersion: Self.pairRelationAlgorithmVersion, relation: relation)
            }
            await progress(ScanProgress(
                stage: .comparing,
                fraction: images.isEmpty ? 1 : Double(index + 1) / Double(images.count),
                currentFile: image.filename,
                discoveredCount: images.count,
                cacheHits: pairCacheHits,
                cacheTotal: pairCacheTotal,
                cacheKind: cache != nil && pairCacheTotal > 0 ? .relation : nil
            ))
        }
        return ImagePipelineResult(images: images, relations: relations, groups: SimilarityGrouper.groups(items: images, relations: relations, threshold: threshold))
    }

    private func computeHashes(images: [MediaItem], progress: @escaping @Sendable (ScanProgress) async -> Void) async throws -> [UUID: ImagePerceptualHash] {
        var hashes: [UUID: ImagePerceptualHash] = [:]
        var missing: [MediaItem] = []
        for image in images {
            if let record = await cache?.lookup(filePath: image.url.path, fileSize: image.fileSize, modifiedAt: image.modifiedAt, mediaKind: .image, algorithmVersion: Self.algorithmVersion) {
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
        try await withThrowingTaskGroup(of: (MediaItem, ImagePerceptualHash?).self) { group in
            var iterator = missing.makeIterator()
            for _ in 0..<min(4, missing.count) {
                if let item = iterator.next() { group.addTask { (item, try? ImagePerceptualHasher.hash(for: item.url, id: item.id)) } }
            }
            var completed = hashes.count
            while let (item, hash) = try await group.next() {
                completed += 1
                if let hash {
                    hashes[item.id] = hash
                    var record = CacheRecord(filePath: item.url.path, fileSize: item.fileSize, modifiedAt: item.modifiedAt, perceptualHash: Data(hash.hashBits), prehashDurationBucket: 0, prehashSizeBucket: 0, prehashAspectBucket: 0, prehashThumbnailMean: 0, prehashThumbnailVariance: 0)
                    record.mediaKind = MediaKind.image.rawValue
                    record.algorithmVersion = Self.algorithmVersion
                    await cache?.upsert(record)
                }
                await progress(ScanProgress(
                    stage: .hashing,
                    fraction: images.isEmpty ? 1 : Double(completed) / Double(images.count),
                    currentFile: item.filename,
                    discoveredCount: images.count,
                    cacheHits: cacheHits,
                    cacheTotal: images.count,
                    cacheKind: cache != nil && !images.isEmpty ? .fingerprint : nil
                ))
                if let next = iterator.next() { group.addTask { (next, try? ImagePerceptualHasher.hash(for: next.url, id: next.id)) } }
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
