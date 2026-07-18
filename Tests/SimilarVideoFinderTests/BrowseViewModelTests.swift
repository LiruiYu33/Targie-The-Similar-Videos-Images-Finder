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

import Combine
import XCTest
@testable import SimilarVideoFinder

@MainActor
final class BrowseViewModelTests: XCTestCase {

    private func makeItem(
        name: String,
        width: Int,
        height: Int,
        kind: MediaKind = .video,
        directory: String = "/tmp",
        fileSize: Int64 = 1000,
        modifiedAt: Date? = nil
    ) -> MediaItem {
        MediaItem(
            kind: kind,
            url: URL(fileURLWithPath: directory).appendingPathComponent(name),
            fileSize: fileSize,
            duration: kind == .video ? 10 : nil,
            width: width,
            height: height,
            modifiedAt: modifiedAt,
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

    func testLargeInitialBrowseComputesDefaultSortSynchronously() {
        let items = (0..<600).map { index in
            makeItem(
                name: String(format: "clip-%04d.mov", 600 - index),
                width: 1920,
                height: 1080
            )
        }
        let rawIDs = items.map(\.id)
        let sortedIDs = items
            .sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
            .map(\.id)
        XCTAssertNotEqual(rawIDs, sortedIDs)
        let scanModel = ScanViewModel(hashCache: nil)
        scanModel.replaceResultsForTesting(items: items, relations: [])

        let browse = BrowseViewModel(scanModel: scanModel)

        XCTAssertEqual(browse.displayedItems.map(\.id), sortedIDs)
    }

    func testProgressUpdateDoesNotRecomputeDisplayedItems() async throws {
        let scanModel = ScanViewModel(hashCache: nil)
        scanModel.replaceResultsForTesting(
            items: [makeItem(name: "a.mov", width: 1920, height: 1080)],
            relations: []
        )
        let browse = BrowseViewModel(scanModel: scanModel)
        let recomputeCount = browse.displayedItemsRecomputeCount

        scanModel.replaceProgressForTesting(ScanProgress(stage: .hashing, fraction: 0.5))
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(browse.displayedItemsRecomputeCount, recomputeCount)
    }

    func testThresholdUpdateDoesNotRecomputeDisplayedItems() async throws {
        let scanModel = ScanViewModel(hashCache: nil)
        scanModel.replaceResultsForTesting(
            items: [makeItem(name: "a.mov", width: 1920, height: 1080)],
            relations: []
        )
        let browse = BrowseViewModel(scanModel: scanModel)
        let recomputeCount = browse.displayedItemsRecomputeCount

        scanModel.threshold = 0.80
        try await Task.sleep(for: .milliseconds(180))

        XCTAssertEqual(browse.displayedItemsRecomputeCount, recomputeCount)
    }

    func testItemRevisionRecomputesDisplayedItemsOnce() async throws {
        let scanModel = ScanViewModel(hashCache: nil)
        let browse = BrowseViewModel(scanModel: scanModel)
        let recomputeCount = browse.displayedItemsRecomputeCount
        let item = makeItem(name: "a.mov", width: 1920, height: 1080)

        scanModel.replaceResultsForTesting(items: [item], relations: [])
        try await waitUntil { browse.displayedItems.map(\.id) == [item.id] }

        XCTAssertEqual(browse.displayedItemsRecomputeCount, recomputeCount + 1)
    }

    func testExcludeSubfoldersRecomputesBrowseItemsWithoutStartingScan() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseExcludeSubfolders-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let topLevel = makeItem(
            name: "top.mov",
            width: 1920,
            height: 1080,
            directory: root.path
        )
        let nestedItem = makeItem(
            name: "nested.mov",
            width: 1920,
            height: 1080,
            directory: nested.path
        )
        let scanModel = ScanViewModel(hashCache: nil)
        XCTAssertTrue(scanModel.addFolders([root]))
        scanModel.replaceResultsForTesting(items: [topLevel, nestedItem], relations: [])
        let browse = BrowseViewModel(scanModel: scanModel)
        let recomputeCount = browse.displayedItemsRecomputeCount

        XCTAssertEqual(Set(browse.displayedItems.map(\.id)), [topLevel.id, nestedItem.id])
        XCTAssertFalse(scanModel.isScanning)

        scanModel.excludeSubfolders = true
        try await waitUntil { browse.displayedItems.map(\.id) == [topLevel.id] }

        XCTAssertFalse(scanModel.isScanning)
        XCTAssertEqual(browse.displayedItemsRecomputeCount, recomputeCount + 1)

        scanModel.excludeSubfolders = false
        try await waitUntil {
            Set(browse.displayedItems.map(\.id)) == [topLevel.id, nestedItem.id]
        }

        XCTAssertFalse(scanModel.isScanning)
        XCTAssertEqual(browse.displayedItemsRecomputeCount, recomputeCount + 2)
    }

    func testEqualSortKeysUseDeterministicPathOrderInBothDirections() {
        let date = Date(timeIntervalSince1970: 1_000)
        let first = makeItem(
            name: "same.mov",
            width: 1920,
            height: 1080,
            directory: "/tmp/a",
            modifiedAt: date
        )
        let second = makeItem(
            name: "same.mov",
            width: 1920,
            height: 1080,
            directory: "/tmp/b",
            modifiedAt: date
        )
        let third = makeItem(
            name: "same.mov",
            width: 1920,
            height: 1080,
            directory: "/tmp/c",
            modifiedAt: date
        )
        let expected = [first.id, second.id, third.id]
        let scanModel = ScanViewModel(hashCache: nil)
        scanModel.replaceResultsForTesting(items: [third, first, second], relations: [])
        let browse = BrowseViewModel(scanModel: scanModel)

        for field in BrowseViewModel.SortField.allCases {
            browse.sortField = field
            browse.sortAscending = true
            XCTAssertEqual(browse.displayedItems.map(\.id), expected, "Ascending \(field)")

            browse.sortAscending = false
            XCTAssertEqual(browse.displayedItems.map(\.id), expected, "Descending \(field)")
        }
    }

    func testUnchangedOrderedIDsDoNotRepublishDisplayedItems() {
        let first = makeItem(name: "a.mov", width: 1920, height: 1080)
        let second = makeItem(name: "b.mov", width: 1920, height: 1080)
        let scanModel = ScanViewModel(hashCache: nil)
        scanModel.replaceResultsForTesting(items: [first, second], relations: [])
        let browse = BrowseViewModel(scanModel: scanModel)
        var publicationCount = 0
        let cancellable = browse.$displayedItems.dropFirst().sink { _ in
            publicationCount += 1
        }
        defer { cancellable.cancel() }

        browse.sortField = .fileSize

        XCTAssertEqual(browse.displayedItems.map(\.id), [first.id, second.id])
        XCTAssertEqual(publicationCount, 0)
    }

    func testSetSortUpdatesFieldAndDirectionWithOneRecompute() {
        let narrow = makeItem(name: "a.mov", width: 720, height: 1280)
        let wide = makeItem(name: "b.mov", width: 1920, height: 1080)
        let scanModel = ScanViewModel(hashCache: nil)
        scanModel.replaceResultsForTesting(items: [narrow, wide], relations: [])
        let browse = BrowseViewModel(scanModel: scanModel)
        let recomputeCount = browse.displayedItemsRecomputeCount

        browse.setSort(field: .resolutionWidth, ascending: false)

        XCTAssertEqual(browse.sortField, .resolutionWidth)
        XCTAssertFalse(browse.sortAscending)
        XCTAssertEqual(browse.displayedItems.map(\.id), [wide.id, narrow.id])
        XCTAssertEqual(browse.displayedItemsRecomputeCount, recomputeCount + 1)
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
