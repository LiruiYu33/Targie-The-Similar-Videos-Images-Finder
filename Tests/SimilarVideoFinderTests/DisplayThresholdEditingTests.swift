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

final class DisplayThresholdEditingTests: XCTestCase {
    func testSliderValueSnapsToRecommendedThresholdFromEightyFourToEightyEightPercent() {
        XCTAssertEqual(DisplayThresholdEditing.sliderValue(for: 0.84), 0.88, accuracy: 0.0001)
        XCTAssertEqual(DisplayThresholdEditing.sliderValue(for: 0.85), 0.88, accuracy: 0.0001)
        XCTAssertEqual(DisplayThresholdEditing.sliderValue(for: 0.879), 0.88, accuracy: 0.0001)
        XCTAssertEqual(DisplayThresholdEditing.sliderValue(for: 0.88), 0.88, accuracy: 0.0001)
        XCTAssertEqual(DisplayThresholdEditing.sliderValue(for: 0.89), 0.89, accuracy: 0.0001)
        XCTAssertEqual(DisplayThresholdEditing.sliderValue(for: 0.839), 0.839, accuracy: 0.0001)
        XCTAssertEqual(DisplayThresholdEditing.sliderValue(for: 0.69), 0.69, accuracy: 0.0001)
    }

    func testManualInputDoesNotSnapInsideSliderMagnetRange() {
        assertParsedThreshold("85", equals: 0.85)
        assertParsedThreshold("87.5%", equals: 0.875)
    }

    @MainActor
    func testInitialScanThresholdMatchesRecommendedThreshold() {
        let model = ScanViewModel(hashCache: nil)

        XCTAssertEqual(DisplayThresholdEditing.recommendedThreshold, 0.88, accuracy: 0.0001)
        XCTAssertEqual(model.threshold, DisplayThresholdEditing.recommendedThreshold)
        XCTAssertEqual(DisplayThresholdEditing.text(for: model.threshold), "88")
    }

    func testThresholdHelpUsesRecommendedValueInEveryLanguage() {
        let recommendedText = DisplayThresholdEditing.text(for: DisplayThresholdEditing.recommendedThreshold)
        for language in AppLanguage.allCases {
            let help = L10n.displayThresholdHelp(language)
            XCTAssertTrue(help.contains(recommendedText), "Missing recommendation for \(language)")
            XCTAssertFalse(help.contains("72"), "Outdated recommendation for \(language)")
        }
        XCTAssertEqual(
            L10n.displayThresholdHelp(.simplifiedChinese),
            "建议从 \(recommendedText)% 开始；降低阈值会显示更多候选。分数不代表重复概率。"
        )
    }

    func testTextInputParsesPercentValuesAndClampsToAllowedRange() {
        assertParsedThreshold("72", equals: 0.72)
        assertParsedThreshold("72.5%", equals: 0.725)
        assertParsedThreshold("101", equals: 1.0)
        assertParsedThreshold("55", equals: 0.60)
    }

    func testTextInputRejectsInvalidValuesAndFormatsCurrentThreshold() {
        XCTAssertNil(DisplayThresholdEditing.thresholdValue(from: "abc"))
        XCTAssertNil(DisplayThresholdEditing.thresholdValue(from: ""))
        XCTAssertEqual(DisplayThresholdEditing.text(for: 0.72), "72")
        XCTAssertEqual(DisplayThresholdEditing.text(for: 0.725), "72.5")
    }

    func testTextInputStartsReadOnlyAndOnlyEditsAfterClick() {
        var state = DisplayThresholdTextEditState(threshold: 0.72)

        XCTAssertFalse(state.isEditing)
        XCTAssertEqual(state.displayText, "72")

        state.beginEditing()
        XCTAssertTrue(state.isEditing)
        XCTAssertEqual(state.editText, "72")

        state.commit("73.5")
        XCTAssertFalse(state.isEditing)
        XCTAssertEqual(state.threshold, 0.735, accuracy: 0.0001)

        state.beginEditing()
        state.cancelEditing()
        XCTAssertFalse(state.isEditing)
    }

    func testOutsideClickCommitsCurrentTextAndLeavesEditing() {
        var state = DisplayThresholdTextEditState(threshold: 0.72)
        state.beginEditing()
        state.editText = "74"

        state.commitCurrentText()

        XCTAssertFalse(state.isEditing)
        XCTAssertEqual(state.threshold, 0.74, accuracy: 0.0001)
    }

    private func assertParsedThreshold(
        _ text: String,
        equals expected: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let value = DisplayThresholdEditing.thresholdValue(from: text) else {
            XCTFail("Expected \(text) to parse", file: file, line: line)
            return
        }
        XCTAssertEqual(value, expected, accuracy: 0.0001, file: file, line: line)
    }
}
