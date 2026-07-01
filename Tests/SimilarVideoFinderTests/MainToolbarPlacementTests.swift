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
    func testClearCacheLivesInMainToolbarBetweenBrowseAndLanguage() throws {
        let source = try sourceText("Sources/SimilarVideoFinder/Views/ContentView.swift")
        let browse = try XCTUnwrap(source.range(of: "title: L10n.browse(language)"))
        let clearCache = try XCTUnwrap(source.range(of: "title: L10n.clearCache(language)"))
        let language = try XCTUnwrap(source.range(of: "title: L10n.language(language)"))

        XCTAssertLessThan(browse.lowerBound, clearCache.lowerBound)
        XCTAssertLessThan(clearCache.lowerBound, language.lowerBound)
        XCTAssertTrue(source.contains(".disabled(model.isScanning)"))
    }

    func testBrowseToolbarDoesNotOwnClearCacheAction() throws {
        let source = try sourceText("Sources/SimilarVideoFinder/Views/BrowseView.swift")

        XCTAssertFalse(source.contains("L10n.clearCache(language)"))
        XCTAssertFalse(source.contains("clearAllCaches()"))
    }

    private func sourceText(_ relativePath: String) throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = testsDirectory.deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
