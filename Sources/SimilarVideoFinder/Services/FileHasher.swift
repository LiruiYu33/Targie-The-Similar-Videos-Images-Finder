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

enum FileHasher {
    static func sha256(of url: URL) async throws -> String {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while true {
                try Task.checkCancellation()
                guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { break }
                hasher.update(data: data)
            }
            try Task.checkCancellation()
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// Cache-aware SHA-256 — checks the persistent cache before reading the file,
    /// and stores the result after computing.  Avoids re-reading every byte of
    /// same-size files on every re-scan.
    static func sha256(of url: URL, cache: (any HashCaching)?) async throws -> String {
        try await sha256(of: url, mediaKind: .video, cache: cache)
    }

    static func sha256(of url: URL, mediaKind: MediaKind, cache: (any HashCaching)?) async throws -> String {
        guard let cache else { return try await sha256(of: url) }

        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize = Int64(values.fileSize ?? 0)
        let modifiedAt = values.contentModificationDate

        if let cached = await cache.lookupSHA256(filePath: url.path, fileSize: fileSize, modifiedAt: modifiedAt, mediaKind: mediaKind) {
            return cached
        }
        let hash = try await sha256(of: url)
        // Re-read attributes after hashing. If the file changed during the
        // (potentially multi-second) read, the computed hash corresponds to
        // unknown intermediate content and must not be cached under the stale
        // pre-read attributes - that would poison the cache with a wrong hash.
        let postValues = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        if Self.shouldCacheSHA256(
            originalSize: fileSize,
            originalModifiedAt: modifiedAt,
            currentSize: Int64(postValues.fileSize ?? 0),
            currentModifiedAt: postValues.contentModificationDate
        ) {
            await cache.upsertSHA256(filePath: url.path, fileSize: fileSize, modifiedAt: modifiedAt, mediaKind: mediaKind, sha256: hash)
        }
        return hash
    }

    /// Whether a freshly-computed hash is safe to cache: only when the file's
    /// size and modification date are unchanged between the pre-read (which
    /// keyed the cache lookup) and the post-hash read. Extracted so the
    /// decision is unit-testable without racing real filesystem I/O.
    static func shouldCacheSHA256(
        originalSize: Int64,
        originalModifiedAt: Date?,
        currentSize: Int64,
        currentModifiedAt: Date?
    ) -> Bool {
        originalSize == currentSize
            && FileCacheIdentity.modifiedAtMatches(originalModifiedAt, currentModifiedAt)
    }
}
