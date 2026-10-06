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

import AppKit
import SwiftUI

struct GroupDetailView: View {
    @ObservedObject var model: ScanViewModel
    @Environment(\.appLanguage) private var language

    var body: some View {
        Group {
            if model.selectedFolders.isEmpty {
                welcome
            } else if let group = model.selectedGroup {
                GeometryReader { geometry in
                    ScrollView {
                        ZStack(alignment: .topLeading) {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { model.clearGroupItemSelection() }

                            VStack(alignment: .leading, spacing: 16) {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(L10n.similarMediaCount(group.items.count, language))
                                            .font(.title2.bold())
                                        Text(L10n.highestSimilarity(DisplayFormatters.percent(group.maximumScore), language))
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .help(L10n.similarityScoreHelp(language))
                                    }
                                    Spacer()
                                    GroupSortMenu(model: model, language: language)
                                }

                                LazyVGrid(columns: comparisonColumns(width: geometry.size.width, itemCount: group.items.count), spacing: 14) {
                                    ForEach(model.sortedGroupItems) { video in
                                        VideoCardView(
                                            video: video,
                                            score: group.score(for: video.id),
                                            evidence: group.evidence(for: video.id),
                                            language: language,
                                            isSelected: model.selectedMediaID == video.id,
                                            isChecked: model.checkedMediaIDs.contains(video.id),
                                            previewHeight: comparisonPreviewHeight(size: geometry.size, itemCount: group.items.count),
                                            toggleChecked: { model.toggleChecked(video.id) }
                                        )
                                        .onTapGesture { handleCardTap(video) }
                                        .contextMenu { groupContextMenu(clickedID: video.id) }
                                    }
                                }
                            }
                            .padding(20)
                        }
                        .frame(maxWidth: .infinity, minHeight: 1, alignment: .topLeading)
                    }
                    .contextMenu { groupContextMenu(clickedID: nil) }
                }
            } else if !model.groups.isEmpty {
                ContentUnavailableView(
                    L10n.selectGroup(language),
                    systemImage: "rectangle.3.group",
                    description: Text(L10n.resultsOnLeft(language))
                )
            } else if model.isScanning {
                VStack(spacing: 14) {
                    ProgressView()
                    Text(L10n.scanProgressTitle(model.progress, language)).font(.headline)
                    Text(L10n.scanProgressDetail(model.progress, language)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    model.progress.stage == .completed ? L10n.noSimilarMedia(language) : L10n.waitingToScan(language),
                    systemImage: model.progress.stage == .completed ? "checkmark.circle" : "folder.badge.plus",
                    description: Text(model.progress.stage == .completed ? L10n.lowerThresholdHint(language) : L10n.chooseAndScanHint(language))
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.checkedMediaIDs.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            selectionCount
                            clearSelectionButton
                            Spacer()
                            deleteSelectionButton
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                selectionCount
                                Spacer()
                                clearSelectionButton
                            }
                            deleteSelectionButton
                        }
                    }
                    .padding(16)
                    .background(.bar)
                }
            }
        }
        .navigationTitle(AppIdentity.displayName)
    }

    private var selectionCount: some View {
        Label(L10n.selectedCount(model.checkedMediaIDs.count, language), systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .fixedSize(horizontal: true, vertical: false)
    }

    private var clearSelectionButton: some View {
        Button(L10n.deselectAllGroupItems(language), action: model.clearGroupItemSelection)
            .buttonStyle(.borderless)
            .fixedSize()
    }

    private var deleteSelectionButton: some View {
        Button(role: .destructive, action: model.requestCheckedDeletion) {
            Label(L10n.deleteSelected(model.checkedMediaIDs.count, language), systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .disabled(model.isBusy)
        .fixedSize()
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.stack")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                Text(L10n.findSimilarMedia(language)).font(.largeTitle.weight(.semibold))
                Text(L10n.dragFoldersHint(language)).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button(action: { model.chooseFolder(language: language) }) {
                    Label(L10n.addFolders(language), systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func comparisonColumns(width: CGFloat, itemCount: Int) -> [GridItem] {
        let availableColumns = max(1, Int((width - 40 + 14) / 244))
        let count = max(1, min(itemCount, availableColumns))
        return Array(repeating: GridItem(.flexible(minimum: 230), spacing: 14), count: count)
    }

    private func comparisonPreviewHeight(size: CGSize, itemCount: Int) -> CGFloat {
        let columns = comparisonColumns(width: size.width, itemCount: itemCount).count
        let imageWidth = max(160, (size.width - 40 - CGFloat(columns - 1) * 14) / CGFloat(columns) - 24)
        let contentHeight = model.sortedGroupItems.map { item -> CGFloat in
            if item.kind == .image, item.width > 0, item.height > 0 {
                return imageWidth * CGFloat(item.height) / CGFloat(item.width)
            }
            return imageWidth * 9 / 16
        }.max() ?? imageWidth
        return max(160, min(460, min(size.height - 235, contentHeight)))
    }

    @ViewBuilder
    private func groupContextMenu(clickedID: UUID?) -> some View {
        let targets = MediaContextSelection.items(
            displayedItems: model.sortedGroupItems,
            selectedIDs: model.checkedMediaIDs,
            clickedID: clickedID,
            fallbackID: model.selectedMediaID
        )
        Button(L10n.selectAll(language), action: model.selectAllGroupItems)
            .disabled(model.sortedGroupItems.isEmpty || model.isBusy)
        Divider()
        Button(role: .destructive) { model.requestDeletion(of: targets) } label: {
            Label(targets.count > 1 ? L10n.deleteSelected(targets.count, language) : L10n.deleteMedia(language), systemImage: "trash")
        }
        .disabled(targets.isEmpty || model.isBusy)
    }

    private func handleCardTap(_ video: MediaItem) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift) {
            model.extendGroupItemSelection(to: video.id)
        } else if modifiers.contains(.command) {
            model.toggleGroupItemSelection(video.id)
        } else {
            model.selectGroupItem(video.id)
        }
    }

}

/// Sort menu for the Compare Media card grid. Each dimension is a button:
/// click to activate it (descending on first click), click again to flip to
/// ascending — no separate direction control. The active field shows its
/// current direction with a chevron.
private struct GroupSortMenu: View {
    @ObservedObject var model: ScanViewModel
    let language: AppLanguage

    var body: some View {
        Menu {
            ForEach(GroupSortField.allCases) { field in
                Button {
                    model.toggleGroupSort(field: field)
                } label: {
                    if model.groupSortField == field {
                        // "Similarity ↓" / "Similarity ↑" — direction inline on the active item.
                        Label(
                            "\(label(for: field)) \(model.groupSortAscending ? "↑" : "↓")",
                            systemImage: model.groupSortAscending ? "chevron.up" : "chevron.down"
                        )
                    } else {
                        Text(label(for: field))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.groupSortAscending ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                Text(label(for: model.groupSortField))
                    .font(.callout.weight(.medium))
            }
        }
        .menuStyle(.button)
        .fixedSize()
    }

    private func label(for field: GroupSortField) -> String {
        switch field {
        case .similarity: L10n.sortSimilarity(language)
        case .fileSize: L10n.fileSize(language)
        case .name: L10n.name(language)
        case .duration: L10n.duration(language)
        case .resolutionWidth: L10n.sortByWidth(language)
        case .resolutionHeight: L10n.sortByHeight(language)
        }
    }
}
