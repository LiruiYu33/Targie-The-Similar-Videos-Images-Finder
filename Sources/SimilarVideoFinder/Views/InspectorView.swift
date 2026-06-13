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
            if let video = model.selectedVideo {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VideoPreview(video: video)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(video.filename)
                                .font(.title3.bold())
                                .textSelection(.enabled)
                            metadata(L10n.fileSize(language), DisplayFormatters.fileSize(video.fileSize))
                            metadata(L10n.duration(language), DisplayFormatters.duration(video.duration, language: language))
                            metadata(L10n.resolution(language), video.resolution(language: language))
                            metadata(L10n.path(language), video.url.path)
                        }

                        HStack {
                            Button(L10n.openDefaultPlayer(language), action: model.openSelectedVideo)
                            Button(L10n.showInFinder(language), action: model.revealSelectedVideo)
                        }
                        .controlSize(.small)

                        Divider()
                        Button(role: .destructive) {
                            model.requestDeletion(of: video)
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

private struct VideoPreview: View {
    let video: VideoItem

    var body: some View {
        Group {
            if let data = video.thumbnailData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: "film")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                }
            }
        }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
