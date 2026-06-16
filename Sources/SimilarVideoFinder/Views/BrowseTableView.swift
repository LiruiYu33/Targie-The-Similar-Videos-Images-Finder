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
            Table(browseModel.displayedItems, selection: Binding(
                get: { browseModel.selectedMediaID },
                set: { browseModel.selectMedia($0) }
            )) {
                TableColumn(L10n.thumbnail(language)) { item in
                    BrowseThumbnailCell(item: item)
                }
                .width(min: 48, ideal: 60, max: 80)

                TableColumn(L10n.name(language)) { item in
                    BrowseNameCell(item: item)
                }
                .width(min: 120, ideal: 250)

                TableColumn(L10n.fileSize(language)) { item in
                    Text(DisplayFormatters.fileSize(item.fileSize))
                }
                .width(min: 60, ideal: 90, max: 120)

                TableColumn(L10n.resolution(language)) { item in
                    Text(item.resolution(language: language))
                }
                .width(min: 80, ideal: 110, max: 150)

                TableColumn(L10n.modifiedTime(language)) { item in
                    BrowseDateText(date: item.modifiedAt)
                }
                .width(min: 80, ideal: 120, max: 160)
            }
            .alternatingRowBackgrounds(.enabled)
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}

// MARK: - Cell Views

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
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct BrowseNameCell: View {
    let item: MediaItem
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.kind == .video ? "film" : "photo")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(item.filename)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct BrowseDateText: View {
    let date: Date?
    var body: some View {
        if let date {
            Text(date, style: .date)
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }
}
