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

import XCTest
@testable import SimilarVideoFinder

final class SidebarControlPlacementTests: XCTestCase {
    func testPrimaryControlsStayInStableTopOrder() {
        XCTAssertEqual(
            SidebarControlPlacement.primaryControls,
            [.scanAction, .addFolders, .clearFolders, .excludeSubfolders, .displayThreshold, .folderStatus]
        )
    }

    func testDynamicListsStayBelowPrimaryControls() {
        XCTAssertEqual(
            SidebarControlPlacement.auxiliaryControls,
            [.selectedFolderList, .skippedFiles]
        )
        XCTAssertFalse(SidebarControlPlacement.primaryControls.contains(.selectedFolderList))
    }

    func testFolderStatusStaysOnOneLineBelowThreshold() {
        XCTAssertEqual(SidebarControlPlacement.folderStatusLineLimit, 1)
    }

    func testTopActionButtonsShareShapeAndSizeConfiguration() {
        XCTAssertEqual(
            SidebarControlPlacement.actionButtonControls,
            [.scanAction, .addFolders, .clearFolders]
        )
        XCTAssertTrue(SidebarControlPlacement.actionButtonStyle.usesLargeControlSize)
        XCTAssertFalse(SidebarControlPlacement.actionButtonStyle.usesCustomBorderShape)
        XCTAssertFalse(SidebarControlPlacement.actionButtonStyle.forcesMinimumHeight)
    }

    func testClearFolderSelectionCopyDoesNotSoundLikeDiskDeletion() {
        XCTAssertEqual(L10n.clearFolders(.english), "Clear Folder Selection")
        XCTAssertEqual(L10n.clearFolders(.simplifiedChinese), "清除文件夹选择")
    }

    func testSkippedFilesScrollViewReachesPopoverEdge() {
        XCTAssertEqual(SkippedFilesPopoverLayout.scrollViewHorizontalInset, 0)
        XCTAssertGreaterThan(SkippedFilesPopoverLayout.contentTrailingPadding, 0)
    }
}
