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
        let accepted = relations.filter { $0.score >= threshold }
        var adjacency: [UUID: Set<UUID>] = [:]
        for relation in accepted {
            adjacency[relation.firstID, default: []].insert(relation.secondID)
            adjacency[relation.secondID, default: []].insert(relation.firstID)
        }

        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var visited = Set<UUID>()
        var components: [Set<UUID>] = []
        var componentIndexByItemID: [UUID: Int] = [:]

        for item in items where !visited.contains(item.id) && adjacency[item.id] != nil {
            var stack = [item.id]
            var component = Set<UUID>()
            while let current = stack.popLast() {
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
        for relation in accepted {
            guard
                let firstIndex = componentIndexByItemID[relation.firstID],
                firstIndex == componentIndexByItemID[relation.secondID]
            else { continue }
            relationBuckets[firstIndex].append(relation)
        }

        var result: [(group: SimilarityGroup, orderingKey: String)] = []
        result.reserveCapacity(components.count)
        for (index, component) in components.enumerated() {
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
