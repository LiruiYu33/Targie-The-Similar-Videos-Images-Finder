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

struct BrowseTableView: View {
    @ObservedObject var browseModel: BrowseViewModel
    @Environment(\.appLanguage) private var language

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
            VStack(spacing: 0) {
                browseTableHeader
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.bar)

                Divider()

                List(browseModel.displayedItems, selection: Binding(
                    get: { browseModel.selectedMediaID },
                    set: { browseModel.selectMedia($0) }
                )) { item in
                    BrowseTableRow(item: item, language: language)
                        .tag(item.id)
                }
                .listStyle(.inset)
                .alternatingRowBackgrounds(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Table Header

    private var browseTableHeader: some View {
        HStack(spacing: 0) {
            headerLabel(L10n.thumbnail(language), width: 60)

            sortHeader(L10n.name(language), field: .name, fill: true)

            sortHeader(L10n.fileSize(language), field: .fileSize, fill: false, width: 90)

            resolutionHeader

            sortHeader(L10n.modifiedTime(language), field: .modifiedTime, fill: false, width: 120)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func headerLabel(_ text: String, width: CGFloat) -> some View {
        Text(text).frame(width: width, alignment: .leading)
    }

    private func sortHeader(_ text: String, field: BrowseViewModel.SortField, fill: Bool, width: CGFloat? = nil) -> some View {
        Button { browseModel.toggleSort(field: field) } label: {
            HStack(spacing: 4) {
                Text(text)
                if browseModel.sortField == field {
                    Image(systemName: browseModel.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
        }
        .buttonStyle(.plain)
        .iflet(width) { v, w in v.frame(width: w, alignment: .leading) }
        .if(fill) { v in v.frame(maxWidth: .infinity, alignment: .leading) }
    }

    private var resolutionHeader: some View {
        Button { browseModel.isResolutionSortPresented.toggle() } label: {
            HStack(spacing: 4) {
                Text(L10n.resolution(language))
                if browseModel.sortField.isResolution {
                    Image(systemName: browseModel.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
            .frame(width: 110, alignment: .leading)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $browseModel.isResolutionSortPresented) {
            BrowseResolutionSortPopover(browseModel: browseModel, language: language)
        }
    }
}

// MARK: - Table Row

struct BrowseTableRow: View {
    let item: MediaItem
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 0) {
            BrowseThumbnailCell(item: item)
                .frame(width: 48, height: 48)
                .frame(width: 60, alignment: .center)

            HStack(spacing: 6) {
                Image(systemName: item.kind == .video ? "film" : "photo")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(item.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(DisplayFormatters.fileSize(item.fileSize))
                .monospacedDigit()
                .frame(width: 90, alignment: .leading)

            Text(item.resolution(language: language))
                .monospacedDigit()
                .frame(width: 110, alignment: .leading)

            Group {
                if let date = item.modifiedAt {
                    Text(date, style: .date)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 120, alignment: .leading)
        }
        .font(.callout)
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
