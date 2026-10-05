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

@MainActor
final class MediaContextSelectionTests: XCTestCase {
    private func fixtures() -> [MediaItem] {
        ["a.mov", "b.mov", "c.mov"].map { SimilarityScoringTests.video(name: $0) }
    }

    func testRightClickInsideSelectionKeepsAllSelectedFiles() {
        let items = fixtures()
        let targets = MediaContextSelection.items(displayedItems: items, selectedIDs: [items[0].id, items[1].id], clickedID: items[1].id, fallbackID: items[0].id)
        XCTAssertEqual(targets.map(\.id), [items[0].id, items[1].id])
    }

    func testRightClickOutsideSelectionTargetsOnlyClickedFile() {
        let items = fixtures()
        let targets = MediaContextSelection.items(displayedItems: items, selectedIDs: [items[0].id, items[1].id], clickedID: items[2].id, fallbackID: items[0].id)
        XCTAssertEqual(targets.map(\.id), [items[2].id])
    }

    func testBackgroundMenuUsesCurrentBatchSelection() {
        let items = fixtures()
        let targets = MediaContextSelection.items(displayedItems: items, selectedIDs: [items[1].id, items[2].id], clickedID: nil, fallbackID: items[0].id)
        XCTAssertEqual(targets.map(\.id), [items[1].id, items[2].id])
    }

    func testSinglePreviewIsFallbackWithoutCheckedFiles() {
        let items = fixtures()
        let targets = MediaContextSelection.items(displayedItems: items, selectedIDs: [], clickedID: nil, fallbackID: items[1].id)
        XCTAssertEqual(targets.map(\.id), [items[1].id])
    }

    func testHiddenSelectedFileCannotBecomeDeletionTarget() {
        let items = fixtures()
        let targets = MediaContextSelection.items(displayedItems: Array(items.prefix(2)), selectedIDs: [items[2].id], clickedID: nil, fallbackID: items[0].id)
        XCTAssertTrue(targets.isEmpty)
    }

    func testRemovedClickedFileCannotDeleteTheRemainingSelection() {
        let items = fixtures()
        let targets = MediaContextSelection.items(displayedItems: Array(items.prefix(2)), selectedIDs: [items[0].id], clickedID: items[2].id, fallbackID: items[0].id)
        XCTAssertTrue(targets.isEmpty)
    }
}
