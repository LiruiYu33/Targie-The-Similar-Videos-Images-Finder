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
import XCTest
@testable import SimilarVideoFinder

final class FinderShortcutTests: XCTestCase {
    private func match(_ keyCode: UInt16, _ characters: String?, _ flags: NSEvent.ModifierFlags, editing: Bool = false) -> FinderShortcut? {
        FinderShortcut.match(keyCode: keyCode, charactersIgnoringModifiers: characters, modifierFlags: flags, isEditingText: editing)
    }

    func testCommandFFocusesSearchRegardlessOfCapsLock() {
        XCTAssertEqual(match(3, "f", .command), .find)
        XCTAssertEqual(match(3, "F", [.command, .capsLock]), .find)
    }

    func testCommandDeleteMovesToTrashOnlyOutsideTextEditing() {
        XCTAssertEqual(match(51, "\u{7f}", .command), .moveToTrash)
        XCTAssertNil(match(51, "\u{7f}", .command, editing: true), "⌘⌫ deletes to line start while typing")
    }

    func testOtherModifierCombinationsPassThrough() {
        XCTAssertNil(match(3, "f", []))
        XCTAssertNil(match(3, "f", [.command, .shift]))
        XCTAssertNil(match(51, "\u{7f}", []))
        XCTAssertNil(match(51, "\u{7f}", [.command, .option]))
        XCTAssertNil(match(0, "a", .command))
    }

    private func returnAction(_ keyCode: UInt16 = 36, _ flags: NSEvent.ModifierFlags = [], repeat isRepeat: Bool = false, step: DeletePromptStep, after time: TimeInterval = 1) -> DeletePromptReturnKey.Action? {
        DeletePromptReturnKey.action(keyCode: keyCode, modifierFlags: flags, isRepeat: isRepeat, step: step, timeInStep: time)
    }

    func testReturnAsksForPermanentConfirmationThenConfirms() {
        XCTAssertEqual(returnAction(step: .choosingMethod, after: 0), .askForPermanentConfirmation)
        XCTAssertEqual(returnAction(step: .confirmingPermanent), .confirmPermanentDeletion)
        XCTAssertEqual(returnAction(76, [.numericPad], step: .confirmingPermanent), .confirmPermanentDeletion, "Keypad Enter works too")
    }

    func testPermanentDeletionNeedsADeliberateSecondPress() {
        XCTAssertNil(returnAction(step: .confirmingPermanent, after: 0.1), "A double press must not skip the confirmation")
        XCTAssertNil(returnAction(repeat: true, step: .confirmingPermanent), "Holding Return must not confirm")
        XCTAssertNil(returnAction(repeat: true, step: .choosingMethod))
    }

    func testModifiedReturnAndOtherKeysAreIgnored() {
        XCTAssertNil(returnAction(36, .command, step: .choosingMethod))
        XCTAssertNil(returnAction(49, step: .choosingMethod), "Space stays the Trash shortcut")
    }
}
