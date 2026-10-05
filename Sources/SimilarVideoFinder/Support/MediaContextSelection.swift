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

enum MediaContextSelection {
    /// A right click inside the selection keeps the batch; outside it targets only that file.
    static func items(
        displayedItems: [MediaItem],
        selectedIDs: Set<UUID>,
        clickedID: UUID?,
        fallbackID: UUID?
    ) -> [MediaItem] {
        if let clickedID {
            guard let clicked = displayedItems.first(where: { $0.id == clickedID }) else { return [] }
            if !selectedIDs.contains(clickedID) { return [clicked] }
        }
        if !selectedIDs.isEmpty {
            return displayedItems.filter { selectedIDs.contains($0.id) }
        }
        return displayedItems.filter { $0.id == fallbackID }
    }
}
