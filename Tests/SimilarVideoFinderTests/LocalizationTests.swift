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

final class LocalizationTests: XCTestCase {
    func testDefaultLanguageIsEnglishAndRawValuesRoundTrip() {
        XCTAssertEqual(AppLanguage.defaultLanguage, .english)
        XCTAssertEqual(AppLanguage(rawValue: "zh-Hans"), .simplifiedChinese)
    }

    func testRepresentativeStringsSwitchLanguage() {
        XCTAssertEqual(L10n.chooseFolder(.english), "Choose Folder")
        XCTAssertEqual(L10n.chooseFolder(.simplifiedChinese), "选择文件夹")
        XCTAssertEqual(L10n.skippedFiles(3, .english), "Skipped 3 unreadable files")
        XCTAssertEqual(L10n.skippedFiles(3, .simplifiedChinese), "跳过 3 个无法读取的文件")
        XCTAssertEqual(L10n.similarMedia(.english), "Similar Media")
        XCTAssertEqual(L10n.similarMedia(.simplifiedChinese), "相似媒体")
    }
}
