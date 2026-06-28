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

import AVKit
import AppKit
import SwiftUI

struct InspectorView: View {
    @ObservedObject var model: ScanViewModel
    @Environment(\.appLanguage) private var language

    var body: some View {
        Group {
            if let media = model.selectedMedia {
                VStack(spacing: 0) {
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
                        }
                        .padding(18)
                    }

                    Divider()

                    let actions = PreviewActionArrangement.singleFileActions(includesOpenDefaultPlayer: media.kind == .video)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            ForEach(actions, id: \.self) { action in
                                actionButton(action, media: media)
                            }
                        }
                        .padding(18)
                        VStack(spacing: 8) {
                            ForEach(actions, id: \.self) { action in
                                actionButton(action, media: media)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(18)
                    }
                }
            } else {
                ContentUnavailableView(
                    L10n.selectMedia(language),
                    systemImage: "rectangle.and.hand.point.up.left",
                    description: Text(L10n.selectMediaHint(language))
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

    @ViewBuilder
    private func actionButton(_ action: PreviewActionKind, media: MediaItem) -> some View {
        switch action {
        case .openDefaultPlayer:
            Button(action: model.openSelectedMedia) {
                Label(L10n.openDefaultPlayer(language), systemImage: "play.rectangle")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        case .showInFinder:
            Button(action: model.revealSelectedMedia) {
                Label(L10n.showInFinder(language), systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        case .deleteFile:
            Button(role: .destructive) {
                model.requestPreviewDeletion(defaultingTo: media)
            } label: {
                Label(deleteButtonTitle, systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        case .deleteSelection:
            EmptyView()
        }
    }

    private var deleteButtonTitle: String {
        if model.checkedMediaIDs.isEmpty {
            return L10n.deleteMedia(language)
        }
        return L10n.deleteSelected(model.checkedMediaIDs.count, language)
    }
}

struct MediaPreview: View {
    let media: MediaItem
    @AppStorage("browsePreviewPlayerVolume") private var playerVolume = 0.5

    var body: some View {
        Group {
            if media.kind == .video {
                NativeVideoPlayerView(url: media.url, fallbackData: media.thumbnailData, volume: $playerVolume)
            } else if let image = MediaThumbnailImageCache.shared.image(for: media) {
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
            .aspectRatio(previewAspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var previewAspectRatio: CGFloat {
        guard media.kind == .image, media.width > 0, media.height > 0 else { return 16 / 9 }
        return CGFloat(media.width) / CGFloat(media.height)
    }
}
