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
import SwiftUI
import XCTest
@testable import SimilarVideoFinder

@MainActor
final class BrowseFilterPopoverTests: XCTestCase {
    func testPresetRemainsAppliedAfterManualFieldsClearAndSwiftUIUpdates() async {
        _ = NSApplication.shared
        let scanModel = ScanViewModel(hashCache: nil)
        let smaller = makeImage(name: "small.jpg", width: 640, height: 480)
        let larger = makeImage(name: "large.jpg", width: 1920, height: 1080)
        scanModel.replaceResultsForTesting(items: [smaller, larger], relations: [])
        let browse = BrowseViewModel(scanModel: scanModel)
        browse.setManualWidth("1920")
        browse.setManualHeight("1080")
        let initialRender = expectation(description: "popover renders existing manual dimensions")
        let clearedFieldsRender = expectation(description: "popover renders cleared manual dimensions")
        let host = NSHostingView(rootView: ObservedFilterPopover(browseModel: browse) { width in
            if width == "1920" { initialRender.fulfill() }
            if width.isEmpty { clearedFieldsRender.fulfill() }
        })
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        await fulfillment(of: [initialRender], timeout: 2)
        let recomputeCount = browse.displayedItemsRecomputeCount

        // The view must observe the old manual values before the preset action.
        // Otherwise the former onChange callbacks would never run in this test.
        let preset = BrowseViewModel.ResolutionPreset(id: "720p", label: "720p", shortEdge: 720)
        browse.setResolutionPreset(preset)
        host.layoutSubtreeIfNeeded()
        await fulfillment(of: [clearedFieldsRender], timeout: 2)

        XCTAssertEqual(browse.selectedResolutionPreset, preset)
        XCTAssertEqual(browse.manualWidth, "")
        XCTAssertEqual(browse.manualHeight, "")
        XCTAssertEqual(browse.displayedItems.map(\.id), [smaller.id])
        XCTAssertEqual(browse.displayedItemsRecomputeCount, recomputeCount + 1)
    }

    private func makeImage(name: String, width: Int, height: Int) -> MediaItem {
        MediaItem(
            kind: .image,
            url: URL(fileURLWithPath: "/tmp").appendingPathComponent(name),
            fileSize: 10,
            duration: nil,
            width: width,
            height: height,
            modifiedAt: nil,
            thumbnailData: nil
        )
    }
}

private struct ObservedFilterPopover: View {
    @ObservedObject var browseModel: BrowseViewModel
    let didRenderWidth: (String) -> Void

    var body: some View {
        BrowseFilterPopover(browseModel: browseModel, excludeSubfolders: .constant(false))
            .onChange(of: browseModel.manualWidth, initial: true) { _, width in
                didRenderWidth(width)
            }
    }
}
