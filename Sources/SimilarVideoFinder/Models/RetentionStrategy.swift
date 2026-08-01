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

/// Strategy for picking which file to keep in a similarity group when batch-deduplicating.
enum RetentionStrategy: String, CaseIterable, Identifiable, Sendable {
    case keepSmallest            // Keep the file with smallest byte size
    case keepLargest             // Keep the file with largest byte size
    case keepHighestResolution   // Keep the file with highest pixel count (width × height)
    case keepOldest              // Keep the file with earliest modification date
    case keepNewest              // Keep the file with latest modification date

    var id: String { rawValue }

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .keepSmallest: L10n.keepSmallest(language)
        case .keepLargest: L10n.keepLargest(language)
        case .keepHighestResolution: L10n.keepHighestResolution(language)
        case .keepOldest: L10n.keepOldest(language)
        case .keepNewest: L10n.keepNewest(language)
        }
    }

    /// Picks the keeper from an array of items. Returns nil when items are empty.
    /// When multiple items tie for the keeper position (e.g. same file size), the
    /// first-encountered item wins.
    func pickKeeper(from items: [MediaItem]) -> MediaItem? {
        guard !items.isEmpty else { return nil }
        return items.min(by: comparator)
    }

    private var comparator: (MediaItem, MediaItem) -> Bool {
        switch self {
        case .keepSmallest:         return { $0.fileSize < $1.fileSize }
        case .keepLargest:          return { $0.fileSize > $1.fileSize }
        case .keepHighestResolution: return { ($0.width * $0.height) > ($1.width * $1.height) }
        case .keepOldest:           return { ($0.modifiedAt ?? .distantFuture) < ($1.modifiedAt ?? .distantFuture) }
        case .keepNewest:           return { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
        }
    }
}