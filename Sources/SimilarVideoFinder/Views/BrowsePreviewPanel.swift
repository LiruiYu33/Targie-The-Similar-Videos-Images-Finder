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
import SwiftUI

struct BrowsePreviewPanel: View {
    @ObservedObject var browseModel: BrowseViewModel
    @Environment(\.appLanguage) private var language

    var body: some View {
        Group {
            if let media = browseModel.selectedMedia {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        BrowseMediaPreview(media: media)
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
                                Button(L10n.openDefaultPlayer(language)) { browseModel.scanModel.openMedia(media) }
                            }
                            Button(L10n.showInFinder(language)) { browseModel.scanModel.revealMedia(media) }
                        }
                        .controlSize(.small)

                        Divider()
                        Button(role: .destructive) {
                            browseModel.scanModel.requestDeletion(of: media)
                        } label: {
                            Label(L10n.deleteMedia(language), systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(18)
                }
            } else {
                ContentUnavailableView(
                    L10n.selectMedia(language),
                    systemImage: "rectangle.and.hand.point.up.left",
                    description: Text(L10n.selectMediaHint(language))
                )
            }
        }
        .navigationTitle("")
    }

    private func metadata(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).textSelection(.enabled)
        }
    }
}

// MARK: - Browse Media Preview (with video playback via native AVPlayerView)

struct BrowseMediaPreview: View {
    let media: MediaItem

    var body: some View {
        Group {
            if media.kind == .video {
                NativeVideoPlayerView(url: media.url, fallbackData: media.thumbnailData)
                    .aspectRatio(16 / 9, contentMode: .fit)
            } else if let data = media.thumbnailData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: "photo")
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

// MARK: - Native AVPlayerView wrapped for SwiftUI

/// Wraps AppKit's `AVPlayerView` in an `NSViewRepresentable`.
/// This avoids the SwiftUI `VideoPlayer` metadata-initialization crash
/// that occurs when `VideoPlayer` is used inside a `@MainActor` view
/// hierarchy (e.g. observing a `@MainActor` ViewModel).
struct NativeVideoPlayerView: NSViewRepresentable {
    let url: URL
    let fallbackData: Data?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = nil
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Only swap the player when the URL actually changes
        let currentURL = context.coordinator.currentURL
        guard currentURL != url else { return }
        context.coordinator.currentURL = url

        if FileManager.default.fileExists(atPath: url.path) {
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.volume = 0.5
            nsView.player = player
        } else {
            nsView.player = nil
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        nsView.player?.pause()
        nsView.player = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var currentURL: URL?
    }
}
