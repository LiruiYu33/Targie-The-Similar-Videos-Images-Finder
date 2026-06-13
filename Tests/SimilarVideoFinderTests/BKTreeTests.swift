// Targie — Find similar videos on macOS.
// Copyright (C) 2026 Lirui Yu
//
// This file is part of Targie.
//
// Targie is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// by the Free Software Foundation, either version 3 of the License, or
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

final class BKTreeTests: XCTestCase {

    // MARK: - Basic Insert & Search

    func testEmptyTreeSearchReturnsNothing() {
        let tree = BKTree<String>()
        let results = tree.search("hello", maxDistance: 1, distance: hammingStringDistance)
        XCTAssertEqual(results.count, 0)
    }

    func testSingleItemTreeSearchFindsExactMatch() {
        var tree = BKTree<String>()
        tree.insert("hello", distance: hammingStringDistance)

        let results = tree.search("hello", maxDistance: 0, distance: hammingStringDistance)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].item, "hello")
        XCTAssertEqual(results[0].dist, 0)
    }

    func testSingleItemTreeSearchDoesNotFindDistantMatch() {
        var tree = BKTree<String>()
        tree.insert("hello", distance: hammingStringDistance)

        let results = tree.search("world", maxDistance: 0, distance: hammingStringDistance)
        XCTAssertEqual(results.count, 0)
    }

    func testMultipleItemsSearchFindsNearMatches() {
        var tree = BKTree<String>()
        tree.insert("hello", distance: hammingStringDistance)
        tree.insert("hallo", distance: hammingStringDistance)  // 1 char diff
        tree.insert("hella", distance: hammingStringDistance)  // 1 char diff
        tree.insert("world", distance: hammingStringDistance)  // 5 char diff

        // 搜索与 "hello" Hamming 距离 <= 1 的字符串
        let results = tree.search("hello", maxDistance: 1, distance: hammingStringDistance)
        XCTAssertEqual(results.count, 3)  // hello (0), hallo (1), hella (1)

        let items = results.map { $0.item }
        XCTAssertTrue(items.contains("hello"))
        XCTAssertTrue(items.contains("hallo"))
        XCTAssertTrue(items.contains("hella"))
        XCTAssertFalse(items.contains("world"))
    }

    func testSearchWithMaxDistance2FindsMoreResults() {
        var tree = BKTree<String>()
        tree.insert("abc", distance: hammingStringDistance)
        tree.insert("abd", distance: hammingStringDistance)  // 1 diff
        tree.insert("abx", distance: hammingStringDistance)  // 1 diff
        tree.insert("axc", distance: hammingStringDistance)  // 1 diff
        tree.insert("xyz", distance: hammingStringDistance)  // 3 diff

        let results = tree.search("abc", maxDistance: 1, distance: hammingStringDistance)
        XCTAssertEqual(results.count, 4)  // abc(0), abd(1), abx(1), axc(1)
    }

    // MARK: - Count

    func testCountReturnsCorrectNumberOfItems() {
        var tree = BKTree<String>()
        XCTAssertEqual(tree.count, 0)

        tree.insert("one", distance: hammingStringDistance)
        XCTAssertEqual(tree.count, 1)

        tree.insert("two", distance: hammingStringDistance)
        XCTAssertEqual(tree.count, 2)

        tree.insert("three", distance: hammingStringDistance)
        XCTAssertEqual(tree.count, 3)
    }

    // MARK: - Hamming [UInt8] Distance Integration

    func testBKTreeWithByteHashes() {
        let hashA = VideoPerceptualHash(videoID: UUID(), hashBits: [0xFF, 0x00, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC])
        let hashB = VideoPerceptualHash(videoID: UUID(), hashBits: [0xFF, 0x00, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC])  // identical
        let hashC = VideoPerceptualHash(videoID: UUID(), hashBits: [0xFE, 0x00, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC])  // 1 bit diff
        let hashD = VideoPerceptualHash(videoID: UUID(), hashBits: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])  // very different

        var tree = BKTree<VideoPerceptualHash>()
        tree.insert(hashA, distance: { $0.hammingDistance(to: $1) })
        tree.insert(hashB, distance: { $0.hammingDistance(to: $1) })
        tree.insert(hashC, distance: { $0.hammingDistance(to: $1) })
        tree.insert(hashD, distance: { $0.hammingDistance(to: $1) })

        let results = tree.search(hashA, maxDistance: 1, distance: { $0.hammingDistance(to: $1) })
        XCTAssertEqual(results.count, 3)  // hashA(0), hashB(0), hashC(1)
    }

    func testBKTreeSearchDoesNotMissMatches() {
        // 确保三角不等式剪枝不会漏掉真实匹配
        let hashes = (0..<20).map { i in
            VideoPerceptualHash(
                videoID: UUID(),
                hashBits: [UInt8(i), UInt8(i * 2), UInt8(i * 3), 0, 0, 0, 0, 0]
            )
        }

        var tree = BKTree<VideoPerceptualHash>()
        for hash in hashes {
            tree.insert(hash, distance: { $0.hammingDistance(to: $1) })
        }

        // 用暴力搜索验证 BK-Tree 不漏结果
        let query = hashes[0]
        let maxDist = 5

        let treeResults = tree.search(query, maxDistance: maxDist, distance: { $0.hammingDistance(to: $1) })
        let bruteResults = hashes.filter { $0.hammingDistance(to: query) <= maxDist }

        XCTAssertEqual(treeResults.count, bruteResults.count)
        for result in treeResults {
            XCTAssertTrue(bruteResults.contains(where: { $0.videoID == result.item.videoID }))
        }
    }

    // MARK: - Helpers

    /// 简单字符 Hamming 距离 (逐字符比较)
    private func hammingStringDistance(_ a: String, _ b: String) -> Int {
        let charsA = Array(a)
        let charsB = Array(b)
        let _ = max(charsA.count, charsB.count)
        var distance = abs(charsA.count - charsB.count)
        for i in 0..<min(charsA.count, charsB.count) where charsA[i] != charsB[i] {
            distance += 1
        }
        return distance
    }
}
