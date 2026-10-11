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
    /// Shows the Preview & Details panel; called on a plain double-click.
    var onOpenPreview: () -> Void = {}
    @Environment(\.appLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var marqueeBase = Set<UUID>()
    @State private var marqueeMode = MarqueeSelectionMode.replace
    @State private var welcomeBounce = 0
    @State private var selectionBarHeight: CGFloat = 0
    /// Group whose cards cascade in. Set only when the user picks a group, so
    /// rebuilding this view (e.g. returning from Browse) does not replay it.
    @State private var cascadingGroupID: UUID?

    var body: some View {
        // A ZStack, not a Group: while one screen transitions into another
        // both exist at once, and a Group would hand them to the parent
        // HStack as side-by-side siblings, squeezing and reflowing both.
        ZStack {
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
                                    ForEach(Array(model.sortedGroupItems.enumerated()), id: \.element.id) { index, video in
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
                                        .equatable()
                                        .onTapGesture { handleCardTap(video) }
                                        .help(L10n.doubleClickToPreview(language))
                                        .contextMenu { groupContextMenu(clickedID: video.id) }
                                        .marqueeItem(video.id)
                                        .cascadeIn(index: index, isEnabled: cascadingGroupID == group.id, reduceMotion: reduceMotion)
                                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                                    }
                                }
                                // Re-sorting and deleting move cards instead of jumping.
                                .animation(Motion.standard, value: model.sortedGroupItems.map(\.id))
                            }
                            .padding(20)
                        }
                        // Fill the viewport (minus the selection bar's margin, so a
                        // short group never becomes scrollable just from checking a card).
                        // The 1pt slack keeps sub-point rounding from making it scrollable.
                        .frame(maxWidth: .infinity, minHeight: max(1, geometry.size.height - bottomContentMargin - 1), alignment: .topLeading)
                        .marqueeSelection(
                            isEnabled: !model.isBusy,
                            resetKey: model.sortedGroupItems.map(\.id),
                            onBegin: { mode in
                                marqueeMode = mode
                                marqueeBase = mode == .replace ? [] : model.checkedMediaIDs
                            },
                            onChange: { hits in
                                model.setGroupItemSelection(marqueeMode.apply(hits: hits, to: marqueeBase))
                            },
                            onEnd: model.finishGroupItemMarquee
                        )
                    }
                    .contextMenu { groupContextMenu(clickedID: nil) }
                    // Leave room for the floating selection bar without
                    // shrinking the viewport, so cards keep their size.
                    .contentMargins(.bottom, bottomContentMargin, for: .scrollContent)
                }
                // A new group replaces the old one with a crossfade and starts at
                // the top. Opacity only: a scaling transition (like .blurReplace)
                // resizes the hosted NSScrollView by fractions of a point, which
                // toggles its scroll bar on and off for the whole transition.
                .id(group.id)
                .transition(.opacity)
            } else if !model.groups.isEmpty {
                ContentUnavailableView(
                    L10n.selectGroup(language),
                    systemImage: "rectangle.3.group",
                    description: Text(L10n.resultsOnLeft(language))
                )
            } else if model.isScanning {
                VStack(spacing: 14) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.tint)
                        .symbolEffect(.pulse, options: .repeating)
                    ProgressView(value: model.progress.fraction)
                        .frame(maxWidth: 260)
                        .animation(.linear(duration: 0.2), value: model.progress.fraction)
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
        // An overlay rather than a safe-area inset: an inset would shrink the
        // geometry the card heights are computed from, resizing every card the
        // moment the first one is checked (visible as a hitch during a marquee).
        .overlay(alignment: .bottom) {
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
                }
                .background(.bar)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { selectionBarHeight = $0 }
                .transition(Motion.slide(from: .bottom, reduceMotion: reduceMotion))
            }
        }
        .onChange(of: model.selectedGroupID) { _, id in cascadingGroupID = id }
        .animation(Motion.standard, value: model.checkedMediaIDs.isEmpty)
        .animation(Motion.standard, value: contentState)
        .navigationTitle(AppIdentity.displayName)
    }

    private var selectionCount: some View {
        Label(L10n.selectedCount(model.checkedMediaIDs.count, language), systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .contentTransition(.numericText(value: Double(model.checkedMediaIDs.count)))
            .animation(Motion.quick, value: model.checkedMediaIDs.count)
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
                .symbolEffect(.bounce, value: model.checkedMediaIDs.count)
        }
        .buttonStyle(.bordered)
        .disabled(model.isBusy)
        .fixedSize()
    }

    private var bottomContentMargin: CGFloat {
        model.checkedMediaIDs.isEmpty ? 0 : selectionBarHeight
    }

    /// Which top-level screen is showing; changes crossfade between them.
    private var contentState: ContentState {
        if model.selectedFolders.isEmpty { return .welcome }
        if let group = model.selectedGroup { return .group(group.id) }
        if !model.groups.isEmpty { return .selectGroup }
        if model.isScanning { return .scanning }
        return .empty
    }

    private enum ContentState: Equatable {
        case welcome, group(UUID), selectGroup, scanning, empty
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.stack")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.bounce, value: welcomeBounce)
                .onAppear { welcomeBounce += 1 }
                .onHover { if $0 { welcomeBounce += 1 } }
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

    /// Every click selects immediately; the second click of a plain
    /// double-click also opens the preview. Reading the click count instead
    /// of adding a count-2 tap gesture keeps single clicks free of the delay
    /// SwiftUI adds while it waits to rule out a double-click.
    private func handleCardTap(_ video: MediaItem) {
        let modifiers = NSEvent.modifierFlags
        if NSApp.currentEvent?.clickCount == 2, !modifiers.contains(.shift), !modifiers.contains(.command) {
            model.selectGroupItem(video.id)
            onOpenPreview()
        } else if modifiers.contains(.shift) {
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
