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
        var result: [SimilarityGroup] = []

        for item in items where !visited.contains(item.id) && adjacency[item.id] != nil {
            var stack = [item.id]
            var component = Set<UUID>()
            while let current = stack.popLast() {
                guard visited.insert(current).inserted else { continue }
                component.insert(current)
                stack.append(contentsOf: adjacency[current, default: []])
            }
            let groupItems = component.compactMap { byID[$0] }.sorted { $0.filename < $1.filename }
            guard groupItems.count >= 2 else { continue }
            // 同质性保险: grouping 来源 (相似度流水线) 已确保不会跨媒介产生 relation,
            // 但作为防御层, 这里再用 SimilarityGroup.make 校验, 拒绝混合组。
            let componentRelations = accepted.filter {
                component.contains($0.firstID) && component.contains($0.secondID)
            }
            if let group = SimilarityGroup.make(items: groupItems, relations: componentRelations) {
                result.append(group)
            }
        }

        return result.sorted {
            if $0.maximumScore == $1.maximumScore { return $0.reclaimableBytes > $1.reclaimableBytes }
            return $0.maximumScore > $1.maximumScore
        }
    }
}
