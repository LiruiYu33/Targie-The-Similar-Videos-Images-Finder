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
        .navigationTitle(L10n.previewAndDetails(language))
    }

    private func metadata(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).textSelection(.enabled)
        }
    }
}

struct MediaPreview: View {
    let media: MediaItem

    var body: some View {
        Group {
            if media.kind == .video {
                VideoMediaPreview(url: media.url, fallbackData: media.thumbnailData)
            } else if let data = media.thumbnailData, let image = NSImage(data: data) {
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

/// Live, playable preview for video media. Wraps SwiftUI's `VideoPlayer`
/// (AVKit), so clicking the frame plays/pauses and the built-in scrubber
/// lets the user seek. The player is recreated whenever the URL changes.
private struct VideoMediaPreview: View {
    let url: URL
    let fallbackData: Data?

    @StateObject private var holder = PlayerHolder()

    var body: some View {
        VStack(spacing: 0) {
            if let player = holder.player {
                VideoPlayer(player: player)
            } else {
                // Fallback: static thumbnail while the player loads (or if the file
                // is unreadable).
                ZStack {
                    Color.black.opacity(0.88)
                    if let data = fallbackData, let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "film")
                            .font(.system(size: 42))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .onAppear { holder.load(url: url) }
        .onChange(of: url) { _, newURL in holder.load(url: newURL) }
        .onDisappear { holder.tearDown() }
    }
}

/// Owns the `AVPlayer`. Kept free of `@MainActor` isolation: it is only ever
/// touched from SwiftUI lifecycle callbacks (`onAppear`/`onChange`/`onDisappear`)
/// which already run on the main thread, and marking it `@MainActor` triggers a
/// Swift-runtime metadata-initialization crash when used via `@StateObject`.
private final class PlayerHolder: ObservableObject {
    @Published var player: AVPlayer?

    func load(url: URL) {
        // Drop any previous player before constructing a new one.
        player?.pause()
        player = nil
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.volume = 0.5
        player = newPlayer
    }

    func tearDown() {
        player?.pause()
        player = nil
    }
}
