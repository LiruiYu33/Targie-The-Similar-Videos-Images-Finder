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

// MARK: - Media Kind & Scan Mode

/// 媒介种类: 视频或图片。SimilarityGroup 只允许同种媒介聚合。
enum MediaKind: String, Codable, Sendable, Hashable {
    case video
    case image
}

/// 扫描模式: 用户可选仅视频、仅图片、或全部。持久化到 UserDefaults 时使用 rawValue。
enum ScanMode: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case videos
    case images
    case all

    var id: String { rawValue }
}

// MARK: - MediaItem (统一视频与图片)

/// 媒介中立的扫描条目。视频用 `duration: Double?`, 图片用 `duration: nil`。
/// `kind` 是不可变标签, 用于禁止跨媒介相似度匹配。
struct MediaItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: MediaKind
    let url: URL
    let fileSize: Int64
    let duration: Double?
    let width: Int
    let height: Int
    let modifiedAt: Date?
    let thumbnailData: Data?

    init(
        id: UUID = UUID(),
        kind: MediaKind,
        url: URL,
        fileSize: Int64,
        duration: Double?,
        width: Int,
        height: Int,
        modifiedAt: Date?,
        thumbnailData: Data?
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.fileSize = fileSize
        self.duration = duration
        self.width = width
        self.height = height
        self.modifiedAt = modifiedAt
        self.thumbnailData = thumbnailData
    }

    var filename: String { url.lastPathComponent }

    func resolution(language: AppLanguage = .defaultLanguage) -> String {
        width > 0 && height > 0 ? "\(width) × \(height)" : L10n.unknown(language)
    }
}

// MARK: - Similarity Evidence

enum SimilarityEvidence: String, Hashable, Sendable {
    case identicalContentHash
    case similarPerceptualHash
    case similarFrames
    case similarDuration
    case similarDimensions
    case similarSize
    case similarName
}

// MARK: - SimilarityRelation

struct SimilarityRelation: Hashable, Sendable {
    let firstID: UUID
    let secondID: UUID
    let score: Double
    let evidence: Set<SimilarityEvidence>

    func contains(_ id: UUID) -> Bool { firstID == id || secondID == id }
}

// MARK: - SimilarityGroup

/// 同一组的所有 `items` 必须有相同 `MediaKind`。
/// 直接初始化器假设调用方已确保同质性 (供 grouping 算法内部使用);
/// 外部代码应使用 `SimilarityGroup.make(items:relations:)` 来安全构造。
struct SimilarityGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    let items: [MediaItem]
    let relations: [SimilarityRelation]

    init(id: UUID = UUID(), items: [MediaItem], relations: [SimilarityRelation]) {
        self.id = id
        self.items = items
        self.relations = relations
    }

    /// 工厂方法: 拒绝混合媒介组, 返回 nil 表示拒绝。
    /// 空列表也拒绝, 因为没有 kind 可推断。
    static func make(id: UUID = UUID(), items: [MediaItem], relations: [SimilarityRelation]) -> SimilarityGroup? {
        guard let firstKind = items.first?.kind else { return nil }
        guard items.allSatisfy({ $0.kind == firstKind }) else { return nil }
        return SimilarityGroup(id: id, items: items, relations: relations)
    }

    /// 组的媒介种类 (从首个条目推断; 直接初始化器调用方需确保同质)。
    var kind: MediaKind? { items.first?.kind }

    var maximumScore: Double { relations.map(\.score).max() ?? 0 }

    var reclaimableBytes: Int64 {
        guard items.count > 1 else { return 0 }
        return items.map(\.fileSize).sorted().dropFirst().reduce(0, +)
    }

    func score(for itemID: UUID) -> Double {
        relations.filter { $0.contains(itemID) }.map(\.score).max() ?? maximumScore
    }

    func evidence(for itemID: UUID) -> Set<SimilarityEvidence> {
        relations.filter { $0.contains(itemID) }.reduce(into: []) { $0.formUnion($1.evidence) }
    }
}

// MARK: - Scan Issue

enum ScanIssueReason: Hashable, Sendable {
    case noVideoTrack
    case unreadableImage
    case message(String)
}

struct ScanIssue: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    let reason: ScanIssueReason

    func message(language: AppLanguage) -> String {
        switch reason {
        case .noVideoTrack: L10n.noVideoTrack(language)
        case .unreadableImage: L10n.unreadableImage(language)
        case .message(let value): value
        }
    }
}

// MARK: - Scan Progress

enum ScanStage: Equatable, Sendable {
    case idle
    case discovering
    case readingMetadata
    case prehashing
    case hashing
    case comparing
    case completed
    case cancelled
}

struct ScanProgress: Equatable, Sendable {
    var stage: ScanStage = .idle
    var fraction: Double = 0
    var currentFile: String = ""
    var discoveredCount: Int = 0
}
