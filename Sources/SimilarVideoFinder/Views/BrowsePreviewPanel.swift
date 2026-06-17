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
            if browseModel.hasMultipleSelection {
                BrowseStackedPreview(browseModel: browseModel, language: language)
            } else if let media = browseModel.selectedMedia {
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

// MARK: - Stacked Selection Preview

struct BrowseStackedPreview: View {
    @ObservedObject var browseModel: BrowseViewModel
    let language: AppLanguage

    private var selectedItems: [MediaItem] { browseModel.selectedMediaList }
    private var visibleItems: [MediaItem] { Array(selectedItems.prefix(8)) }
    private var extraCount: Int { max(0, selectedItems.count - visibleItems.count) }
    private var totalSize: Int64 { selectedItems.reduce(0) { $0 + $1.fileSize } }
    private var imageCount: Int { selectedItems.filter { $0.kind == .image }.count }
    private var videoCount: Int { selectedItems.filter { $0.kind == .video }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                        stackedThumbnail(item: item, index: index)
                    }
                    if extraCount > 0 {
                        Text("+\(extraCount)")
                            .font(.headline.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .offset(x: 74, y: 54)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.selectedCount(selectedItems.count, language))
                        .font(.title3.bold())
                    metadata(L10n.fileSize(language), DisplayFormatters.fileSize(totalSize))
                    metadata(L10n.images(language), "\(imageCount)")
                    metadata(L10n.videos(language), "\(videoCount)")
                }

                HStack {
                    if let first = selectedItems.first {
                        Button(L10n.showInFinder(language)) { browseModel.scanModel.revealMedia(first) }
                    }
                    Button(role: .destructive) {
                        browseModel.scanModel.requestDeletion(of: selectedItems)
                    } label: {
                        Label(L10n.deleteSelected(selectedItems.count, language), systemImage: "trash")
                    }
                }
                .controlSize(.small)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(selectedItems.prefix(12)) { item in
                        Text(item.filename)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if selectedItems.count > 12 {
                        Text("+\(selectedItems.count - 12)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .textSelection(.enabled)
            }
            .padding(18)
        }
    }

    private func stackedThumbnail(item: MediaItem, index: Int) -> some View {
        let offset = CGFloat(index) * 12
        let rotation = Double(index - visibleItems.count / 2) * 3
        return BrowseThumbnailCell(item: item)
            .frame(width: 170, height: 120)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .rotationEffect(.degrees(rotation))
            .offset(x: offset - 42, y: offset * 0.45 - 18)
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
    @AppStorage("browsePreviewPlayerVolume") private var playerVolume = 0.5

    var body: some View {
        Group {
            if media.kind == .video {
                NativeVideoPlayerView(url: media.url, fallbackData: media.thumbnailData, volume: $playerVolume)
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
    @Binding var volume: Double

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.allowsPictureInPicturePlayback = true
        view.player = nil
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        context.coordinator.volume = $volume
        context.coordinator.playerView = nsView

        // Only swap the player when the URL actually changes
        let currentURL = context.coordinator.currentURL
        guard currentURL != url else {
            nsView.player?.volume = Float(volume)
            return
        }
        context.coordinator.currentURL = url
        context.coordinator.removeVolumeObservation()

        if FileManager.default.fileExists(atPath: url.path) {
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.volume = Float(volume)
            nsView.player = player
            context.coordinator.observeVolume(on: player)
        } else {
            nsView.player = nil
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.removeVolumeObservation()
        nsView.player?.pause()
        nsView.player = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(volume: $volume)
    }

    class Coordinator {
        var currentURL: URL?
        var volume: Binding<Double>
        weak var playerView: AVPlayerView?
        private var volumeObservation: NSKeyValueObservation?

        init(volume: Binding<Double>) {
            self.volume = volume
        }

        func observeVolume(on player: AVPlayer) {
            volumeObservation = player.observe(\.volume, options: [.new]) { player, _ in
                UserDefaults.standard.set(Double(player.volume), forKey: "browsePreviewPlayerVolume")
            }
        }

        func removeVolumeObservation() {
            volumeObservation?.invalidate()
            volumeObservation = nil
        }
    }
}
