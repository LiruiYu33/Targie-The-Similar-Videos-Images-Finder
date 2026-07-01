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
import GRDB

// MARK: - CacheRecord

/// 单个视频的缓存哈希记录。filePath + fileSize + modifiedAt 三者组合确定缓存有效性,
/// 任一不匹配则视为缓存失效, 重新计算并覆盖。
struct CacheRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    var filePath: String          // 视频文件绝对路径 (PRIMARY KEY)
    var fileSize: Int64
    var modifiedAt: Date?
    var perceptualHash: Data      // VideoPerceptualHash.hashBits 序列化为 Data
    var prehashDurationBucket: Int
    var prehashSizeBucket: Int
    var prehashAspectBucket: Int
    var prehashThumbnailMean: Int
    var prehashThumbnailVariance: Int
    var mediaKind: String = MediaKind.video.rawValue
    var algorithmVersion: String = "video-dct3d-v1"

    static var databaseTableName: String { "hash_cache" }
}

private protocol FilePathCacheRecord {
    var filePath: String { get }
    var fileSize: Int64 { get }
    var modifiedAt: Date? { get }
}

extension CacheRecord: FilePathCacheRecord {}

// MARK: - MediaMetadata (avoids re-reading AVFoundation on re-scan)

/// Cached video/image metadata so `loadVideo`/`loadImage` can skip AVFoundation /
/// CGImageSource calls when re-scanning the same file.
struct MediaMetadata: Codable, Sendable, FetchableRecord, PersistableRecord {
    var filePath: String    // PRIMARY KEY
    var fileSize: Int64
    var modifiedAt: Date?
    var duration: Double?
    var width: Int?
    var height: Int?
    var mediaKind: String
    var sha256: String?

    static var databaseTableName: String { "media_metadata" }
}

extension MediaMetadata: FilePathCacheRecord {}

// MARK: - ImageFeatureRecord (avoids re-running Vision on re-scan)

/// Persisted `VNFeaturePrintObservation` blob so the image comparison phase
/// can skip the Vision neural-network inference on re-scan.
struct ImageFeatureRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    var filePath: String    // PRIMARY KEY
    var fileSize: Int64
    var modifiedAt: Date?
    var featureData: Data   // NSKeyedArchiver archive of VNFeaturePrintObservation

    static var databaseTableName: String { "image_features" }
}

extension ImageFeatureRecord: FilePathCacheRecord {}

// MARK: - FrameFeatureRecord (avoids re-running Vision on video frames)

/// Persisted serialized `FrameFeatures` blob so optional video frame
/// verification can skip repeated frame decode + Vision inference.
struct FrameFeatureRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    var filePath: String    // PRIMARY KEY
    var fileSize: Int64
    var modifiedAt: Date?
    var featureData: Data

    static var databaseTableName: String { "frame_features" }
}

extension FrameFeatureRecord: FilePathCacheRecord {}

// MARK: - Pair Relation Cache

struct PairRelationCacheEntry: Equatable, Sendable {
    let score: Double?
    let evidence: Set<SimilarityEvidence>

    func relation(firstID: UUID, secondID: UUID) -> SimilarityRelation? {
        guard let score else { return nil }
        return SimilarityRelation(firstID: firstID, secondID: secondID, score: score, evidence: evidence)
    }
}

struct CachedScanRelation: Equatable, Sendable {
    let firstPath: String
    let secondPath: String
    let score: Double
    let evidence: Set<SimilarityEvidence>
}

struct CachedScanRelationIndex: Equatable, Sendable {
    let signature: String
    let mediaKind: MediaKind
    let algorithmVersion: String
    let fileCount: Int
    let candidateCount: Int
    let relations: [CachedScanRelation]
}

struct MediaMetadataCacheKey: Hashable, Sendable {
    let filePath: String
    let fileSize: Int64
    let modifiedAt: Date?
    let mediaKind: MediaKind
}

struct MediaMetadataCacheEntry: Equatable, Sendable {
    let duration: Double?
    let width: Int?
    let height: Int?
}

struct MediaHashCacheKey: Hashable, Sendable {
    let filePath: String
    let fileSize: Int64
    let modifiedAt: Date?
    let mediaKind: MediaKind
    let algorithmVersion: String
}

struct PairRelationCacheKey: Hashable, Sendable {
    let firstPath: String
    let secondPath: String
    let firstFileSize: Int64
    let secondFileSize: Int64
    let firstModifiedAt: Date?
    let secondModifiedAt: Date?
    let mediaKind: MediaKind
    let algorithmVersion: String

    init?(first lhs: MediaItem, second rhs: MediaItem, algorithmVersion: String) {
        guard lhs.kind == rhs.kind, lhs.url.path != rhs.url.path else { return nil }
        let first: MediaItem
        let second: MediaItem
        if lhs.url.path < rhs.url.path {
            first = lhs
            second = rhs
        } else {
            first = rhs
            second = lhs
        }
        self.firstPath = first.url.path
        self.secondPath = second.url.path
        self.firstFileSize = first.fileSize
        self.secondFileSize = second.fileSize
        self.firstModifiedAt = Self.normalizedModifiedAt(first.modifiedAt)
        self.secondModifiedAt = Self.normalizedModifiedAt(second.modifiedAt)
        self.mediaKind = first.kind
        self.algorithmVersion = algorithmVersion
    }

    private static func normalizedModifiedAt(_ date: Date?) -> Date? {
        guard let date else { return nil }
        let milliseconds = (date.timeIntervalSince1970 * 1_000).rounded()
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }
}

private struct PairRelationRecord: Codable, Sendable, FetchableRecord, TableRecord {
    var firstPath: String
    var secondPath: String
    var firstFileSize: Int64
    var secondFileSize: Int64
    var firstModifiedAt: Date?
    var secondModifiedAt: Date?
    var mediaKind: String
    var algorithmVersion: String
    var score: Double?
    var evidence: String

    static var databaseTableName: String { "pair_relations" }
}

private struct ScanRelationIndexRecord: Codable, Sendable, FetchableRecord, TableRecord {
    var signature: String
    var mediaKind: String
    var algorithmVersion: String
    var fileCount: Int
    var candidateCount: Int

    static var databaseTableName: String { "scan_relation_indexes" }
}

private struct ScanRelationIndexRelationRecord: Codable, Sendable, FetchableRecord, TableRecord {
    var signature: String
    var mediaKind: String
    var algorithmVersion: String
    var firstPath: String
    var secondPath: String
    var score: Double
    var evidence: String

    static var databaseTableName: String { "scan_relation_index_relations" }
}

private enum PairRelationCacheCodec {
    static func identity(first lhs: MediaItem, second rhs: MediaItem, algorithmVersion: String) -> PairRelationCacheKey? {
        PairRelationCacheKey(first: lhs, second: rhs, algorithmVersion: algorithmVersion)
    }

    static func record(identity: PairRelationCacheKey, relation: SimilarityRelation?) -> PairRelationRecord {
        PairRelationRecord(
            firstPath: identity.firstPath,
            secondPath: identity.secondPath,
            firstFileSize: identity.firstFileSize,
            secondFileSize: identity.secondFileSize,
            firstModifiedAt: identity.firstModifiedAt,
            secondModifiedAt: identity.secondModifiedAt,
            mediaKind: identity.mediaKind.rawValue,
            algorithmVersion: identity.algorithmVersion,
            score: relation?.score,
            evidence: encode(relation?.evidence ?? [])
        )
    }

    static func entry(record: PairRelationRecord, identity: PairRelationCacheKey) -> PairRelationCacheEntry? {
        guard record.firstFileSize == identity.firstFileSize,
              record.secondFileSize == identity.secondFileSize,
              identityDateMatch(record.firstModifiedAt, identity.firstModifiedAt),
              identityDateMatch(record.secondModifiedAt, identity.secondModifiedAt)
        else { return nil }
        return PairRelationCacheEntry(score: record.score, evidence: decode(record.evidence))
    }

    private static func encode(_ evidence: Set<SimilarityEvidence>) -> String {
        evidence.map(\.rawValue).sorted().joined(separator: ",")
    }

    private static func decode(_ value: String) -> Set<SimilarityEvidence> {
        Set(value.split(separator: ",").compactMap { SimilarityEvidence(rawValue: String($0)) })
    }

    private static func identityDateMatch(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return abs(lhs.timeIntervalSince(rhs)) < 0.001
    }
}

private enum ScanRelationIndexCodec {
    static func storedRelation(_ relation: CachedScanRelation) -> CachedScanRelation {
        let ordered = relation.firstPath < relation.secondPath
            ? (relation.firstPath, relation.secondPath)
            : (relation.secondPath, relation.firstPath)
        return CachedScanRelation(
            firstPath: ordered.0,
            secondPath: ordered.1,
            score: relation.score,
            evidence: relation.evidence
        )
    }

    static func encode(_ evidence: Set<SimilarityEvidence>) -> String {
        evidence.map(\.rawValue).sorted().joined(separator: ",")
    }

    static func decode(_ value: String) -> Set<SimilarityEvidence> {
        Set(value.split(separator: ",").compactMap { SimilarityEvidence(rawValue: String($0)) })
    }
}

// MARK: - HashCache Protocol

/// 缓存接口 — 通过协议化便于测试时注入 InMemory 替身。
protocol HashCaching: Sendable {
    func lookup(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> CacheRecord?
    func upsert(_ record: CacheRecord) async
    func pruneStale(validPaths: Set<String>) async
    func count() async -> Int
    func clearAll() async
    func sizeInBytes() async -> Int64
    func lookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, algorithmVersion: String) async -> CacheRecord?
    func lookupHashes(keys: [MediaHashCacheKey]) async -> [MediaHashCacheKey: CacheRecord]

    // Metadata cache — lets loadVideo / loadImage skip AVFoundation re-read on
    // re-scan when the file hasn't changed.
    func upsertMetadata(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, duration: Double?, width: Int?, height: Int?) async
    func lookupMetadata(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) async -> (duration: Double?, width: Int?, height: Int?)?
    func lookupMetadata(keys: [MediaMetadataCacheKey]) async -> [MediaMetadataCacheKey: MediaMetadataCacheEntry]

    // SHA-256 file hash cache — avoids re-reading every byte of same-size files
    // on every re-scan.
    func upsertSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, sha256: String) async
    func lookupSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) async -> String?

    // Image feature cache — persists VNFeaturePrintObservation so the comparing
    // phase skips Vision neural-network inference on re-scan.
    func upsertImageFeature(filePath: String, fileSize: Int64, modifiedAt: Date?, featureData: Data) async
    func lookupImageFeature(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> Data?

    // Video frame feature cache — persists sampled frame feature prints so
    // optional frame verification can survive process restarts.
    func upsertFrameFeature(filePath: String, fileSize: Int64, modifiedAt: Date?, featureData: Data) async
    func lookupFrameFeature(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> Data?

    // Pair relation cache — stores the final comparison result for a candidate
    // pair so re-scans can skip pair-level SHA / Vision / scoring work.
    func upsertPairRelation(first: MediaItem, second: MediaItem, algorithmVersion: String, relation: SimilarityRelation?) async
    func lookupPairRelation(first: MediaItem, second: MediaItem, algorithmVersion: String) async -> PairRelationCacheEntry?
    func lookupPairRelations(keys: [PairRelationCacheKey]) async -> [PairRelationCacheKey: PairRelationCacheEntry]

    // Scan relation index cache — stores the complete positive relation result
    // for an unchanged scan signature so re-scans can skip candidate generation.
    func lookupScanRelationIndex(signature: String, mediaKind: MediaKind, algorithmVersion: String) async -> CachedScanRelationIndex?
    func upsertScanRelationIndex(signature: String, mediaKind: MediaKind, algorithmVersion: String, fileCount: Int, candidateCount: Int, relations: [CachedScanRelation]) async

    /// Returns the previous path of a file that was moved, if one can be found
    /// in the cache. Read-only — does NOT update the path; the caller is
    /// responsible for migrating other caches (e.g. thumbnails) using the
    /// returned old path.
    func detectMove(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, algorithmVersion: String) async -> String?
}

extension HashCaching {
    func lookup(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> CacheRecord? {
        await lookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt, mediaKind: .video, algorithmVersion: "video-dct3d-v1")
    }

    func lookupHashes(keys: [MediaHashCacheKey]) async -> [MediaHashCacheKey: CacheRecord] {
        var results: [MediaHashCacheKey: CacheRecord] = [:]
        for key in keys {
            guard let record = await lookup(
                filePath: key.filePath,
                fileSize: key.fileSize,
                modifiedAt: key.modifiedAt,
                mediaKind: key.mediaKind,
                algorithmVersion: key.algorithmVersion
            ) else { continue }
            results[key] = record
        }
        return results
    }

    func upsertMetadata(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, duration: Double?, width: Int?, height: Int?) async {}
    func lookupMetadata(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) async -> (duration: Double?, width: Int?, height: Int?)? { nil }
    func lookupMetadata(keys: [MediaMetadataCacheKey]) async -> [MediaMetadataCacheKey: MediaMetadataCacheEntry] {
        var results: [MediaMetadataCacheKey: MediaMetadataCacheEntry] = [:]
        for key in keys {
            guard let entry = await lookupMetadata(
                filePath: key.filePath,
                fileSize: key.fileSize,
                modifiedAt: key.modifiedAt,
                mediaKind: key.mediaKind
            ) else { continue }
            results[key] = MediaMetadataCacheEntry(duration: entry.duration, width: entry.width, height: entry.height)
        }
        return results
    }

    func upsertSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, sha256: String) async {}
    func lookupSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) async -> String? { nil }

    func upsertSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?, sha256: String) async {
        await upsertSHA256(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt, mediaKind: .video, sha256: sha256)
    }

    func lookupSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> String? {
        await lookupSHA256(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt, mediaKind: .video)
    }

    func upsertImageFeature(filePath: String, fileSize: Int64, modifiedAt: Date?, featureData: Data) async {}
    func lookupImageFeature(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> Data? { nil }
    func upsertFrameFeature(filePath: String, fileSize: Int64, modifiedAt: Date?, featureData: Data) async {}
    func lookupFrameFeature(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> Data? { nil }
    func upsertPairRelation(first: MediaItem, second: MediaItem, algorithmVersion: String, relation: SimilarityRelation?) async {}
    func lookupPairRelation(first: MediaItem, second: MediaItem, algorithmVersion: String) async -> PairRelationCacheEntry? { nil }
    func lookupPairRelations(keys: [PairRelationCacheKey]) async -> [PairRelationCacheKey: PairRelationCacheEntry] { [:] }
    func lookupScanRelationIndex(signature: String, mediaKind: MediaKind, algorithmVersion: String) async -> CachedScanRelationIndex? { nil }
    func upsertScanRelationIndex(signature: String, mediaKind: MediaKind, algorithmVersion: String, fileCount: Int, candidateCount: Int, relations: [CachedScanRelation]) async {}
    func detectMove(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, algorithmVersion: String) async -> String? { nil }
}

// MARK: - HashCache

/// SQLite 持久化哈希缓存, 使用 GRDB.swift 实现。
/// 数据库位置: ~/Library/Caches/Targie/hash_cache.sqlite
actor HashCache: HashCaching {
    private static let stalePruneTables = ["hash_cache", "media_metadata", "image_features", "frame_features"]
    private static let pruneInsertBatchSize = 500
    private static let cacheLookupBatchSize = 500

    private let dbQueue: DatabaseQueue
    private let databaseURL: URL

    init(databaseURL: URL? = nil) throws {
        let url = try databaseURL ?? Self.defaultDatabaseURL()
        self.databaseURL = url

        // 确保目录存在
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        self.dbQueue = try DatabaseQueue(path: url.path)
        try Self.runMigrations(on: dbQueue)
    }

    // MARK: - Public API

    func lookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, algorithmVersion: String) async -> CacheRecord? {
        // Primary lookup by path.
        if let primary = primaryCacheLookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt, mediaKind: mediaKind, algorithmVersion: algorithmVersion) {
            return primary
        }
        // Secondary lookup only after content identity proves the file moved.
        return await moveLookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt, mediaKind: mediaKind, algorithmVersion: algorithmVersion)
    }

    func lookupHashes(keys: [MediaHashCacheKey]) async -> [MediaHashCacheKey: CacheRecord] {
        guard !keys.isEmpty else { return [:] }
        return (try? await dbQueue.read { db in
            var results: [MediaHashCacheKey: CacheRecord] = [:]
            let keysByGroup = Dictionary(grouping: keys) { "\($0.mediaKind.rawValue)\u{0}\($0.algorithmVersion)" }
            for group in keysByGroup.values {
                guard let first = group.first else { continue }
                let keysByPath = Dictionary(grouping: group, by: \.filePath)
                let paths = Array(keysByPath.keys)
                for chunk in paths.chunked(size: Self.cacheLookupBatchSize) {
                    let records = try CacheRecord
                        .filter(chunk.contains(Column("filePath")))
                        .filter(Column("mediaKind") == first.mediaKind.rawValue)
                        .filter(Column("algorithmVersion") == first.algorithmVersion)
                        .fetchAll(db)
                    for record in records {
                        for key in keysByPath[record.filePath] ?? [] {
                            guard record.fileSize == key.fileSize,
                                  modifiedAtMatches(record.modifiedAt, key.modifiedAt)
                            else { continue }
                            results[key] = record
                        }
                    }
                }
            }
            return results
        }) ?? [:]
    }

    private func primaryCacheLookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, algorithmVersion: String) -> CacheRecord? {
        try? dbQueue.read { db in
            try CacheRecord
                .filter(Column("filePath") == filePath)
                .filter(Column("fileSize") == fileSize)
                .filter(Column("mediaKind") == mediaKind.rawValue)
                .filter(Column("algorithmVersion") == algorithmVersion)
                .fetchOne(db)
                .flatMap { record in
                    if modifiedAtMatches(record.modifiedAt, modifiedAt) { return record }
                    return nil
                }
        }
    }

    /// When a file moves to a different folder its old cache entry still exists under
    /// the previous path. Reuse it only when the old path is gone and a persisted
    /// SHA-256 proves the old cache record belongs to the current file.
    private func moveLookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, algorithmVersion: String) async -> CacheRecord? {
        let candidates = (try? await dbQueue.read { db in
            try CacheRecord
                .filter(Column("fileSize") == fileSize)
                .filter(Column("mediaKind") == mediaKind.rawValue)
                .filter(Column("algorithmVersion") == algorithmVersion)
                .filter(Column("filePath") != filePath)
                .order(Column("filePath"))
                .fetchAll(db)
        }) ?? []
        guard let candidate = await verifiedMovedRecord(
            candidates,
            to: filePath,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            mediaKind: mediaKind
        ) else { return nil }

        // Atomically relocate the record to the new path.
        try? await dbQueue.write { db in
            try db.execute(sql: "UPDATE hash_cache SET filePath = ? WHERE filePath = ?",
                           arguments: [filePath, candidate.filePath])
        }
        return CacheRecord(
            filePath: filePath,
            fileSize: candidate.fileSize,
            modifiedAt: candidate.modifiedAt,
            perceptualHash: candidate.perceptualHash,
            prehashDurationBucket: candidate.prehashDurationBucket,
            prehashSizeBucket: candidate.prehashSizeBucket,
            prehashAspectBucket: candidate.prehashAspectBucket,
            prehashThumbnailMean: candidate.prehashThumbnailMean,
            prehashThumbnailVariance: candidate.prehashThumbnailVariance,
            mediaKind: candidate.mediaKind,
            algorithmVersion: candidate.algorithmVersion
        )
    }

    // MARK: - Move Detection (read-only, for thumbnail migration)

    /// Read-only variant of move detection: returns the old path of a moved file
    /// WITHOUT updating any cache record.  Queries `media_metadata` (which has
    /// entries for *every* scanned file, not just those in candidate pairs) so
    /// thumbnail migration covers all files — not just similar ones. The move
    /// still requires stored SHA-256 proof; otherwise the caller should regenerate.
    /// `algorithmVersion` is ignored (metadata table has no concept of version);
    /// kept on the protocol for source compatibility.
    func detectMove(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, algorithmVersion: String) async -> String? {
        let candidates = (try? await dbQueue.read { db in
            try MediaMetadata
                .filter(Column("fileSize") == fileSize)
                .filter(Column("mediaKind") == mediaKind.rawValue)
                .filter(Column("filePath") != filePath)
                .order(Column("filePath"))
                .fetchAll(db)
        }) ?? []
        return await verifiedMovedRecord(
            candidates,
            to: filePath,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            mediaKind: mediaKind
        )?.filePath
    }

    func upsert(_ record: CacheRecord) {
        try? dbQueue.write { db in
            try record.save(db)  // GRDB save = INSERT OR UPDATE
        }
    }

    func pruneStale(validPaths: Set<String>) {
        try? dbQueue.write { db in
            guard !validPaths.isEmpty else {
                for table in Self.stalePruneTables {
                    try db.execute(sql: "DELETE FROM \(table)")
                }
                try db.execute(sql: "DELETE FROM pair_relations")
                try db.execute(sql: "DELETE FROM scan_relation_index_relations")
                try db.execute(sql: "DELETE FROM scan_relation_indexes")
                return
            }

            try db.execute(sql: """
                CREATE TEMP TABLE IF NOT EXISTS temp_valid_cache_paths (
                    filePath TEXT PRIMARY KEY
                )
                """)
            try db.execute(sql: "DELETE FROM temp_valid_cache_paths")

            let allValidPaths = Array(validPaths)
            for start in stride(from: 0, to: allValidPaths.count, by: Self.pruneInsertBatchSize) {
                let end = min(start + Self.pruneInsertBatchSize, allValidPaths.count)
                let chunk = allValidPaths[start..<end]
                let placeholders = Array(repeating: "(?)", count: chunk.count).joined(separator: ", ")
                try db.execute(
                    sql: "INSERT OR IGNORE INTO temp_valid_cache_paths (filePath) VALUES \(placeholders)",
                    arguments: StatementArguments(chunk)
                )
            }

            for table in Self.stalePruneTables {
                try db.execute(sql: """
                    DELETE FROM \(table)
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM temp_valid_cache_paths
                        WHERE temp_valid_cache_paths.filePath = \(table).filePath
                    )
                    """)
            }

            try db.execute(sql: """
                DELETE FROM pair_relations
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM temp_valid_cache_paths
                    WHERE temp_valid_cache_paths.filePath = pair_relations.firstPath
                )
                OR NOT EXISTS (
                    SELECT 1
                    FROM temp_valid_cache_paths
                    WHERE temp_valid_cache_paths.filePath = pair_relations.secondPath
                )
                """)

            try db.execute(sql: """
                DELETE FROM scan_relation_indexes
                WHERE EXISTS (
                    SELECT 1
                    FROM scan_relation_index_relations
                    WHERE scan_relation_index_relations.signature = scan_relation_indexes.signature
                    AND scan_relation_index_relations.mediaKind = scan_relation_indexes.mediaKind
                    AND scan_relation_index_relations.algorithmVersion = scan_relation_indexes.algorithmVersion
                    AND (
                        NOT EXISTS (
                            SELECT 1
                            FROM temp_valid_cache_paths
                            WHERE temp_valid_cache_paths.filePath = scan_relation_index_relations.firstPath
                        )
                        OR NOT EXISTS (
                            SELECT 1
                            FROM temp_valid_cache_paths
                            WHERE temp_valid_cache_paths.filePath = scan_relation_index_relations.secondPath
                        )
                    )
                )
                """)

            try db.execute(sql: """
                DELETE FROM scan_relation_index_relations
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM scan_relation_indexes
                    WHERE scan_relation_indexes.signature = scan_relation_index_relations.signature
                    AND scan_relation_indexes.mediaKind = scan_relation_index_relations.mediaKind
                    AND scan_relation_indexes.algorithmVersion = scan_relation_index_relations.algorithmVersion
                )
                """)

            try db.execute(sql: "DELETE FROM temp_valid_cache_paths")
        }
    }

    func count() -> Int {
        (try? dbQueue.read { db in try CacheRecord.fetchCount(db) }) ?? 0
    }

    /// Deletes every cached perceptual hash, metadata, and image feature.
    /// Next scan re-derives them.
    func clearAll() {
        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM hash_cache")
                try db.execute(sql: "DELETE FROM media_metadata")
                try db.execute(sql: "DELETE FROM image_features")
                try db.execute(sql: "DELETE FROM frame_features")
                try db.execute(sql: "DELETE FROM pair_relations")
                try db.execute(sql: "DELETE FROM scan_relation_index_relations")
                try db.execute(sql: "DELETE FROM scan_relation_indexes")
            }
            try dbQueue.vacuum()
        } catch {
            // Clear Cache is best-effort; scans can rebuild any missing data.
        }
    }

    func upsertMetadata(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, duration: Double?, width: Int?, height: Int?) async {
        try? await dbQueue.write { db in
            let sha256 = try String.fetchOne(
                db,
                sql: "SELECT sha256 FROM media_metadata WHERE filePath = ?",
                arguments: [filePath]
            )
            try MediaMetadata(
                filePath: filePath,
                fileSize: fileSize,
                modifiedAt: modifiedAt,
                duration: duration,
                width: width,
                height: height,
                mediaKind: mediaKind.rawValue,
                sha256: sha256
            ).save(db)
        }
    }

    func lookupMetadata(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) async -> (duration: Double?, width: Int?, height: Int?)? {
        // Primary path lookup.
        if let primary = primaryMetadataLookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt, mediaKind: mediaKind) {
            return primary
        }
        // Move support — only reuse after SHA-256 confirms content identity.
        return await moveMetadataLookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt, mediaKind: mediaKind)
    }

    func lookupMetadata(keys: [MediaMetadataCacheKey]) async -> [MediaMetadataCacheKey: MediaMetadataCacheEntry] {
        guard !keys.isEmpty else { return [:] }
        return (try? await dbQueue.read { db in
            var results: [MediaMetadataCacheKey: MediaMetadataCacheEntry] = [:]
            let keysByKind = Dictionary(grouping: keys, by: \.mediaKind)
            for (mediaKind, group) in keysByKind {
                let keysByPath = Dictionary(grouping: group, by: \.filePath)
                let paths = Array(keysByPath.keys)
                for chunk in paths.chunked(size: Self.cacheLookupBatchSize) {
                    let records = try MediaMetadata
                        .filter(chunk.contains(Column("filePath")))
                        .filter(Column("mediaKind") == mediaKind.rawValue)
                        .fetchAll(db)
                    for record in records {
                        for key in keysByPath[record.filePath] ?? [] {
                            guard record.fileSize == key.fileSize,
                                  modifiedAtMatches(record.modifiedAt, key.modifiedAt)
                            else { continue }
                            results[key] = MediaMetadataCacheEntry(duration: record.duration, width: record.width, height: record.height)
                        }
                    }
                }
            }
            return results
        }) ?? [:]
    }

    private func primaryMetadataLookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) -> (duration: Double?, width: Int?, height: Int?)? {
        try? dbQueue.read { db in
            guard let record = try MediaMetadata
                .filter(Column("filePath") == filePath)
                .filter(Column("fileSize") == fileSize)
                .filter(Column("mediaKind") == mediaKind.rawValue)
                .fetchOne(db),
                modifiedAtMatches(record.modifiedAt, modifiedAt)
            else { return nil }
            return (record.duration, record.width, record.height)
        }
    }

    private func moveMetadataLookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) async -> (duration: Double?, width: Int?, height: Int?)? {
        let candidates = (try? await dbQueue.read { db in
            try MediaMetadata
                .filter(Column("fileSize") == fileSize)
                .filter(Column("mediaKind") == mediaKind.rawValue)
                .filter(Column("filePath") != filePath)
                .order(Column("filePath"))
                .fetchAll(db)
        }) ?? []
        guard let candidate = await verifiedMovedRecord(
            candidates,
            to: filePath,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            mediaKind: mediaKind
        ) else { return nil }

        try? await dbQueue.write { db in
            try db.execute(sql: "UPDATE media_metadata SET filePath = ? WHERE filePath = ?",
                           arguments: [filePath, candidate.filePath])
        }
        return (candidate.duration, candidate.width, candidate.height)
    }

    // MARK: - SHA-256 Cache

    func upsertSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, sha256: String) async {
        try? await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO media_metadata (filePath, fileSize, modifiedAt, mediaKind, sha256)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(filePath) DO UPDATE SET
                    fileSize = excluded.fileSize,
                    modifiedAt = excluded.modifiedAt,
                    mediaKind = CASE
                        WHEN media_metadata.mediaKind = '' THEN excluded.mediaKind
                        ELSE media_metadata.mediaKind
                    END,
                    sha256 = excluded.sha256
                """, arguments: [filePath, fileSize, modifiedAt, mediaKind.rawValue, sha256])
        }
    }

    func lookupSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) async -> String? {
        // Primary path lookup.
        if let sha = primarySHA256Lookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt, mediaKind: mediaKind) {
            return sha
        }
        // Move support — only reuse after SHA-256 confirms content identity.
        return await moveSHA256Lookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt, mediaKind: mediaKind)
    }

    private func primarySHA256Lookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) -> String? {
        try? dbQueue.read { db in
            guard let record = try MediaMetadata
                .filter(Column("filePath") == filePath)
                .filter(Column("fileSize") == fileSize)
                .fetchOne(db),
                record.mediaKind.isEmpty || record.mediaKind == mediaKind.rawValue,
                modifiedAtMatches(record.modifiedAt, modifiedAt)
            else { return nil }
            return record.sha256
        }
    }

    private func moveSHA256Lookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) async -> String? {
        let candidates = (try? await dbQueue.read { db in
            try MediaMetadata
                .filter(Column("fileSize") == fileSize)
                .filter(Column("mediaKind") == mediaKind.rawValue)
                .filter(Column("filePath") != filePath)
                .order(Column("filePath"))
                .fetchAll(db)
        }) ?? []
        guard let candidate = await verifiedMovedRecord(
            candidates,
            to: filePath,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            mediaKind: mediaKind
        ), let sha = candidate.sha256, !sha.isEmpty else { return nil }

        try? await dbQueue.write { db in
            try db.execute(sql: "UPDATE media_metadata SET filePath = ? WHERE filePath = ?",
                           arguments: [filePath, candidate.filePath])
        }
        return sha
    }

    // MARK: - Image Feature Cache

    func upsertImageFeature(filePath: String, fileSize: Int64, modifiedAt: Date?, featureData: Data) async {
        try? await dbQueue.write { db in
            let record = ImageFeatureRecord(
                filePath: filePath,
                fileSize: fileSize,
                modifiedAt: modifiedAt,
                featureData: featureData
            )
            try record.save(db)
        }
    }

    func lookupImageFeature(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> Data? {
        // Primary path lookup.
        if let data = primaryImageFeatureLookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt) {
            return data
        }
        // Move support — only reuse after SHA-256 confirms content identity.
        return await moveImageFeatureLookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt)
    }

    private func primaryImageFeatureLookup(filePath: String, fileSize: Int64, modifiedAt: Date?) -> Data? {
        try? dbQueue.read { db in
            guard let record = try ImageFeatureRecord
                .filter(Column("filePath") == filePath)
                .filter(Column("fileSize") == fileSize)
                .fetchOne(db),
                modifiedAtMatches(record.modifiedAt, modifiedAt)
            else { return nil }
            return record.featureData
        }
    }

    private func moveImageFeatureLookup(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> Data? {
        let candidates = (try? await dbQueue.read { db in
            try ImageFeatureRecord
                .filter(Column("fileSize") == fileSize)
                .filter(Column("filePath") != filePath)
                .order(Column("filePath"))
                .fetchAll(db)
        }) ?? []
        guard let candidate = await verifiedMovedRecord(
            candidates,
            to: filePath,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            mediaKind: .image
        ) else { return nil }

        try? await dbQueue.write { db in
            try db.execute(sql: "UPDATE image_features SET filePath = ? WHERE filePath = ?",
                           arguments: [filePath, candidate.filePath])
        }
        return candidate.featureData
    }

    // MARK: - Frame Feature Cache

    func upsertFrameFeature(filePath: String, fileSize: Int64, modifiedAt: Date?, featureData: Data) async {
        try? await dbQueue.write { db in
            let record = FrameFeatureRecord(
                filePath: filePath,
                fileSize: fileSize,
                modifiedAt: modifiedAt,
                featureData: featureData
            )
            try record.save(db)
        }
    }

    func lookupFrameFeature(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> Data? {
        if let data = primaryFrameFeatureLookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt) {
            return data
        }
        return await moveFrameFeatureLookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt)
    }

    private func primaryFrameFeatureLookup(filePath: String, fileSize: Int64, modifiedAt: Date?) -> Data? {
        try? dbQueue.read { db in
            guard let record = try FrameFeatureRecord
                .filter(Column("filePath") == filePath)
                .filter(Column("fileSize") == fileSize)
                .fetchOne(db),
                modifiedAtMatches(record.modifiedAt, modifiedAt)
            else { return nil }
            return record.featureData
        }
    }

    private func moveFrameFeatureLookup(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> Data? {
        let candidates = (try? await dbQueue.read { db in
            try FrameFeatureRecord
                .filter(Column("fileSize") == fileSize)
                .filter(Column("filePath") != filePath)
                .order(Column("filePath"))
                .fetchAll(db)
        }) ?? []
        guard let candidate = await verifiedMovedRecord(
            candidates,
            to: filePath,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            mediaKind: .video
        ) else { return nil }

        try? await dbQueue.write { db in
            try db.execute(sql: "UPDATE frame_features SET filePath = ? WHERE filePath = ?",
                           arguments: [filePath, candidate.filePath])
        }
        return candidate.featureData
    }

    // MARK: - Pair Relation Cache

    func upsertPairRelation(first: MediaItem, second: MediaItem, algorithmVersion: String, relation: SimilarityRelation?) async {
        guard let identity = PairRelationCacheCodec.identity(first: first, second: second, algorithmVersion: algorithmVersion) else { return }
        let record = PairRelationCacheCodec.record(identity: identity, relation: relation)
        try? await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO pair_relations (
                    firstPath, secondPath, firstFileSize, secondFileSize,
                    firstModifiedAt, secondModifiedAt, mediaKind, algorithmVersion,
                    score, evidence
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(firstPath, secondPath, mediaKind, algorithmVersion) DO UPDATE SET
                    firstFileSize = excluded.firstFileSize,
                    secondFileSize = excluded.secondFileSize,
                    firstModifiedAt = excluded.firstModifiedAt,
                    secondModifiedAt = excluded.secondModifiedAt,
                    score = excluded.score,
                    evidence = excluded.evidence
                """, arguments: [
                    record.firstPath,
                    record.secondPath,
                    record.firstFileSize,
                    record.secondFileSize,
                    record.firstModifiedAt,
                    record.secondModifiedAt,
                    record.mediaKind,
                    record.algorithmVersion,
                    record.score,
                    record.evidence
                ])
        }
    }

    func lookupPairRelation(first: MediaItem, second: MediaItem, algorithmVersion: String) async -> PairRelationCacheEntry? {
        guard let identity = PairRelationCacheCodec.identity(first: first, second: second, algorithmVersion: algorithmVersion) else { return nil }
        return try? await dbQueue.read { db in
            guard let record = try PairRelationRecord
                .filter(Column("firstPath") == identity.firstPath)
                .filter(Column("secondPath") == identity.secondPath)
                .filter(Column("mediaKind") == identity.mediaKind.rawValue)
                .filter(Column("algorithmVersion") == identity.algorithmVersion)
                .fetchOne(db)
            else { return nil }
            return PairRelationCacheCodec.entry(record: record, identity: identity)
        }
    }

    func lookupPairRelations(keys: [PairRelationCacheKey]) async -> [PairRelationCacheKey: PairRelationCacheEntry] {
        guard !keys.isEmpty else { return [:] }
        return (try? await dbQueue.read { db in
            var results: [PairRelationCacheKey: PairRelationCacheEntry] = [:]
            let keysByGroup = Dictionary(grouping: keys) { "\($0.mediaKind.rawValue)\u{0}\($0.algorithmVersion)" }
            for group in keysByGroup.values {
                guard let first = group.first else { continue }
                let keysByLookupIdentity = Dictionary(grouping: group, by: Self.pairRelationLookupIdentity)
                let firstPaths = Array(Set(group.map(\.firstPath)))
                for chunk in firstPaths.chunked(size: Self.cacheLookupBatchSize) {
                    let records = try PairRelationRecord
                        .filter(chunk.contains(Column("firstPath")))
                        .filter(Column("mediaKind") == first.mediaKind.rawValue)
                        .filter(Column("algorithmVersion") == first.algorithmVersion)
                        .fetchAll(db)
                    for record in records {
                        let lookupIdentity = Self.pairRelationLookupIdentity(record)
                        for identity in keysByLookupIdentity[lookupIdentity] ?? [] {
                            guard let entry = PairRelationCacheCodec.entry(record: record, identity: identity) else { continue }
                            results[identity] = entry
                        }
                    }
                }
            }
            return results
        }) ?? [:]
    }

    func lookupScanRelationIndex(signature: String, mediaKind: MediaKind, algorithmVersion: String) async -> CachedScanRelationIndex? {
        try? await dbQueue.read { db in
            guard let record = try ScanRelationIndexRecord
                .filter(Column("signature") == signature)
                .filter(Column("mediaKind") == mediaKind.rawValue)
                .filter(Column("algorithmVersion") == algorithmVersion)
                .fetchOne(db)
            else { return nil }

            let relationRecords = try ScanRelationIndexRelationRecord
                .filter(Column("signature") == signature)
                .filter(Column("mediaKind") == mediaKind.rawValue)
                .filter(Column("algorithmVersion") == algorithmVersion)
                .order(Column("firstPath"), Column("secondPath"))
                .fetchAll(db)
            let relations = relationRecords.map {
                CachedScanRelation(
                    firstPath: $0.firstPath,
                    secondPath: $0.secondPath,
                    score: $0.score,
                    evidence: ScanRelationIndexCodec.decode($0.evidence)
                )
            }
            return CachedScanRelationIndex(
                signature: record.signature,
                mediaKind: mediaKind,
                algorithmVersion: record.algorithmVersion,
                fileCount: record.fileCount,
                candidateCount: record.candidateCount,
                relations: relations
            )
        }
    }

    func upsertScanRelationIndex(
        signature: String,
        mediaKind: MediaKind,
        algorithmVersion: String,
        fileCount: Int,
        candidateCount: Int,
        relations: [CachedScanRelation]
    ) async {
        let normalizedRelations = relations.map { ScanRelationIndexCodec.storedRelation($0) }
        let storedRelations = normalizedRelations.sorted { lhs, rhs in
            if lhs.firstPath == rhs.firstPath {
                return lhs.secondPath < rhs.secondPath
            }
            return lhs.firstPath < rhs.firstPath
        }
        try? await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO scan_relation_indexes (
                    signature, mediaKind, algorithmVersion, fileCount, candidateCount
                )
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(signature, mediaKind, algorithmVersion) DO UPDATE SET
                    fileCount = excluded.fileCount,
                    candidateCount = excluded.candidateCount,
                    createdAt = CURRENT_TIMESTAMP
                """, arguments: [
                    signature,
                    mediaKind.rawValue,
                    algorithmVersion,
                    fileCount,
                    candidateCount
                ])
            try db.execute(sql: """
                DELETE FROM scan_relation_index_relations
                WHERE signature = ?
                AND mediaKind = ?
                AND algorithmVersion = ?
                """, arguments: [signature, mediaKind.rawValue, algorithmVersion])
            for relation in storedRelations {
                try db.execute(sql: """
                    INSERT INTO scan_relation_index_relations (
                        signature, mediaKind, algorithmVersion,
                        firstPath, secondPath, score, evidence
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        signature,
                        mediaKind.rawValue,
                        algorithmVersion,
                        relation.firstPath,
                        relation.secondPath,
                        relation.score,
                        ScanRelationIndexCodec.encode(relation.evidence)
                    ])
            }
        }
    }

    // MARK: - Helpers

    private nonisolated func modifiedAtMatches(_ cached: Date?, _ current: Date?) -> Bool {
        if let a = cached, let b = current {
            return abs(a.timeIntervalSince(b)) < 1.0
        }
        return cached == nil && current == nil
    }

    private nonisolated func modifiedAtExactlyMatches(_ cached: Date?, _ current: Date?) -> Bool {
        cached == current
    }

    private nonisolated static func pairRelationLookupIdentity(_ key: PairRelationCacheKey) -> String {
        "\(key.firstPath)\u{0}\(key.secondPath)\u{0}\(key.mediaKind.rawValue)\u{0}\(key.algorithmVersion)"
    }

    private nonisolated static func pairRelationLookupIdentity(_ record: PairRelationRecord) -> String {
        "\(record.firstPath)\u{0}\(record.secondPath)\u{0}\(record.mediaKind)\u{0}\(record.algorithmVersion)"
    }

    private func verifiedMovedRecord<T: FilePathCacheRecord>(
        _ candidates: [T],
        to filePath: String,
        fileSize: Int64,
        modifiedAt: Date?,
        mediaKind: MediaKind
    ) async -> T? {
        let viable = candidates.filter {
            modifiedAtExactlyMatches($0.modifiedAt, modifiedAt) &&
            !FileManager.default.fileExists(atPath: $0.filePath)
        }
        guard !viable.isEmpty,
              let currentSHA = try? await FileHasher.sha256(of: URL(fileURLWithPath: filePath))
        else { return nil }

        for candidate in viable {
            guard let cachedSHA = cachedSHA256ForMove(
                oldPath: candidate.filePath,
                fileSize: fileSize,
                modifiedAt: modifiedAt,
                mediaKind: mediaKind
            ), cachedSHA == currentSHA else { continue }
            return candidate
        }
        return nil
    }

    private func cachedSHA256ForMove(oldPath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) -> String? {
        try? dbQueue.read { db in
            guard let record = try MediaMetadata
                .filter(Column("filePath") == oldPath)
                .filter(Column("fileSize") == fileSize)
                .filter(Column("mediaKind") == mediaKind.rawValue)
                .fetchOne(db),
                modifiedAtExactlyMatches(record.modifiedAt, modifiedAt),
                let sha = record.sha256,
                !sha.isEmpty
            else { return nil }
            return sha
        }
    }

    func sizeInBytes() -> Int64 {
        let size = (try? FileManager.default.attributesOfItem(atPath: databaseURL.path)[.size]) as? NSNumber
        return size?.int64Value ?? 0
    }

    // MARK: - Migrations

    private static func runMigrations(on dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_hash_cache") { db in
            try db.create(table: "hash_cache") { t in
                t.primaryKey("filePath", .text)
                t.column("fileSize", .integer).notNull()
                t.column("modifiedAt", .datetime)
                t.column("perceptualHash", .blob).notNull()
                t.column("prehashDurationBucket", .integer).notNull().defaults(to: 0)
                t.column("prehashSizeBucket", .integer).notNull().defaults(to: 0)
                t.column("prehashAspectBucket", .integer).notNull().defaults(to: 0)
                t.column("prehashThumbnailMean", .integer).notNull().defaults(to: 0)
                t.column("prehashThumbnailVariance", .integer).notNull().defaults(to: 0)
            }
        }
        migrator.registerMigration("v2_media_cache_identity") { db in
            try db.alter(table: "hash_cache") { table in
                table.add(column: "mediaKind", .text).notNull().defaults(to: MediaKind.video.rawValue)
                table.add(column: "algorithmVersion", .text).notNull().defaults(to: "video-dct3d-v1")
            }
        }
        migrator.registerMigration("v3_media_metadata") { db in
            try db.create(table: "media_metadata") { t in
                t.primaryKey("filePath", .text)
                t.column("fileSize", .integer).notNull()
                t.column("modifiedAt", .datetime)
                t.column("duration", .double)
                t.column("width", .integer)
                t.column("height", .integer)
                t.column("mediaKind", .text).notNull()
            }
        }
        migrator.registerMigration("v4_sha256_cache") { db in
            try db.alter(table: "media_metadata") { table in
                table.add(column: "sha256", .text)
            }
        }
        migrator.registerMigration("v5_image_features") { db in
            try db.create(table: "image_features") { t in
                t.primaryKey("filePath", .text)
                t.column("fileSize", .integer).notNull()
                t.column("modifiedAt", .datetime)
                t.column("featureData", .blob).notNull()
            }
        }
        migrator.registerMigration("v6_frame_features") { db in
            try db.create(table: "frame_features") { t in
                t.primaryKey("filePath", .text)
                t.column("fileSize", .integer).notNull()
                t.column("modifiedAt", .datetime)
                t.column("featureData", .blob).notNull()
            }
        }
        migrator.registerMigration("v7_pair_relations") { db in
            try db.execute(sql: """
                CREATE TABLE pair_relations (
                    firstPath TEXT NOT NULL,
                    secondPath TEXT NOT NULL,
                    firstFileSize INTEGER NOT NULL,
                    secondFileSize INTEGER NOT NULL,
                    firstModifiedAt DATETIME,
                    secondModifiedAt DATETIME,
                    mediaKind TEXT NOT NULL,
                    algorithmVersion TEXT NOT NULL,
                    score DOUBLE,
                    evidence TEXT NOT NULL DEFAULT '',
                    PRIMARY KEY (firstPath, secondPath, mediaKind, algorithmVersion)
                )
                """)
            try db.execute(sql: "CREATE INDEX pair_relations_firstPath_idx ON pair_relations(firstPath)")
            try db.execute(sql: "CREATE INDEX pair_relations_secondPath_idx ON pair_relations(secondPath)")
        }
        migrator.registerMigration("v8_scan_relation_indexes") { db in
            try db.execute(sql: """
                CREATE TABLE scan_relation_indexes (
                    signature TEXT NOT NULL,
                    mediaKind TEXT NOT NULL,
                    algorithmVersion TEXT NOT NULL,
                    fileCount INTEGER NOT NULL,
                    candidateCount INTEGER NOT NULL,
                    createdAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (signature, mediaKind, algorithmVersion)
                )
                """)
            try db.execute(sql: """
                CREATE TABLE scan_relation_index_relations (
                    signature TEXT NOT NULL,
                    mediaKind TEXT NOT NULL,
                    algorithmVersion TEXT NOT NULL,
                    firstPath TEXT NOT NULL,
                    secondPath TEXT NOT NULL,
                    score DOUBLE NOT NULL,
                    evidence TEXT NOT NULL DEFAULT '',
                    PRIMARY KEY (signature, mediaKind, algorithmVersion, firstPath, secondPath)
                )
                """)
        }
        try migrator.migrate(dbQueue)
    }

    // MARK: - Default Path

    private static func defaultDatabaseURL() throws -> URL {
        let cachesDir = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return cachesDir
            .appendingPathComponent("Targie", isDirectory: true)
            .appendingPathComponent("hash_cache.sqlite")
    }
}

private extension Array {
    func chunked(size: Int) -> [ArraySlice<Element>] {
        guard size > 0, !isEmpty else { return [] }
        return stride(from: 0, to: count, by: size).map { start in
            self[start..<Swift.min(start + size, count)]
        }
    }
}

// MARK: - Conversion Helpers

extension CacheRecord {
    /// 将 CacheRecord 还原为 VideoPerceptualHash (与 ID 关联)
    func toPerceptualHash(videoID: UUID) -> VideoPerceptualHash {
        VideoPerceptualHash(videoID: videoID, hashBits: Array(perceptualHash))
    }

    /// 还原为 QuickPrehash (与 ID 关联)
    func toQuickPrehash(videoID: UUID) -> QuickPrehash {
        QuickPrehash(
            videoID: videoID,
            durationBucket: prehashDurationBucket,
            sizeBucket: prehashSizeBucket,
            aspectBucket: prehashAspectBucket,
            thumbnailMean: UInt8(clamping: prehashThumbnailMean),
            thumbnailVariance: UInt16(clamping: prehashThumbnailVariance)
        )
    }

    /// 从一组数据构造 CacheRecord
    static func make(
        video: MediaItem,
        perceptualHash: VideoPerceptualHash,
        quickPrehash: QuickPrehash
    ) -> CacheRecord {
        CacheRecord(
            filePath: video.url.path,
            fileSize: video.fileSize,
            modifiedAt: video.modifiedAt,
            perceptualHash: Data(perceptualHash.hashBits),
            prehashDurationBucket: quickPrehash.durationBucket,
            prehashSizeBucket: quickPrehash.sizeBucket,
            prehashAspectBucket: quickPrehash.aspectBucket,
            prehashThumbnailMean: Int(quickPrehash.thumbnailMean),
            prehashThumbnailVariance: Int(quickPrehash.thumbnailVariance)
        )
    }
}

// MARK: - In-Memory Cache (for tests)

/// 测试用纯内存缓存替身, 与 SQLite 缓存接口一致。
actor InMemoryHashCache: HashCaching {
    private var storage: [String: CacheRecord] = [:]
    private var metadata: [String: (key: MediaMetadataCacheKey, entry: MediaMetadataCacheEntry)] = [:]
    private var sha256Store: [String: String] = [:]
    private var imageFeatures: [String: Data] = [:]
    private var frameFeatures: [String: Data] = [:]
    private var pairRelations: [PairRelationCacheKey: PairRelationRecord] = [:]
    private var scanRelationIndexes: [String: CachedScanRelationIndex] = [:]

    func lookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, algorithmVersion: String) -> CacheRecord? {
        guard let record = storage[filePath] else { return nil }
        guard record.fileSize == fileSize else { return nil }
        guard record.mediaKind == mediaKind.rawValue, record.algorithmVersion == algorithmVersion else { return nil }
        if let a = record.modifiedAt, let b = modifiedAt {
            return abs(a.timeIntervalSince(b)) < 1.0 ? record : nil
        }
        return record.modifiedAt == nil && modifiedAt == nil ? record : nil
    }

    func lookupHashes(keys: [MediaHashCacheKey]) -> [MediaHashCacheKey: CacheRecord] {
        var results: [MediaHashCacheKey: CacheRecord] = [:]
        for key in keys {
            guard let record = lookup(
                filePath: key.filePath,
                fileSize: key.fileSize,
                modifiedAt: key.modifiedAt,
                mediaKind: key.mediaKind,
                algorithmVersion: key.algorithmVersion
            ) else { continue }
            results[key] = record
        }
        return results
    }

    func upsert(_ record: CacheRecord) {
        storage[record.filePath] = record
    }

    func pruneStale(validPaths: Set<String>) {
        storage = storage.filter { validPaths.contains($0.key) }
        metadata = metadata.filter { validPaths.contains($0.key) }
        sha256Store = sha256Store.filter { validPaths.contains($0.key) }
        imageFeatures = imageFeatures.filter { validPaths.contains($0.key) }
        frameFeatures = frameFeatures.filter { validPaths.contains($0.key) }
        pairRelations = pairRelations.filter {
            validPaths.contains($0.key.firstPath) && validPaths.contains($0.key.secondPath)
        }
        scanRelationIndexes = scanRelationIndexes.filter { _, index in
            index.relations.allSatisfy {
                validPaths.contains($0.firstPath) && validPaths.contains($0.secondPath)
            }
        }
    }

    func count() -> Int { storage.count }

    func clearAll() { storage.removeAll(); metadata.removeAll(); sha256Store.removeAll(); imageFeatures.removeAll(); frameFeatures.removeAll(); pairRelations.removeAll(); scanRelationIndexes.removeAll() }

    func sizeInBytes() -> Int64 { 0 }

    func upsertMetadata(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, duration: Double?, width: Int?, height: Int?) async {
        let key = MediaMetadataCacheKey(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt, mediaKind: mediaKind)
        metadata[filePath] = (key, MediaMetadataCacheEntry(duration: duration, width: width, height: height))
    }

    func lookupMetadata(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) async -> (duration: Double?, width: Int?, height: Int?)? {
        guard let cached = metadata[filePath],
              cached.key.fileSize == fileSize,
              cached.key.mediaKind == mediaKind,
              datesMatch(cached.key.modifiedAt, modifiedAt)
        else { return nil }
        return (cached.entry.duration, cached.entry.width, cached.entry.height)
    }

    func lookupMetadata(keys: [MediaMetadataCacheKey]) -> [MediaMetadataCacheKey: MediaMetadataCacheEntry] {
        var results: [MediaMetadataCacheKey: MediaMetadataCacheEntry] = [:]
        for key in keys {
            guard let cached = metadata[key.filePath],
                  cached.key.fileSize == key.fileSize,
                  cached.key.mediaKind == key.mediaKind,
                  datesMatch(cached.key.modifiedAt, key.modifiedAt)
            else { continue }
            results[key] = cached.entry
        }
        return results
    }

    func upsertSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, sha256: String) async {
        sha256Store[filePath] = sha256
    }

    func lookupSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) async -> String? {
        sha256Store[filePath]
    }

    func upsertImageFeature(filePath: String, fileSize: Int64, modifiedAt: Date?, featureData: Data) async {
        imageFeatures[filePath] = featureData
    }

    func lookupImageFeature(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> Data? {
        imageFeatures[filePath]
    }

    func upsertFrameFeature(filePath: String, fileSize: Int64, modifiedAt: Date?, featureData: Data) async {
        frameFeatures[filePath] = featureData
    }

    func lookupFrameFeature(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> Data? {
        frameFeatures[filePath]
    }

    func upsertPairRelation(first: MediaItem, second: MediaItem, algorithmVersion: String, relation: SimilarityRelation?) async {
        guard let identity = PairRelationCacheCodec.identity(first: first, second: second, algorithmVersion: algorithmVersion) else { return }
        pairRelations[identity] = PairRelationCacheCodec.record(identity: identity, relation: relation)
    }

    func lookupPairRelation(first: MediaItem, second: MediaItem, algorithmVersion: String) async -> PairRelationCacheEntry? {
        guard let identity = PairRelationCacheCodec.identity(first: first, second: second, algorithmVersion: algorithmVersion),
              let record = pairRelations[identity]
        else { return nil }
        return PairRelationCacheCodec.entry(record: record, identity: identity)
    }

    func lookupPairRelations(keys: [PairRelationCacheKey]) -> [PairRelationCacheKey: PairRelationCacheEntry] {
        var results: [PairRelationCacheKey: PairRelationCacheEntry] = [:]
        for key in keys {
            guard let record = pairRelations[key],
                  let entry = PairRelationCacheCodec.entry(record: record, identity: key)
            else { continue }
            results[key] = entry
        }
        return results
    }

    func lookupScanRelationIndex(signature: String, mediaKind: MediaKind, algorithmVersion: String) -> CachedScanRelationIndex? {
        scanRelationIndexes[scanRelationIndexKey(signature: signature, mediaKind: mediaKind, algorithmVersion: algorithmVersion)]
    }

    func upsertScanRelationIndex(
        signature: String,
        mediaKind: MediaKind,
        algorithmVersion: String,
        fileCount: Int,
        candidateCount: Int,
        relations: [CachedScanRelation]
    ) {
        let normalizedRelations = relations.map { ScanRelationIndexCodec.storedRelation($0) }
        let storedRelations = normalizedRelations.sorted { lhs, rhs in
            if lhs.firstPath == rhs.firstPath {
                return lhs.secondPath < rhs.secondPath
            }
            return lhs.firstPath < rhs.firstPath
        }
        let index = CachedScanRelationIndex(
            signature: signature,
            mediaKind: mediaKind,
            algorithmVersion: algorithmVersion,
            fileCount: fileCount,
            candidateCount: candidateCount,
            relations: storedRelations
        )
        scanRelationIndexes[scanRelationIndexKey(signature: signature, mediaKind: mediaKind, algorithmVersion: algorithmVersion)] = index
    }

    func detectMove(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, algorithmVersion: String) -> String? { nil }

    private func scanRelationIndexKey(signature: String, mediaKind: MediaKind, algorithmVersion: String) -> String {
        "\(signature)\u{0}\(mediaKind.rawValue)\u{0}\(algorithmVersion)"
    }

    private func datesMatch(_ cached: Date?, _ current: Date?) -> Bool {
        if let a = cached, let b = current {
            return abs(a.timeIntervalSince(b)) < 1.0
        }
        return cached == nil && current == nil
    }
}
