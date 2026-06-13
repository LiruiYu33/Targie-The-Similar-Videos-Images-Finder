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

// MARK: - HashCache Protocol

/// 缓存接口 — 通过协议化便于测试时注入 InMemory 替身。
protocol HashCaching: Sendable {
    func lookup(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> CacheRecord?
    func upsert(_ record: CacheRecord) async
    func pruneStale(validPaths: Set<String>) async
    func count() async -> Int
    func lookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, algorithmVersion: String) async -> CacheRecord?
}

extension HashCaching {
    func lookup(filePath: String, fileSize: Int64, modifiedAt: Date?) async -> CacheRecord? {
        await lookup(filePath: filePath, fileSize: fileSize, modifiedAt: modifiedAt, mediaKind: .video, algorithmVersion: "video-dct3d-v1")
    }
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
        try? dbQueue.read { db in
            try CacheRecord
                .filter(Column("filePath") == filePath)
                .filter(Column("fileSize") == fileSize)
                .filter(Column("mediaKind") == mediaKind.rawValue)
                .filter(Column("algorithmVersion") == algorithmVersion)
                .fetchOne(db)
                .flatMap { record in
                    // 校验修改时间 (容差 1 秒, 兼容文件系统精度差异)
                    if let cached = record.modifiedAt, let current = modifiedAt {
                        return abs(cached.timeIntervalSince(current)) < 1.0 ? record : nil
                    }
                    // 两边都为 nil 视为匹配
                    if record.modifiedAt == nil && modifiedAt == nil { return record }
                    return nil
                }
        }
    }

    func upsert(_ record: CacheRecord) {
        try? dbQueue.write { db in
            try record.save(db)  // GRDB save = INSERT OR UPDATE
        }
    }

    func pruneStale(validPaths: Set<String>) {
        try? dbQueue.write { db in
            // 删除所有不在 validPaths 中的记录
            let validList = Array(validPaths)
            if validList.isEmpty {
                _ = try CacheRecord.deleteAll(db)
            } else {
                let placeholders = validList.map { _ in "?" }.joined(separator: ",")
                let sql = "DELETE FROM hash_cache WHERE filePath NOT IN (\(placeholders))"
                try db.execute(sql: sql, arguments: StatementArguments(validList))
            }
        }
    }

    func count() -> Int {
        (try? dbQueue.read { db in try CacheRecord.fetchCount(db) }) ?? 0
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
    }

    func count() -> Int { storage.count }
}
