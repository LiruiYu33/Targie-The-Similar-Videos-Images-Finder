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

import AppKit
import CoreGraphics

/// How a rubber-band drag combines with the selection that existed when the
/// drag started. Mirrors Finder: plain drag replaces, ⇧ adds, ⌘ toggles.
enum MarqueeSelectionMode: Equatable, Sendable {
    case replace
    case add
    case toggle

    init(modifierFlags: NSEvent.ModifierFlags) {
        if modifierFlags.contains(.command) {
            self = .toggle
        } else if modifierFlags.contains(.shift) {
            self = .add
        } else {
            self = .replace
        }
    }

    func apply(hits: Set<UUID>, to base: Set<UUID>) -> Set<UUID> {
        switch self {
        case .replace: hits
        case .add: base.union(hits)
        case .toggle: base.symmetricDifference(hits)
        }
    }
}

enum MarqueeGeometry {
    /// The normalized rectangle spanned by a drag, whichever way it goes.
    static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    /// IDs whose frames touch the marquee; like Finder, partial overlap counts.
    static func hits(in rect: CGRect, frames: [UUID: CGRect]) -> Set<UUID> {
        Set(frames.compactMap { id, frame in frame.intersects(rect) ? id : nil })
    }

    /// Auto-scroll speed (points per tick) for a pointer `distance` points from
    /// the visible edge: zero outside the hot zone, faster the deeper it goes,
    /// and capped once the pointer leaves the view.
    static func autoScrollSpeed(distanceToEdge distance: CGFloat, zone: CGFloat = 36, maximum: CGFloat = 28) -> CGFloat {
        guard distance < zone else { return 0 }
        let depth = min(1.5, (zone - distance) / zone)
        return min(maximum, max(2, depth * maximum * 0.66))
    }
}
