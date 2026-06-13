// Targie - Find similar videos on macOS.
// Copyright (C) 2026 Lirui Yu

import Foundation

struct PrehashCandidateResult {
    let pairs: [(MediaItem, MediaItem)]
    let compatibilityChecks: Int
}

enum PrehashCandidateFinder {
    private struct BucketKey: Hashable {
        let duration: Int
        let size: Int
        let aspect: Int
    }

    private struct PairKey: Hashable {
        let first: UUID
        let second: UUID

        init(_ lhs: UUID, _ rhs: UUID) {
            if lhs.uuidString < rhs.uuidString {
                first = lhs
                second = rhs
            } else {
                first = rhs
                second = lhs
            }
        }
    }

    static func find(
        videos: [MediaItem],
        prehashes: [UUID: QuickPrehash]
    ) -> PrehashCandidateResult {
        var buckets: [BucketKey: [MediaItem]] = [:]
        var names: [String: [MediaItem]] = [:]
        var pairKeys = Set<PairKey>()
        var pairs: [(MediaItem, MediaItem)] = []
        var compatibilityChecks = 0

        func appendPair(_ first: MediaItem, _ second: MediaItem) {
            guard pairKeys.insert(PairKey(first.id, second.id)).inserted else { return }
            pairs.append((first, second))
        }

        for video in videos {
            guard let prehash = prehashes[video.id] else { continue }

            for duration in (prehash.durationBucket - 2)...(prehash.durationBucket + 2) {
                for size in (prehash.sizeBucket - 3)...(prehash.sizeBucket + 3) {
                    for aspect in (prehash.aspectBucket - 2)...(prehash.aspectBucket + 2) {
                        let key = BucketKey(duration: duration, size: size, aspect: aspect)
                        for candidate in buckets[key] ?? [] {
                            guard let candidatePrehash = prehashes[candidate.id] else { continue }
                            compatibilityChecks += 1
                            if prehash.isCompatible(with: candidatePrehash) {
                                appendPair(candidate, video)
                            }
                        }
                    }
                }
            }

            let normalizedName = FilenameNormalizer.normalize(video.filename)
            if !normalizedName.isEmpty {
                for candidate in names[normalizedName] ?? [] {
                    appendPair(candidate, video)
                }
                names[normalizedName, default: []].append(video)
            }

            let ownKey = BucketKey(
                duration: prehash.durationBucket,
                size: prehash.sizeBucket,
                aspect: prehash.aspectBucket
            )
            buckets[ownKey, default: []].append(video)
        }

        return PrehashCandidateResult(pairs: pairs, compatibilityChecks: compatibilityChecks)
    }
}
