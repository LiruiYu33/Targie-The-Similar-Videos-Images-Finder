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

enum SidebarControlKind: Hashable {
    case addFolders
    case clearFolders
    case excludeSubfolders
    case folderStatus
    case scanAction
    case displayThreshold
    case selectedFolderList
    case skippedFiles
}

struct SidebarActionButtonStyle: Equatable {
    let usesLargeControlSize: Bool
    let usesCustomBorderShape: Bool
    let forcesMinimumHeight: Bool
}

enum SidebarControlPlacement {
    static let primaryControls: [SidebarControlKind] = [
        .scanAction,
        .addFolders,
        .clearFolders,
        .excludeSubfolders,
        .displayThreshold,
        .folderStatus
    ]

    static let auxiliaryControls: [SidebarControlKind] = [
        .selectedFolderList,
        .skippedFiles
    ]

    static let actionButtonControls: [SidebarControlKind] = [
        .scanAction,
        .addFolders,
        .clearFolders
    ]

    static let actionButtonStyle = SidebarActionButtonStyle(
        usesLargeControlSize: true,
        usesCustomBorderShape: false,
        forcesMinimumHeight: false
    )
    static let folderStatusLineLimit = 1
}
