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

/// Media kind: video or image. `SimilarityGroup` only allows same-kind media.
enum MediaKind: String, Codable, Sendable, Hashable {
    case video
    case image
}

/// Scan mode: videos only, images only, or all. Uses `rawValue` for UserDefaults persistence.
enum ScanMode: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case videos
    case images
    case all

    var id: String { rawValue }
}

// MARK: - MediaItem (Unified Video and Image Model)

/// Media-neutral scan item. Videos use `duration: Double?`; images use `duration: nil`.
/// `kind` is an immutable tag that prevents cross-media similarity matching.
struct MediaItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: MediaKind
    let url: URL
    let fileSize: Int64
    let duration: Double?
    let width: Int
    let height: Int
    let modifiedAt: Date?
    private let embeddedThumbnailData: Data?
    let thumbnailURL: URL?

    init(
        id: UUID = UUID(),
        kind: MediaKind,
        url: URL,
        fileSize: Int64,
        duration: Double?,
        width: Int,
        height: Int,
        modifiedAt: Date?,
        thumbnailData: Data?,
        thumbnailURL: URL? = nil
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.fileSize = fileSize
        self.duration = duration
        self.width = width
        self.height = height
        self.modifiedAt = modifiedAt
        self.embeddedThumbnailData = thumbnailData
        self.thumbnailURL = thumbnailURL
    }

    var filename: String { url.lastPathComponent }
    /// Synchronous access is intentionally limited to embedded or already
    /// memory-cached bytes. Disk-backed thumbnails must use `loadThumbnailData()`.
    var thumbnailData: Data? {
        if let embeddedThumbnailData { return embeddedThumbnailData }
        return thumbnailURL.flatMap(ThumbnailStore.cachedData(at:))
    }

    func loadThumbnailData() async -> Data? {
        if let thumbnailData { return thumbnailData }
        guard let thumbnailURL else { return nil }
        return await ThumbnailStore.loadPersistedData(at: thumbnailURL)
    }
    var isThumbnailDiskBacked: Bool { embeddedThumbnailData == nil && thumbnailURL != nil }

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

/// Every item in a group must have the same `MediaKind`.
/// The direct initializer assumes callers already enforced homogeneity for grouping internals.
/// External code should use `SimilarityGroup.make(items:relations:)` for safe construction.
struct SimilarityGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    let items: [MediaItem]
    let relations: [SimilarityRelation]
    private let maximumScoreValue: Double
    private let reclaimableBytesValue: Int64
    private let scoresByItemID: [UUID: Double]
    private let evidenceByItemID: [UUID: Set<SimilarityEvidence>]

    init(id: UUID = UUID(), items: [MediaItem], relations: [SimilarityRelation]) {
        self.id = id
        self.items = items
        self.relations = relations

        let maximumScore = relations.lazy.map(\.score).max() ?? 0
        var scoresByItemID: [UUID: Double] = [:]
        var evidenceByItemID: [UUID: Set<SimilarityEvidence>] = [:]
        scoresByItemID.reserveCapacity(items.count)
        evidenceByItemID.reserveCapacity(items.count)
        for relation in relations {
            scoresByItemID[relation.firstID] = max(scoresByItemID[relation.firstID] ?? 0, relation.score)
            scoresByItemID[relation.secondID] = max(scoresByItemID[relation.secondID] ?? 0, relation.score)
            evidenceByItemID[relation.firstID, default: []].formUnion(relation.evidence)
            evidenceByItemID[relation.secondID, default: []].formUnion(relation.evidence)
        }

        self.maximumScoreValue = maximumScore
        self.reclaimableBytesValue = items.count > 1
            ? items.map(\.fileSize).sorted().dropFirst().reduce(0, +)
            : 0
        self.scoresByItemID = scoresByItemID
        self.evidenceByItemID = evidenceByItemID
    }

    /// Factory method: rejects mixed-media groups by returning nil.
    /// Empty groups are also rejected because there is no kind to infer.
    static func make(id: UUID = UUID(), items: [MediaItem], relations: [SimilarityRelation]) -> SimilarityGroup? {
        guard let firstKind = items.first?.kind else { return nil }
        guard items.allSatisfy({ $0.kind == firstKind }) else { return nil }
        return SimilarityGroup(id: id, items: items, relations: relations)
    }

    /// Group media kind, inferred from the first item; direct-initializer callers must enforce homogeneity.
    var kind: MediaKind? { items.first?.kind }

    var maximumScore: Double { maximumScoreValue }

    var reclaimableBytes: Int64 { reclaimableBytesValue }

    func score(for itemID: UUID) -> Double {
        scoresByItemID[itemID] ?? maximumScore
    }

    func evidence(for itemID: UUID) -> Set<SimilarityEvidence> {
        evidenceByItemID[itemID] ?? []
    }

    static func == (lhs: SimilarityGroup, rhs: SimilarityGroup) -> Bool {
        lhs.id == rhs.id && lhs.items == rhs.items && lhs.relations == rhs.relations
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(items)
        hasher.combine(relations)
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

enum ScanProgressCacheKind: Equatable, Sendable {
    case metadata
    case fingerprint
    case relation
}

enum ScanComparisonPhase: Equatable, Sendable {
    case findingCandidates
    case checkingPairCache
    case comparingUncached
}

struct ScanProgress: Equatable, Sendable {
    var stage: ScanStage = .idle
    var fraction: Double = 0
    var currentFile: String = ""
    var discoveredCount: Int = 0
    var cacheHits: Int = 0
    var cacheTotal: Int = 0
    var cacheKind: ScanProgressCacheKind?
    var comparisonPhase: ScanComparisonPhase?
    var comparisonCompleted: Int = 0
    var comparisonTotal: Int = 0
}

enum ScanProgressReporting {
    private static let maximumUpdates = 100

    static func shouldReport(completed: Int, total: Int) -> Bool {
        guard total > maximumUpdates else { return true }
        guard completed < total else { return true }
        if completed == 1 { return true }
        let interval = max(1, (total + maximumUpdates - 1) / maximumUpdates)
        return completed.isMultiple(of: interval)
    }
}
