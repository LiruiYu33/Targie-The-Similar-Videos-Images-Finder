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

final class MarqueeSelectionTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()

    func testModifierFlagsMatchFinder() {
        XCTAssertEqual(MarqueeSelectionMode(modifierFlags: []), .replace)
        XCTAssertEqual(MarqueeSelectionMode(modifierFlags: .shift), .add)
        XCTAssertEqual(MarqueeSelectionMode(modifierFlags: .command), .toggle)
        XCTAssertEqual(MarqueeSelectionMode(modifierFlags: [.command, .shift]), .toggle)
    }

    func testModesCombineHitsWithStartingSelection() {
        XCTAssertEqual(MarqueeSelectionMode.replace.apply(hits: [b], to: [a]), [b])
        XCTAssertEqual(MarqueeSelectionMode.add.apply(hits: [b], to: [a]), [a, b])
        XCTAssertEqual(MarqueeSelectionMode.toggle.apply(hits: [a, b], to: [a, c]), [b, c])
    }

    func testRectIsNormalizedForEveryDragDirection() {
        let expected = CGRect(x: 10, y: 20, width: 30, height: 40)
        XCTAssertEqual(MarqueeGeometry.rect(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 40, y: 60)), expected)
        XCTAssertEqual(MarqueeGeometry.rect(from: CGPoint(x: 40, y: 60), to: CGPoint(x: 10, y: 20)), expected)
        XCTAssertEqual(MarqueeGeometry.rect(from: CGPoint(x: 40, y: 20), to: CGPoint(x: 10, y: 60)), expected)
    }

    func testPartialOverlapSelectsAndGapsDoNot() {
        let frames = [
            a: CGRect(x: 0, y: 0, width: 100, height: 100),
            b: CGRect(x: 120, y: 0, width: 100, height: 100),
            c: CGRect(x: 0, y: 120, width: 100, height: 100)
        ]
        XCTAssertEqual(MarqueeGeometry.hits(in: CGRect(x: 90, y: 10, width: 40, height: 10), frames: frames), [a, b])
        XCTAssertEqual(MarqueeGeometry.hits(in: CGRect(x: 102, y: 102, width: 15, height: 15), frames: frames), [])
    }

    func testAutoScrollOnlyNearEdgesAndAccelerates() {
        XCTAssertEqual(MarqueeGeometry.autoScrollSpeed(distanceToEdge: 100), 0)
        let shallow = MarqueeGeometry.autoScrollSpeed(distanceToEdge: 30)
        let deep = MarqueeGeometry.autoScrollSpeed(distanceToEdge: 2)
        let outside = MarqueeGeometry.autoScrollSpeed(distanceToEdge: -200)
        XCTAssertGreaterThan(shallow, 0)
        XCTAssertGreaterThan(deep, shallow)
        XCTAssertLessThanOrEqual(outside, 28)
    }

}
