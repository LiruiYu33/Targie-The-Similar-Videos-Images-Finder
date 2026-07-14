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

import Foundation

enum SimilarityGrouper {
    static func groups(
        items: [MediaItem],
        relations: [SimilarityRelation],
        threshold: Double
    ) -> [SimilarityGroup] {
        buildGroups(
            items: items,
            relations: relations,
            threshold: threshold,
            cancellationCheck: {}
        )
    }

    static func cancellableGroups(
        items: [MediaItem],
        relations: [SimilarityRelation],
        threshold: Double
    ) throws -> [SimilarityGroup] {
        try buildGroups(
            items: items,
            relations: relations,
            threshold: threshold,
            cancellationCheck: { try Task.checkCancellation() }
        )
    }

    private static func buildGroups(
        items: [MediaItem],
        relations: [SimilarityRelation],
        threshold: Double,
        cancellationCheck: () throws -> Void
    ) rethrows -> [SimilarityGroup] {
        try cancellationCheck()
        var accepted: [SimilarityRelation] = []
        accepted.reserveCapacity(relations.count)
        for (index, relation) in relations.enumerated() {
            if index.isMultiple(of: 256) { try cancellationCheck() }
            if relation.score >= threshold { accepted.append(relation) }
        }

        var adjacency: [UUID: Set<UUID>] = [:]
        for (index, relation) in accepted.enumerated() {
            if index.isMultiple(of: 256) { try cancellationCheck() }
            adjacency[relation.firstID, default: []].insert(relation.secondID)
            adjacency[relation.secondID, default: []].insert(relation.firstID)
        }

        var byID: [UUID: MediaItem] = [:]
        byID.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            if index.isMultiple(of: 256) { try cancellationCheck() }
            byID[item.id] = item
        }
        var visited = Set<UUID>()
        var components: [Set<UUID>] = []
        var componentIndexByItemID: [UUID: Int] = [:]

        for (index, item) in items.enumerated() where !visited.contains(item.id) && adjacency[item.id] != nil {
            if index.isMultiple(of: 256) { try cancellationCheck() }
            var stack = [item.id]
            var component = Set<UUID>()
            var traversed = 0
            while let current = stack.popLast() {
                if traversed.isMultiple(of: 256) { try cancellationCheck() }
                traversed += 1
                guard visited.insert(current).inserted else { continue }
                component.insert(current)
                stack.append(contentsOf: adjacency[current, default: []])
            }
            let componentIndex = components.count
            components.append(component)
            for itemID in component {
                componentIndexByItemID[itemID] = componentIndex
            }
        }

        var relationBuckets = Array(repeating: [SimilarityRelation](), count: components.count)
        for (index, relation) in accepted.enumerated() {
            if index.isMultiple(of: 256) { try cancellationCheck() }
            guard
                let firstIndex = componentIndexByItemID[relation.firstID],
                firstIndex == componentIndexByItemID[relation.secondID]
            else { continue }
            relationBuckets[firstIndex].append(relation)
        }

        var result: [(group: SimilarityGroup, orderingKey: String)] = []
        result.reserveCapacity(components.count)
        for (index, component) in components.enumerated() {
            try cancellationCheck()
            let groupItems = component.compactMap { byID[$0] }.sorted {
                if $0.filename != $1.filename { return $0.filename < $1.filename }
                if $0.url.path != $1.url.path { return $0.url.path < $1.url.path }
                return $0.id.uuidString < $1.id.uuidString
            }
            guard groupItems.count >= 2 else { continue }
            // Similarity pipelines should not produce cross-media relations,
            // but the factory remains the final homogeneity guard.
            if let group = SimilarityGroup.make(items: groupItems, relations: relationBuckets[index]) {
                let orderingKey = groupItems.map { $0.id.uuidString }.min() ?? ""
                result.append((group, orderingKey))
            }
        }

        try cancellationCheck()
        return result.sorted {
            if $0.group.maximumScore != $1.group.maximumScore {
                return $0.group.maximumScore > $1.group.maximumScore
            }
            if $0.group.reclaimableBytes != $1.group.reclaimableBytes {
                return $0.group.reclaimableBytes > $1.group.reclaimableBytes
            }
            return $0.orderingKey < $1.orderingKey
        }.map(\.group)
    }
}
