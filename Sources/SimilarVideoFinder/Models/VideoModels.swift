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

struct VideoItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let fileSize: Int64
    let duration: Double
    let width: Int
    let height: Int
    let modifiedAt: Date?
    let thumbnailData: Data?

    init(
        id: UUID = UUID(),
        url: URL,
        fileSize: Int64,
        duration: Double,
        width: Int,
        height: Int,
        modifiedAt: Date?,
        thumbnailData: Data?
    ) {
        self.id = id
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

enum SimilarityEvidence: String, Hashable, Sendable {
    case identicalContentHash
    case similarPerceptualHash
    case similarFrames
    case similarDuration
    case similarDimensions
    case similarSize
    case similarName

}

struct SimilarityRelation: Hashable, Sendable {
    let firstID: UUID
    let secondID: UUID
    let score: Double
    let evidence: Set<SimilarityEvidence>

    func contains(_ id: UUID) -> Bool { firstID == id || secondID == id }
}

struct SimilarityGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    let videos: [VideoItem]
    let relations: [SimilarityRelation]

    init(id: UUID = UUID(), videos: [VideoItem], relations: [SimilarityRelation]) {
        self.id = id
        self.videos = videos
        self.relations = relations
    }

    var maximumScore: Double { relations.map(\.score).max() ?? 0 }
    var reclaimableBytes: Int64 {
        guard videos.count > 1 else { return 0 }
        return videos.map(\.fileSize).sorted().dropFirst().reduce(0, +)
    }

    func score(for videoID: UUID) -> Double {
        relations.filter { $0.contains(videoID) }.map(\.score).max() ?? maximumScore
    }

    func evidence(for videoID: UUID) -> Set<SimilarityEvidence> {
        relations.filter { $0.contains(videoID) }.reduce(into: []) { $0.formUnion($1.evidence) }
    }
}

enum ScanIssueReason: Hashable, Sendable {
    case noVideoTrack
    case message(String)
}

struct ScanIssue: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    let reason: ScanIssueReason

    func message(language: AppLanguage) -> String {
        switch reason {
        case .noVideoTrack: L10n.noVideoTrack(language)
        case .message(let value): value
        }
    }
}

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
