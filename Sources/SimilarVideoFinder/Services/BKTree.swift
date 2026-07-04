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

import Foundation

// MARK: - BK-Tree Node

struct BKNode<T> {
    let item: T
    var children: [Int: BKNode<T>]  // distance → subtree

    init(item: T) {
        self.item = item
        self.children = [:]
    }
}

// MARK: - BK-Tree

/// BK-Tree (Burkhard-Keller Tree): an approximate matching tree for discrete metrics such as Hamming distance.
/// Search complexity is O(n log n), much better than an O(n^2) full scan.
/// Core idea: using the triangle inequality, if dist(query, root) = d,
/// nodes within `maxDistance` of the query can only be in children[d-maxDist...d+maxDist].
struct BKTree<T> {
    private var root: BKNode<T>?

    /// Inserts an item into the tree.
    mutating func insert(_ item: T, distance: (T, T) -> Int) {
        if root == nil {
            root = BKNode(item: item)
            return
        }
        insertInto(node: &root!, item: item, distance: distance)
    }

    private func insertInto(node: inout BKNode<T>, item: T, distance: (T, T) -> Int) {
        let d = distance(node.item, item)
        if node.children[d] != nil {
            insertInto(node: &node.children[d]!, item: item, distance: distance)
        } else {
            node.children[d] = BKNode(item: item)
        }
    }

    /// Searches for all items whose distance from `query` is at most `maxDistance`.
    func search(_ query: T, maxDistance: Int, distance: (T, T) -> Int) -> [(item: T, dist: Int)] {
        guard let rootNode = root else { return [] }
        var results: [(item: T, dist: Int)] = []
        searchIn(node: rootNode, query: query, maxDistance: maxDistance, distance: distance, results: &results)
        return results
    }

    private func searchIn(
        node: BKNode<T>,
        query: T,
        maxDistance: Int,
        distance: (T, T) -> Int,
        results: inout [(item: T, dist: Int)]
    ) {
        let d = distance(node.item, query)
        if d <= maxDistance {
            results.append((node.item, d))
        }

        // Use the triangle inequality to only search children in [d-maxDistance, d+maxDistance].
        let lowerBound = max(0, d - maxDistance)
        let upperBound = d + maxDistance

        for childDistance in lowerBound...upperBound where node.children[childDistance] != nil {
            searchIn(node: node.children[childDistance]!, query: query, maxDistance: maxDistance, distance: distance, results: &results)
        }
    }

    /// Searches for all items whose distance from `query` is at most `maxDistance`, returning only items.
    func searchItems(_ query: T, maxDistance: Int, distance: (T, T) -> Int) -> [T] {
        search(query, maxDistance: maxDistance, distance: distance).map { $0.item }
    }

    /// Total number of items in the tree.
    var count: Int {
        countIn(node: root)
    }

    private func countIn(node: BKNode<T>?) -> Int {
        guard let node else { return 0 }
        return 1 + node.children.values.reduce(0) { $0 + countIn(node: $1) }
    }
}
