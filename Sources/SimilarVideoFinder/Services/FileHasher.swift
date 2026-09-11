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

enum FileHashError: Error, Equatable {
    case fileChangedDuringRead
}

enum FileHasher {
    private struct LiveIdentity: Equatable, Sendable {
        let fileSize: Int64
        let modifiedAt: Date?
    }

    static func sha256(of url: URL) async throws -> String {
        try await sha256(of: url, mediaKind: .video, cache: nil)
    }

    /// Cache-aware SHA-256 — checks the persistent cache before reading the file,
    /// and stores the result after computing.  Avoids re-reading every byte of
    /// same-size files on every re-scan.
    static func sha256(of url: URL, cache: (any HashCaching)?) async throws -> String {
        try await sha256(of: url, mediaKind: .video, cache: cache)
    }

    static func sha256(
        of url: URL,
        mediaKind: MediaKind,
        cache: (any HashCaching)?,
        afterReadingChunk: (@Sendable () async throws -> Void)? = nil
    ) async throws -> String {
        try Task.checkCancellation()
        let identity = try liveIdentity(of: url)
        if let cache {
            let cached = await cache.lookupSHA256(
                filePath: url.path,
                fileSize: identity.fileSize,
                modifiedAt: identity.modifiedAt,
                mediaKind: mediaKind
            )
            // Even a cache hit crosses an await: the source may have changed
            // while the lookup was pending.
            try Task.checkCancellation()
            try validate(identity, at: url)
            if let cached { return cached }
        }

        let hash = try await readStableSHA256(of: url, identity: identity, afterReadingChunk: afterReadingChunk)
        try Task.checkCancellation()
        try validate(identity, at: url)
        if let cache {
            await cache.upsertSHA256(
                filePath: url.path,
                fileSize: identity.fileSize,
                modifiedAt: identity.modifiedAt,
                mediaKind: mediaKind,
                sha256: hash
            )
            try Task.checkCancellation()
            try validate(identity, at: url)
        }
        return hash
    }

    private static func readStableSHA256(
        of url: URL,
        identity: LiveIdentity,
        afterReadingChunk: (@Sendable () async throws -> Void)?
    ) async throws -> String {
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            try validate(identity, at: url)
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while true {
                try Task.checkCancellation()
                guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { break }
                hasher.update(data: data)
                // A controlled boundary also lets tests exercise real file
                // changes and cancellation without depending on read timings.
                try await afterReadingChunk?()
            }
            try Task.checkCancellation()
            try validate(identity, at: url)
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
        return try await withTaskCancellationHandler {
            let hash = try await worker.value
            try Task.checkCancellation()
            return hash
        } onCancel: {
            worker.cancel()
        }
    }

    private static func liveIdentity(of url: URL) throws -> LiveIdentity {
        // FileManager reads the filesystem directly. Reusing resourceValues
        // on the scanner's URL would return its cached size and modification date.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber else {
            throw CocoaError(.fileReadUnknown)
        }
        return LiveIdentity(fileSize: size.int64Value, modifiedAt: attributes[.modificationDate] as? Date)
    }

    private static func validate(_ expected: LiveIdentity, at url: URL) throws {
        let current = try liveIdentity(of: url)
        guard shouldCacheSHA256(
            originalSize: expected.fileSize,
            originalModifiedAt: expected.modifiedAt,
            currentSize: current.fileSize,
            currentModifiedAt: current.modifiedAt
        ) else { throw FileHashError.fileChangedDuringRead }
    }

    /// Live stability checks retain full timestamp precision. Millisecond
    /// normalisation is only appropriate when comparing persisted cache dates.
    static func shouldCacheSHA256(
        originalSize: Int64,
        originalModifiedAt: Date?,
        currentSize: Int64,
        currentModifiedAt: Date?
    ) -> Bool {
        originalSize == currentSize
            && originalModifiedAt == currentModifiedAt
    }
}
