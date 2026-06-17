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

/// Effective per-column widths after fitting the table to the container.
struct BrowseColumnWidths: Equatable {
    let thumbnail: CGFloat
    let name: CGFloat
    let fileSize: CGFloat
    let resolution: CGFloat
    let modifiedTime: CGFloat
}

struct BrowseTableView: View {
    @ObservedObject var browseModel: BrowseViewModel
    @Environment(\.appLanguage) private var language

    // Stored (user-preferred) widths for resizable columns.
    @State private var thumbnailWidth: CGFloat = 56
    @State private var fileSizeWidth: CGFloat = 84
    @State private var resolutionWidth: CGFloat = 100
    @State private var modifiedTimeWidth: CGFloat = 110

    private let rowHorizontalPadding: CGFloat = 12
    private let dividerWidth: CGFloat = 6
    private let nameMinWidth: CGFloat = 60

    var body: some View {
        if browseModel.scanModel.isScanning && browseModel.scanModel.items.isEmpty {
            VStack(spacing: 12) {
                ProgressView(value: browseModel.scanModel.progress.fraction) {
                    Text(L10n.scanStage(browseModel.scanModel.progress.stage, language))
                } currentValueLabel: {
                    Text(browseModel.scanModel.progress.currentFile)
                        .lineLimit(1)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .controlSize(.large)
                .frame(maxWidth: 300)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if browseModel.displayedItems.isEmpty {
            ContentUnavailableView(
                L10n.noItemsToBrowse(language),
                systemImage: "doc.questionmark",
                description: Text(L10n.noItemsBrowseHint(language))
            )
        } else {
            GeometryReader { geo in
                let widths = computeWidths(forContainerWidth: geo.size.width)

                VStack(spacing: 0) {
                    browseTableHeader(widths: widths)
                        .padding(.horizontal, rowHorizontalPadding)
                        .frame(height: 28)
                        .background(.bar)

                    Divider()

                    List(selection: Binding(
                        get: { browseModel.selectedMediaID },
                        set: { browseModel.selectMedia($0) }
                    )) {
                        ForEach(browseModel.displayedItems) { item in
                            BrowseTableRow(item: item, language: language, widths: widths)
                                .padding(.horizontal, rowHorizontalPadding)
                                .listRowInsets(EdgeInsets())
                                .tag(item.id)
                        }
                    }
                    .id(browseModel.sortVersion)
                    .listStyle(.plain)
                    .alternatingRowBackgrounds(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Fit the columns to the container.
    /// Thumbnail/fileSize/resolution/modifiedTime use stored widths but scale down
    /// proportionally if total > available; name absorbs leftover space (or its
    /// minimum if everything else has been squeezed flat).
    private func computeWidths(forContainerWidth container: CGFloat) -> BrowseColumnWidths {
        let inner = max(0, container - 2 * rowHorizontalPadding)
        let dividers = 3 * dividerWidth

        let preferred = thumbnailWidth + fileSizeWidth + resolutionWidth + modifiedTimeWidth
        let availableForFixed = max(0, inner - dividers - nameMinWidth)

        let scale: CGFloat = preferred > availableForFixed && preferred > 0
            ? availableForFixed / preferred
            : 1

        let thumb = thumbnailWidth * scale
        let size  = fileSizeWidth * scale
        let res   = resolutionWidth * scale
        let mod   = modifiedTimeWidth * scale

        let usedFixed = thumb + size + res + mod
        let nameWidth = max(nameMinWidth, inner - dividers - usedFixed)

        return BrowseColumnWidths(
            thumbnail: thumb,
            name: nameWidth,
            fileSize: size,
            resolution: res,
            modifiedTime: mod
        )
    }

    // MARK: - Table Header

    private func browseTableHeader(widths: BrowseColumnWidths) -> some View {
        HStack(spacing: 0) {
            Text(L10n.thumbnail(language))
                .lineLimit(1)
                .frame(width: widths.thumbnail, alignment: .leading)

            sortHeader(L10n.name(language), field: .name)
                .frame(width: widths.name, alignment: .leading)

            ColumnResizeHandle(width: $fileSizeWidth, dividerWidth: dividerWidth)

            sortHeader(L10n.fileSize(language), field: .fileSize)
                .frame(width: widths.fileSize, alignment: .leading)

            ColumnResizeHandle(width: $resolutionWidth, dividerWidth: dividerWidth)

            resolutionHeader
                .frame(width: widths.resolution, alignment: .leading)

            ColumnResizeHandle(width: $modifiedTimeWidth, dividerWidth: dividerWidth)

            sortHeader(L10n.modifiedTime(language), field: .modifiedTime)
                .frame(width: widths.modifiedTime, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func sortHeader(_ text: String, field: BrowseViewModel.SortField) -> some View {
        Button { browseModel.toggleSort(field: field) } label: {
            HStack(spacing: 4) {
                Text(text).lineLimit(1)
                if browseModel.sortField == field {
                    Image(systemName: browseModel.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var resolutionHeader: some View {
        Button { browseModel.isResolutionSortPresented.toggle() } label: {
            HStack(spacing: 4) {
                Text(L10n.resolution(language)).lineLimit(1)
                if browseModel.sortField.isResolution {
                    Image(systemName: browseModel.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $browseModel.isResolutionSortPresented) {
            BrowseResolutionSortPopover(browseModel: browseModel, language: language)
        }
    }
}

// MARK: - Column Resize Handle

private struct ColumnResizeHandle: View {
    @Binding var width: CGFloat
    let dividerWidth: CGFloat
    @State private var startWidth: CGFloat?

    private let minWidth: CGFloat = 50
    private let maxWidth: CGFloat = 400

    var body: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(.quaternary)
                .frame(width: 1)
        }
        .frame(width: dividerWidth)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let base = startWidth ?? width
                    if startWidth == nil { startWidth = base }
                    // Handle is on the left edge of the column it controls;
                    // dragging right should narrow that column.
                    let proposed = base - value.translation.width
                    width = max(minWidth, min(maxWidth, proposed))
                }
                .onEnded { _ in startWidth = nil }
        )
    }
}

// MARK: - Table Row

struct BrowseTableRow: View {
    let item: MediaItem
    let language: AppLanguage
    let widths: BrowseColumnWidths

    var body: some View {
        HStack(spacing: 0) {
            BrowseThumbnailCell(item: item)
                .frame(width: min(widths.thumbnail, 40), height: min(widths.thumbnail, 40))
                .frame(width: widths.thumbnail, alignment: .leading)

            HStack(spacing: 6) {
                Image(systemName: item.kind == .video ? "film" : "photo")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(item.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: widths.name, alignment: .leading)

            // Spacer matches the divider width so columns align with header.
            Color.clear.frame(width: 6)

            Text(DisplayFormatters.fileSize(item.fileSize))
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: widths.fileSize, alignment: .leading)

            Color.clear.frame(width: 6)

            Text(item.resolution(language: language))
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: widths.resolution, alignment: .leading)

            Color.clear.frame(width: 6)

            Group {
                if let date = item.modifiedAt {
                    Text(date, style: .date).lineLimit(1)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .frame(width: widths.modifiedTime, alignment: .leading)
        }
        .font(.callout)
        .padding(.vertical, 4)
    }
}

// MARK: - View Helpers

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }

    @ViewBuilder
    func iflet<T, Content: View>(_ value: T?, transform: (Self, T) -> Content) -> some View {
        if let value { transform(self, value) } else { self }
    }
}

// MARK: - Thumbnail Cell

struct BrowseThumbnailCell: View {
    let item: MediaItem
    var body: some View {
        Group {
            if let data = item.thumbnailData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: item.kind == .video ? "film" : "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Resolution Sort Popover

struct BrowseResolutionSortPopover: View {
    @ObservedObject var browseModel: BrowseViewModel
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.resolutionSort(language))
                    .font(.headline)
                Text(L10n.sortBy(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: Binding(
                    get: { browseModel.sortField.isResolution ? browseModel.sortField : .resolutionWidth },
                    set: { browseModel.sortField = $0; browseModel.sortAscending = true }
                )) {
                    Text(L10n.sortByWidth(language)).tag(BrowseViewModel.SortField.resolutionWidth)
                    Text(L10n.sortByHeight(language)).tag(BrowseViewModel.SortField.resolutionHeight)
                }
                .pickerStyle(.segmented)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.sortDirection(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $browseModel.sortAscending) {
                    Text(L10n.ascending(language)).tag(true)
                    Text(L10n.descending(language)).tag(false)
                }
                .pickerStyle(.segmented)
            }

            if browseModel.sortField.isResolution {
                Button(L10n.clearFilter(language), action: browseModel.clearResolutionSort)
                    .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}
