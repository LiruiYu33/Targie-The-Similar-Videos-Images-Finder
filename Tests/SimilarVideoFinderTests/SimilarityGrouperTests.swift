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

    func testDisconnectedComponentsReceiveOnlyTheirOwnRelations() {
        let componentCount = 200
        let pairs = (0..<componentCount).map { index in
            (
                SimilarityScoringTests.video(name: "\(index)-a.mov", size: Int64(index + 1)),
                SimilarityScoringTests.video(name: "\(index)-b.mov", size: Int64(index + 2))
            )
        }
        let items = pairs.flatMap { [$0.0, $0.1] }
        let relations = pairs.enumerated().map { index, pair in
            SimilarityRelation(
                firstID: pair.0.id,
                secondID: pair.1.id,
                score: 0.91 + (Double(index) / 100_000),
                evidence: [.similarSize]
            )
        }

        let groups = SimilarityGrouper.groups(items: items, relations: relations, threshold: 0.90)

        XCTAssertEqual(groups.count, componentCount)
        for group in groups {
            XCTAssertEqual(group.items.count, 2)
            XCTAssertEqual(group.relations.count, 1)
            XCTAssertEqual(Set(group.items.map(\.id)), [group.relations[0].firstID, group.relations[0].secondID])
        }
    }

    func testGroupOrderingUsesDeterministicTieBreaker() {
        let a = SimilarityScoringTests.video(name: "a.mov", size: 10)
        let b = SimilarityScoringTests.video(name: "b.mov", size: 20)
        let c = SimilarityScoringTests.video(name: "c.mov", size: 10)
        let d = SimilarityScoringTests.video(name: "d.mov", size: 20)
        let relations = [
            SimilarityRelation(firstID: a.id, secondID: b.id, score: 0.95, evidence: [.similarSize]),
            SimilarityRelation(firstID: c.id, secondID: d.id, score: 0.95, evidence: [.similarSize])
        ]

        let first = SimilarityGrouper.groups(items: [a, b, c, d], relations: relations, threshold: 0.90)
        let second = SimilarityGrouper.groups(items: [d, c, b, a], relations: relations.reversed(), threshold: 0.90)

        XCTAssertEqual(first.map { Set($0.items.map(\.id)) }, second.map { Set($0.items.map(\.id)) })
        XCTAssertEqual(first.map(\.maximumScore), second.map(\.maximumScore))
        XCTAssertEqual(first.map(\.reclaimableBytes), second.map(\.reclaimableBytes))
    }

    func testCancellableGroupingStopsWhenCurrentTaskIsCancelled() async {
        let first = SimilarityScoringTests.video(name: "cancel-a.mov")
        let second = SimilarityScoringTests.video(name: "cancel-b.mov")
        let relation = SimilarityRelation(
            firstID: first.id,
            secondID: second.id,
            score: 0.95,
            evidence: []
        )
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try SimilarityGrouper.cancellableGroups(
                items: [first, second],
                relations: [relation],
                threshold: 0.90
            )
        }

        do {
            _ = try await task.value
            XCTFail("Cancelled grouping should throw")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected grouping error: \(error)")
        }
    }
}
