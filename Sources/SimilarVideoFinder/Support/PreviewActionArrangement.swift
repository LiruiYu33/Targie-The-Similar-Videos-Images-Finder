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

enum PreviewActionKind: Hashable {
    case openDefaultPlayer
    case showInFinder
    case deleteFile
    case deleteSelection
}

enum PreviewActionArrangement {
    static func singleFileActions(includesOpenDefaultPlayer: Bool) -> [PreviewActionKind] {
        var actions: [PreviewActionKind] = []
        if includesOpenDefaultPlayer {
            actions.append(.openDefaultPlayer)
        }
        actions.append(.showInFinder)
        actions.append(.deleteFile)
        return actions
    }

    static func multipleSelectionActions() -> [PreviewActionKind] {
        [.showInFinder, .deleteSelection]
    }

    /// Splits actions into an optional full-width lead row (opening the file,
    /// the most common next step) and the rest, which share one row.
    static func rows(for actions: [PreviewActionKind]) -> (lead: PreviewActionKind?, shared: [PreviewActionKind]) {
        guard let lead = actions.first(where: { $0 == .openDefaultPlayer }) else {
            return (nil, actions)
        }
        return (lead, actions.filter { $0 != lead })
    }
}
