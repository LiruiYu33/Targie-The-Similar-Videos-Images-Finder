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

    // Metadata cache — lets loadVideo / loadImage skip AVFoundation re-read on
    // re-scan when the file hasn't changed.
    func upsertMetadata(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, duration: Double?, width: Int?, height: Int?) async
    func lookupMetadata(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) async -> (duration: Double?, width: Int?, height: Int?)?

    // SHA-256 file hash cache — avoids re-reading every byte of same-size files
    // on every re-scan.
    func upsertSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?, sha256: String) async
    func lookupSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> String?

    // Image feature cache — persists VNFeaturePrintObservation so the comparing
    // phase skips Vision neural-network inference on re-scan.
    func upsertImageFeature(filePath: String, fileSize: Int64, modifiedAt: Date?, featureData: Data) async
    func lookupImageFeature(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> Data?
}

extension HashCaching {
    func lookup(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> CacheRecord? {
        await lookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt, mediaKind: .video, algorithmVersion: "video-dct3d-v1")
    }

    func upsertMetadata(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, duration: Double?, width: Int?, height: Int?) async {}
    func lookupMetadata(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) async -> (duration: Double?, width: Int?, height: Int?)? { nil }

    func upsertSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?, sha256: String) async {}
    func lookupSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> String? { nil }

    func upsertImageFeature(filePath: String, fileSize: Int64, modifiedAt: Date?, featureData: Data) async {}
    func lookupImageFeature(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> Data? { nil }
}

// MARK: - HashCache

/// SQLite 持久化哈希缓存, 使用 GRDB.swift 实现。
/// 数据库位置: ~/Library/Caches/Targie/hash_cache.sqlite
actor HashCache: HashCaching {
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

    func lookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, algorithmVersion: String) -> CacheRecord? {
        // Primary lookup by path.
        if let primary = primaryCacheLookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt, mediaKind: mediaKind, algorithmVersion: algorithmVersion) {
            return primary
        }
        // Secondary lookup by file properties — catches files moved to a new folder.
        return moveLookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt, mediaKind: mediaKind, algorithmVersion: algorithmVersion)
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
    /// the previous path.  Look for a record with matching (fileSize, modifiedAt, kind,
    /// algorithm) but a *different* filePath, and — critically — verify that the old
    /// path no longer exists on disk (otherwise it's a copy, not a move, and the cache
    /// must not be shared).  If found, atomically update the path so subsequent lookups
    /// hit the primary key directly.
    private func moveLookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, algorithmVersion: String) -> CacheRecord? {
        guard let candidate = try? dbQueue.read({ db in
            try CacheRecord
                .filter(Column("fileSize") == fileSize)
                .filter(Column("mediaKind") == mediaKind.rawValue)
                .filter(Column("algorithmVersion") == algorithmVersion)
                .filter(Column("filePath") != filePath)
                .fetchOne(db)
        }), modifiedAtMatches(candidate.modifiedAt, modifiedAt) else { return nil }

        // Only reuse when the old file is truly gone (moved, not copied).
        guard !FileManager.default.fileExists(atPath: candidate.filePath) else { return nil }

        // Atomically relocate the record to the new path.
        try? dbQueue.write { db in
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

    func upsert(_ record: CacheRecord) {
        try? dbQueue.write { db in
            try record.save(db)  // GRDB save = INSERT OR UPDATE
        }
    }

    func pruneStale(validPaths: Set<String>) {
        try? dbQueue.write { db in
            for table in ["hash_cache", "media_metadata", "image_features"] {
                let cachedPaths = try String.fetchAll(db, sql: "SELECT filePath FROM \(table)")
                for stalePath in cachedPaths where !validPaths.contains(stalePath) {
                    try db.execute(sql: "DELETE FROM \(table) WHERE filePath = ?", arguments: [stalePath])
                }
            }
        }
    }

    func count() -> Int {
        (try? dbQueue.read { db in try CacheRecord.fetchCount(db) }) ?? 0
    }

    /// Deletes every cached perceptual hash, metadata, and image feature.
    /// Next scan re-derives them.
    func clearAll() {
        try? dbQueue.write { db in
            try db.execute(sql: "DELETE FROM hash_cache")
            try db.execute(sql: "DELETE FROM media_metadata")
            try db.execute(sql: "DELETE FROM image_features")
        }
    }

    func upsertMetadata(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, duration: Double?, width: Int?, height: Int?) {
        try? dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO media_metadata (filePath, fileSize, modifiedAt, duration, width, height, mediaKind)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(filePath) DO UPDATE SET
                    fileSize = excluded.fileSize,
                    modifiedAt = excluded.modifiedAt,
                    duration = excluded.duration,
                    width = excluded.width,
                    height = excluded.height,
                    mediaKind = excluded.mediaKind
                """, arguments: [filePath, fileSize, modifiedAt, duration, width, height, mediaKind.rawValue])
        }
    }

    func lookupMetadata(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) -> (duration: Double?, width: Int?, height: Int?)? {
        // Primary path lookup.
        if let primary = primaryMetadataLookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt, mediaKind: mediaKind) {
            return primary
        }
        // Move support — file may have been relocated to a different folder.
        return moveMetadataLookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt, mediaKind: mediaKind)
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

    private func moveMetadataLookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) -> (duration: Double?, width: Int?, height: Int?)? {
        guard let candidate = try? dbQueue.read({ db in
            try MediaMetadata
                .filter(Column("fileSize") == fileSize)
                .filter(Column("mediaKind") == mediaKind.rawValue)
                .filter(Column("filePath") != filePath)
                .fetchOne(db)
        }), modifiedAtMatches(candidate.modifiedAt, modifiedAt),
              !FileManager.default.fileExists(atPath: candidate.filePath)
        else { return nil }

        try? dbQueue.write { db in
            try db.execute(sql: "UPDATE media_metadata SET filePath = ? WHERE filePath = ?",
                           arguments: [filePath, candidate.filePath])
        }
        return (candidate.duration, candidate.width, candidate.height)
    }

    // MARK: - SHA-256 Cache

    func upsertSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?, sha256: String) {
        try? dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO media_metadata (filePath, fileSize, modifiedAt, mediaKind, sha256)
                VALUES (?, ?, ?, '', ?)
                ON CONFLICT(filePath) DO UPDATE SET sha256 = excluded.sha256
                """, arguments: [filePath, fileSize, modifiedAt, sha256])
        }
    }

    func lookupSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?) -> String? {
        // Primary path lookup.
        if let sha = primarySHA256Lookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt) {
            return sha
        }
        // Move support.
        return moveSHA256Lookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt)
    }

    private func primarySHA256Lookup(filePath: String, fileSize: Int64, modifiedAt: Date?) -> String? {
        try? dbQueue.read { db in
            guard let record = try MediaMetadata
                .filter(Column("filePath") == filePath)
                .filter(Column("fileSize") == fileSize)
                .fetchOne(db),
                modifiedAtMatches(record.modifiedAt, modifiedAt)
            else { return nil }
            return record.sha256
        }
    }

    private func moveSHA256Lookup(filePath: String, fileSize: Int64, modifiedAt: Date?) -> String? {
        guard let candidate = try? dbQueue.read({ db in
            try MediaMetadata
                .filter(Column("fileSize") == fileSize)
                .filter(Column("filePath") != filePath)
                .fetchOne(db)
        }), let sha = candidate.sha256, !sha.isEmpty,
              modifiedAtMatches(candidate.modifiedAt, modifiedAt),
              !FileManager.default.fileExists(atPath: candidate.filePath)
        else { return nil }

        try? dbQueue.write { db in
            try db.execute(sql: "UPDATE media_metadata SET filePath = ? WHERE filePath = ?",
                           arguments: [filePath, candidate.filePath])
        }
        return sha
    }

    // MARK: - Image Feature Cache

    func upsertImageFeature(filePath: String, fileSize: Int64, modifiedAt: Date?, featureData: Data) {
        try? dbQueue.write { db in
            let record = ImageFeatureRecord(
                filePath: filePath,
                fileSize: fileSize,
                modifiedAt: modifiedAt,
                featureData: featureData
            )
            try record.save(db)
        }
    }

    func lookupImageFeature(filePath: String, fileSize: Int64, modifiedAt: Date?) -> Data? {
        // Primary path lookup.
        if let data = primaryImageFeatureLookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt) {
            return data
        }
        // Move support.
        return moveImageFeatureLookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt)
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

    private func moveImageFeatureLookup(filePath: String, fileSize: Int64, modifiedAt: Date?) -> Data? {
        guard let candidate = try? dbQueue.read({ db in
            try ImageFeatureRecord
                .filter(Column("fileSize") == fileSize)
                .filter(Column("filePath") != filePath)
                .fetchOne(db)
        }), modifiedAtMatches(candidate.modifiedAt, modifiedAt),
              !FileManager.default.fileExists(atPath: candidate.filePath)
        else { return nil }

        try? dbQueue.write { db in
            try db.execute(sql: "UPDATE image_features SET filePath = ? WHERE filePath = ?",
                           arguments: [filePath, candidate.filePath])
        }
        return candidate.featureData
    }

    // MARK: - Helpers

    private func modifiedAtMatches(_ cached: Date?, _ current: Date?) -> Bool {
        if let a = cached, let b = current {
            return abs(a.timeIntervalSince(b)) < 1.0
        }
        return cached == nil && current == nil
    }

    func sizeInBytes() -> Int64 {
        Int64((try? databaseURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
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
    private var metadata: [String: (duration: Double?, width: Int?, height: Int?)] = [:]
    private var sha256Store: [String: String] = [:]
    private var imageFeatures: [String: Data] = [:]

    func lookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, algorithmVersion: String) -> CacheRecord? {
        guard let record = storage[filePath] else { return nil }
        guard record.fileSize == fileSize else { return nil }
        guard record.mediaKind == mediaKind.rawValue, record.algorithmVersion == algorithmVersion else { return nil }
        if let a = record.modifiedAt, let b = modifiedAt {
            return abs(a.timeIntervalSince(b)) < 1.0 ? record : nil
        }
        return record.modifiedAt == nil && modifiedAt == nil ? record : nil
    }

    func upsert(_ record: CacheRecord) {
        storage[record.filePath] = record
    }

    func pruneStale(validPaths: Set<String>) {
        storage = storage.filter { validPaths.contains($0.key) }
        metadata = metadata.filter { validPaths.contains($0.key) }
        sha256Store = sha256Store.filter { validPaths.contains($0.key) }
        imageFeatures = imageFeatures.filter { validPaths.contains($0.key) }
    }

    func count() -> Int { storage.count }

    func clearAll() { storage.removeAll(); metadata.removeAll(); sha256Store.removeAll(); imageFeatures.removeAll() }

    func sizeInBytes() -> Int64 { 0 }

    func upsertMetadata(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, duration: Double?, width: Int?, height: Int?) async {
        metadata[filePath] = (duration, width, height)
    }

    func lookupMetadata(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) async -> (duration: Double?, width: Int?, height: Int?)? {
        metadata[filePath]
    }

    func upsertSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?, sha256: String) async {
        sha256Store[filePath] = sha256
    }

    func lookupSHA256(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> String? {
        sha256Store[filePath]
    }

    func upsertImageFeature(filePath: String, fileSize: Int64, modifiedAt: Date?, featureData: Data) async {
        imageFeatures[filePath] = featureData
    }

    func lookupImageFeature(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> Data? {
        imageFeatures[filePath]
    }
}
