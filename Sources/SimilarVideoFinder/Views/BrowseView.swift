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

struct BrowseView: View {
    @ObservedObject var browseModel: BrowseViewModel
    let onBack: () -> Void
    @Environment(\.appLanguage) private var language

    var body: some View {
        NavigationSplitView {
            Color.clear
                .frame(width: 0)
                .navigationSplitViewColumnWidth(min: 0, ideal: 0, max: 0)
        } content: {
            BrowseTableView(browseModel: browseModel)
                .navigationSplitViewColumnWidth(min: 400, ideal: 700)
        } detail: {
            BrowsePreviewPanel(browseModel: browseModel)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 450)
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: onBack) {
                    Label(L10n.back(language), systemImage: "chevron.left")
                }

                Button {
                    browseModel.isFilterPresented.toggle()
                } label: {
                    if browseModel.hasActiveFilter {
                        Label(L10n.filter(language), systemImage: "line.3.horizontal.decrease.circle.fill")
                    } else {
                        Label(L10n.filter(language), systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                .popover(isPresented: $browseModel.isFilterPresented) {
                    BrowseFilterPopover(browseModel: browseModel)
                }

                // Sort menu
                Menu {
                    ForEach(BrowseViewModel.SortField.allCases) { field in
                        Button {
                            browseModel.toggleSort(field: field)
                        } label: {
                            HStack {
                                Text(sortLabel(for: field))
                                if browseModel.sortField == field {
                                    Image(systemName: browseModel.sortAscending ? "chevron.up" : "chevron.down")
                                }
                            }
                        }
                    }
                } label: {
                    Label(L10n.resolutionSort(language), systemImage: "arrow.up.arrow.down")
                }

                Spacer()

                Text(L10n.browseItemCount(browseModel.displayedItems.count, language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L10n.browse(language))
    }

    private func sortLabel(for field: BrowseViewModel.SortField) -> String {
        switch field {
        case .name:             L10n.name(language)
        case .fileSize:         L10n.fileSize(language)
        case .modifiedTime:     L10n.modifiedTime(language)
        case .resolutionWidth:  L10n.sortByWidth(language)
        case .resolutionHeight: L10n.sortByHeight(language)
        }
    }
}
