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

import SwiftUI

struct GroupDetailView: View {
    @ObservedObject var model: ScanViewModel
    @Environment(\.appLanguage) private var language

    var body: some View {
        Group {
            if let group = model.selectedGroup {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n.compareVideos(language))
                                    .font(.title2.bold())
                                Text(L10n.compareHint(language))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(L10n.highestSimilarity(DisplayFormatters.percent(group.maximumScore), language))
                                .font(.callout.weight(.medium))
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                            ForEach(group.items) { video in
                                VideoCardView(
                                    video: video,
                                    score: group.score(for: video.id),
                                    evidence: group.evidence(for: video.id),
                                    language: language,
                                    isSelected: model.selectedMediaID == video.id
                                )
                                .onTapGesture { model.selectedMediaID = video.id }
                            }
                        }
                    }
                    .padding(20)
                }
            } else {
                ContentUnavailableView(
                    L10n.selectGroup(language),
                    systemImage: "rectangle.3.group",
                    description: Text(L10n.resultsOnLeft(language))
                )
            }
        }
        .navigationTitle(model.selectedGroup == nil ? L10n.videoComparison(language) : L10n.similarVideoCount(model.selectedGroup!.items.count, language))
    }
}
