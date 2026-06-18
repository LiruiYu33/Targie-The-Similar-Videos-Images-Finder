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
// but WITHOUT ANY WARRANTY; without even implied warranty of
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
final class BrowseViewModelTests: XCTestCase {

    private func makeItem(name: String, width: Int, height: Int, kind: MediaKind = .video) -> MediaItem {
        MediaItem(
            kind: kind,
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            fileSize: 1000,
            duration: kind == .video ? 10 : nil,
            width: width,
            height: height,
            modifiedAt: nil,
            thumbnailData: nil
        )
    }

    func testResolutionWidthSortAscendingOrdersByWidth() {
        let scanModel = ScanViewModel(hashCache: nil)
        scanModel.replaceResultsForTesting(
            items: [
                makeItem(name: "wide", width: 1920, height: 1080),
                makeItem(name: "narrow", width: 720, height: 1280),
                makeItem(name: "square", width: 1000, height: 1000)
            ],
            relations: []
        )
        let browse = BrowseViewModel(scanModel: scanModel)

        browse.sortField = .resolutionWidth
        browse.sortAscending = true

        let widths = browse.displayedItems.map(\.width)
        XCTAssertEqual(widths, [720, 1000, 1920])
    }

    func testResolutionHeightSortDescendingOrdersByHeight() {
        let scanModel = ScanViewModel(hashCache: nil)
        scanModel.replaceResultsForTesting(
            items: [
                makeItem(name: "wide", width: 1920, height: 1080),
                makeItem(name: "tall", width: 720, height: 1600),
                makeItem(name: "low", width: 400, height: 600)
            ],
            relations: []
        )
        let browse = BrowseViewModel(scanModel: scanModel)

        browse.sortField = .resolutionHeight
        browse.sortAscending = false

        let heights = browse.displayedItems.map(\.height)
        XCTAssertEqual(heights, [1600, 1080, 600])
    }

    func testToggleSortFlipsDirectionOnSameField() {
        let scanModel = ScanViewModel(hashCache: nil)
        scanModel.replaceResultsForTesting(
            items: [makeItem(name: "a", width: 300, height: 400), makeItem(name: "b", width: 500, height: 200)],
            relations: []
        )
        let browse = BrowseViewModel(scanModel: scanModel)

        browse.sortField = .resolutionWidth
        browse.sortAscending = true
        browse.toggleSort(field: .resolutionWidth) // flip to descending

        XCTAssertFalse(browse.sortAscending)
        XCTAssertEqual(browse.displayedItems.map(\.width), [500, 300])
    }

    func testClearResolutionSortResetsToNameAscending() {
        let scanModel = ScanViewModel(hashCache: nil)
        scanModel.replaceResultsForTesting(items: [makeItem(name: "a", width: 1, height: 1)], relations: [])
        let browse = BrowseViewModel(scanModel: scanModel)

        browse.sortField = .resolutionHeight
        browse.sortAscending = false
        browse.clearResolutionSort()

        XCTAssertEqual(browse.sortField, .name)
        XCTAssertTrue(browse.sortAscending)
    }

    func testResolutionFieldFlag() {
        XCTAssertTrue(BrowseViewModel.SortField.resolutionWidth.isResolution)
        XCTAssertTrue(BrowseViewModel.SortField.resolutionHeight.isResolution)
        XCTAssertFalse(BrowseViewModel.SortField.name.isResolution)
        XCTAssertFalse(BrowseViewModel.SortField.fileSize.isResolution)
        XCTAssertFalse(BrowseViewModel.SortField.modifiedTime.isResolution)
    }

    func testSearchTextFiltersDisplayedItemsByFilenameAndPath() {
        let scanModel = ScanViewModel(hashCache: nil)
        let holiday = MediaItem(
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/camera/HolidayClip.mov"),
            fileSize: 1000,
            duration: 10,
            width: 1920,
            height: 1080,
            modifiedAt: nil,
            thumbnailData: nil
        )
        let nested = MediaItem(
            kind: .video,
            url: URL(fileURLWithPath: "/tmp/client-project/raw/take.mov"),
            fileSize: 1000,
            duration: 10,
            width: 1920,
            height: 1080,
            modifiedAt: nil,
            thumbnailData: nil
        )
        let unrelated = makeItem(name: "notes.mov", width: 1920, height: 1080)
        scanModel.replaceResultsForTesting(items: [holiday, nested, unrelated], relations: [])
        let browse = BrowseViewModel(scanModel: scanModel)

        browse.searchText = "holiday"
        XCTAssertEqual(browse.displayedItems.map(\.id), [holiday.id])

        browse.searchText = "client-project"
        XCTAssertEqual(browse.displayedItems.map(\.id), [nested.id])
    }

    func testDeletingSelectedItemSelectsNextDisplayedItem() async throws {
        let first = makeItem(name: "a.mov", width: 1920, height: 1080)
        let second = makeItem(name: "b.mov", width: 1920, height: 1080)
        let third = makeItem(name: "c.mov", width: 1920, height: 1080)
        let scanModel = ScanViewModel(hashCache: nil)
        scanModel.replaceResultsForTesting(items: [first, second, third], relations: [])
        let browse = BrowseViewModel(scanModel: scanModel)
        browse.selectMedia(second.id)

        scanModel.removeItem(second.id)
        try await waitUntil { browse.displayedItems.map(\.id) == [first.id, third.id] }

        XCTAssertEqual(browse.primarySelectedID, third.id)
        XCTAssertEqual(browse.selectedMediaIDs, [third.id])
    }

    private func waitUntil(
        timeoutIterations: Int = 200,
        condition: () -> Bool
    ) async throws {
        for _ in 0..<timeoutIterations {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for browse state")
    }
}
