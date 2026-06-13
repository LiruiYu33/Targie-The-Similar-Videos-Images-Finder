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

/// BK-Tree (Burkhard-Keller Tree): 基于 Hamming 距离等离散距离度量的近似匹配树结构。
/// 搜索复杂度 O(n·log n)，远优于 O(n²) 全量遍历。
/// 核心原理: 利用三角不等式, 如果 dist(query, root) = d，
/// 则距离 query <= maxDistance 的节点只可能在 children[d-maxDist..d+maxDist] 子树中。
struct BKTree<T> {
    private var root: BKNode<T>?

    /// 插入一个元素到树中
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

    /// 搜索所有与 query 的距离 <= maxDistance 的元素
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

        // 利用三角不等式: 只搜索 [d-maxDistance, d+maxDistance] 范围的子树
        let lowerBound = max(0, d - maxDistance)
        let upperBound = d + maxDistance

        for childDistance in lowerBound...upperBound where node.children[childDistance] != nil {
            searchIn(node: node.children[childDistance]!, query: query, maxDistance: maxDistance, distance: distance, results: &results)
        }
    }

    /// 搜索所有与 query 的距离 <= maxDistance 的元素 (仅返回 items, 不含距离)
    func searchItems(_ query: T, maxDistance: Int, distance: (T, T) -> Int) -> [T] {
        search(query, maxDistance: maxDistance, distance: distance).map { $0.item }
    }

    /// 树中元素总数
    var count: Int {
        countIn(node: root)
    }

    private func countIn(node: BKNode<T>?) -> Int {
        guard let node else { return 0 }
        return 1 + node.children.values.reduce(0) { $0 + countIn(node: $1) }
    }
}
