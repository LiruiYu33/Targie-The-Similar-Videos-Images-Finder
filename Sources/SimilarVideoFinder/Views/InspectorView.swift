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

struct InspectorView: View {
    @ObservedObject var model: ScanViewModel
    @Environment(\.appLanguage) private var language

    var body: some View {
        Group {
            if let media = model.selectedMedia {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        MediaPreview(media: media)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(media.filename)
                                .font(.title3.bold())
                                .textSelection(.enabled)
                            metadata(L10n.fileSize(language), DisplayFormatters.fileSize(media.fileSize))
                            if let duration = media.duration {
                                metadata(L10n.duration(language), DisplayFormatters.duration(duration, language: language))
                            }
                            metadata(L10n.resolution(language), media.resolution(language: language))
                            metadata(L10n.path(language), media.url.path)
                        }

                        HStack {
                            if media.kind == .video {
                                Button(L10n.openDefaultPlayer(language), action: model.openSelectedMedia)
                            }
                            Button(L10n.showInFinder(language), action: model.revealSelectedMedia)
                        }
                        .controlSize(.small)

                        Divider()
                        Button(role: .destructive) {
                            model.requestDeletion(of: media)
                        } label: {
                            Label(L10n.deleteVideo(language), systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(18)
                }
            } else {
                ContentUnavailableView(
                    L10n.selectVideo(language),
                    systemImage: "play.rectangle",
                    description: Text(L10n.selectVideoHint(language))
                )
            }
        }
        .navigationTitle(L10n.previewAndDetails(language))
    }

    private func metadata(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).textSelection(.enabled)
        }
    }
}

private struct MediaPreview: View {
    let media: MediaItem

    var body: some View {
        Group {
            if let data = media.thumbnailData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: media.kind == .video ? "film" : "photo")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                }
            }
        }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
