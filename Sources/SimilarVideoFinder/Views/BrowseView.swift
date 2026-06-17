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

    /// Fraction of total width given to the table (left side).
    @State private var leftFraction: CGFloat = 0.65

    /// Fraction captured at the start of a drag — basis for translation deltas.
    @State private var dragStartFraction: CGFloat?

    /// Track whether the user is currently dragging the divider.
    @State private var isDraggingDivider = false

    /// Hard floors so neither pane can collapse to zero.
    private let minLeftWidth: CGFloat = 80
    private let minRightWidth: CGFloat = 80

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let leftWidth = clampedLeft(totalWidth: totalWidth)

            HStack(spacing: 0) {
                // ── Left: file table ──
                BrowseTableView(browseModel: browseModel)
                    .frame(width: leftWidth)
                    .frame(maxHeight: .infinity)
                    .clipped()

                // ── Draggable divider ──
                divider
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .named("browseSplit"))
                            .onChanged { value in
                                isDraggingDivider = true
                                let start = dragStartFraction ?? leftFraction
                                if dragStartFraction == nil { dragStartFraction = start }
                                let baseLeft = totalWidth * start
                                let proposedLeft = baseLeft + value.translation.width
                                leftFraction = clampedLeft(totalWidth: totalWidth, proposed: proposedLeft) / totalWidth
                            }
                            .onEnded { _ in
                                isDraggingDivider = false
                                dragStartFraction = nil
                            }
                    )
                    .onHover { inside in
                        if inside || isDraggingDivider {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }

                // ── Right: preview panel ──
                BrowsePreviewPanel(browseModel: browseModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .coordinateSpace(name: "browseSplit")
        .background(WindowTitleUpdater(title: L10n.browseItemCount(browseModel.displayedItems.count, language)))
        .toolbar {
            ToolbarItemGroup {
                ToolbarLabeledButton(
                    title: L10n.back(language),
                    systemImage: "chevron.left",
                    action: onBack
                )

                ToolbarLabeledButton(
                    title: L10n.filter(language),
                    systemImage: browseModel.hasActiveFilter
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                ) {
                    browseModel.isFilterPresented.toggle()
                }
                .popover(isPresented: $browseModel.isFilterPresented) {
                    BrowseFilterPopover(browseModel: browseModel)
                }
            }
        }
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1)
            .frame(width: 8)       // wider hit target for dragging
            .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private func clampedLeft(totalWidth: CGFloat, proposed: CGFloat? = nil) -> CGFloat {
        let candidate = proposed ?? (totalWidth * leftFraction)
        return max(minLeftWidth, min(totalWidth - minRightWidth, candidate))
    }
}
