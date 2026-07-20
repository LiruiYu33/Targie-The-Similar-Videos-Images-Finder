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

final class MainToolbarPlacementTests: XCTestCase {
    func testMainToolbarIsScanModeBrowseThenSettings() throws {
        let source = try sourceText("Sources/SimilarVideoFinder/Views/ContentView.swift")
        let browse = try XCTUnwrap(source.range(of: "title: L10n.browse(language)"))
        let settings = try XCTUnwrap(source.range(of: "title: L10n.settings(language)"))

        // Settings must follow Browse in the toolbar, and be the only other
        // toolbar button beside the ScanMode picker.
        XCTAssertLessThan(browse.lowerBound, settings.lowerBound)

        // The infrequent controls used to be toolbar buttons; they must no
        // longer appear directly in ContentView's toolbar.
        XCTAssertFalse(source.contains("ToolbarLabeledPopover"))
        XCTAssertFalse(source.contains("title: L10n.clearCache(language)"))
        XCTAssertFalse(source.contains("title: L10n.scanIntensity(language)"))
        XCTAssertFalse(source.contains("title: L10n.language(language)"))

        // The Settings popover hosts them instead.
        let popover = try sourceText("Sources/SimilarVideoFinder/Views/SettingsPopover.swift")
        XCTAssertTrue(popover.contains("L10n.deepVerification(language)"))
        XCTAssertTrue(popover.contains("L10n.scanIntensity(language)"))
        XCTAssertTrue(popover.contains("L10n.language(language)"))
        XCTAssertTrue(popover.contains("onClearCache"))
    }

    func testDeepVerificationPreferenceFeedsScanViewModel() throws {
        let content = try sourceText("Sources/SimilarVideoFinder/Views/ContentView.swift")

        XCTAssertTrue(content.contains("@AppStorage(\"deepVerification\") private var deepVerification = false"))
        XCTAssertTrue(content.contains("model.setDeepVerification(deepVerification)"))
        XCTAssertTrue(content.contains(".onChange(of: deepVerification)"))
        XCTAssertTrue(content.contains("deepVerification: $deepVerification"))
    }

    func testBrowseToolbarDoesNotOwnClearCacheAction() throws {
        let source = try sourceText("Sources/SimilarVideoFinder/Views/BrowseView.swift")

        XCTAssertFalse(source.contains("L10n.clearCache(language)"))
        XCTAssertFalse(source.contains("clearAllCaches()"))
    }

    func testExcludeSubfoldersPreferenceBindingFeedsScanAndBrowseControls() throws {
        let content = try sourceText("Sources/SimilarVideoFinder/Views/ContentView.swift")
        let sidebar = try sourceText("Sources/SimilarVideoFinder/Views/SidebarView.swift")
        let browse = try sourceText("Sources/SimilarVideoFinder/Views/BrowseView.swift")
        let filter = try sourceText("Sources/SimilarVideoFinder/Views/BrowseFilterPopover.swift")

        XCTAssertTrue(content.contains("@AppStorage(\"excludeSubfolders\") private var excludeSubfolders"))
        XCTAssertTrue(content.contains("SidebarView(model: model, excludeSubfolders: $excludeSubfolders)"))
        XCTAssertTrue(content.contains("excludeSubfolders: $excludeSubfolders"))
        XCTAssertTrue(content.contains(".onChange(of: excludeSubfolders)"))

        XCTAssertTrue(sidebar.contains("@Binding var excludeSubfolders: Bool"))
        XCTAssertTrue(sidebar.contains("Toggle(isOn: $excludeSubfolders)"))
        XCTAssertFalse(sidebar.contains("Toggle(isOn: $model.excludeSubfolders)"))

        XCTAssertTrue(browse.contains("@Binding var excludeSubfolders: Bool"))
        XCTAssertTrue(browse.contains("BrowseFilterPopover("))
        XCTAssertTrue(filter.contains("@Binding var excludeSubfolders: Bool"))
        XCTAssertTrue(filter.contains("Toggle(isOn: $excludeSubfolders)"))
    }

    private func sourceText(_ relativePath: String) throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = testsDirectory.deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
