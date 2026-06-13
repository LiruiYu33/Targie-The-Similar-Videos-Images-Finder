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

final class SimilarityGrouperTests: XCTestCase {
    func testChainRelationsFormOneGroup() {
        let a = SimilarityScoringTests.video(name: "a.mov")
        let b = SimilarityScoringTests.video(name: "b.mov")
        let c = SimilarityScoringTests.video(name: "c.mov")
        let groups = SimilarityGrouper.groups(
            items: [a, b, c],
            relations: [
                SimilarityRelation(firstID: a.id, secondID: b.id, score: 0.94, evidence: []),
                SimilarityRelation(firstID: b.id, secondID: c.id, score: 0.91, evidence: [])
            ],
            threshold: 0.90
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].items.map(\.id)), Set([a.id, b.id, c.id]))
    }

    func testRemovingVideoDropsSingletonGroup() {
        let a = SimilarityScoringTests.video(name: "a.mov")
        XCTAssertTrue(SimilarityGrouper.groups(items: [a], relations: [], threshold: 0.90).isEmpty)
    }
}
