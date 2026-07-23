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

import AVFoundation
import AVKit
import AppKit
import SwiftUI

struct BrowsePreviewPanel: View {
    @ObservedObject var browseModel: BrowseViewModel
    @Environment(\.appLanguage) private var language

    var body: some View {
        Group {
            if browseModel.hasMultipleSelection {
                BrowseStackedPreview(browseModel: browseModel, language: language)
            } else if let media = browseModel.selectedMedia {
                VStack(spacing: 0) {
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
        .navigationTitle("")
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
            Button { browseModel.scanModel.openMedia(media) } label: {
                Label(L10n.openDefaultPlayer(language), systemImage: "play.rectangle")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        case .showInFinder:
            Button { browseModel.scanModel.revealMedia(media) } label: {
                Label(L10n.showInFinder(language), systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        case .deleteFile:
            Button(role: .destructive) {
                browseModel.scanModel.requestDeletion(of: media)
            } label: {
                Label(L10n.deleteMedia(language), systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        case .deleteSelection:
            EmptyView()
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

                let multiActions = PreviewActionArrangement.multipleSelectionActions()
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        ForEach(multiActions, id: \.self) { action in
                            actionButton(action)
                        }
                    }
                    VStack(spacing: 8) {
                        ForEach(multiActions, id: \.self) { action in
                            actionButton(action)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

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

    @ViewBuilder
    private func actionButton(_ action: PreviewActionKind) -> some View {
        switch action {
        case .showInFinder:
            if let first = selectedItems.first {
                Button { browseModel.scanModel.revealMedia(first) } label: {
                    Label(L10n.showInFinder(language), systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        case .deleteSelection:
            Button(role: .destructive) {
                browseModel.scanModel.requestDeletion(of: selectedItems)
            } label: {
                Label(L10n.deleteSelected(selectedItems.count, language), systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        case .openDefaultPlayer, .deleteFile:
            EmptyView()
        }
    }
}

// MARK: - Browse Media Preview (with video playback via native AVPlayerView)

struct BrowseMediaPreview: View {
    let media: MediaItem

    var body: some View {
        Group {
            if media.kind == .video {
                VideoPlaybackPreview(media: media)
                    .id(media.id)
                    .aspectRatio(16 / 9, contentMode: .fit)
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    MediaThumbnailView(
                        item: media,
                        placeholderSystemImage: "photo",
                        placeholderFont: .system(size: 42)
                    )
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

struct VideoPlaybackPreview: View {
    let media: MediaItem
    @AppStorage(NativeVideoPlayerVolumeSync.defaultsKey) private var playerVolume = 0.5
    @State private var isPlaying = false

    var body: some View {
        ZStack {
            videoPlaceholder
            NativeVideoPlayerView(url: media.url, volume: $playerVolume, isPlaying: $isPlaying)
                .opacity(isPlaying ? 1 : 0)

            // Centered Play button to start playback. Once playing, the native
            // AVPlayerView controls take over - there is no overlay pause button.
            if !isPlaying {
                Button {
                    isPlaying.toggle()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 58, height: 58)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.black.opacity(0.88))
        .onChange(of: media.id) { _, _ in
            isPlaying = false
        }
    }

    @ViewBuilder
    private var videoPlaceholder: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            MediaThumbnailView(
                item: media,
                placeholderSystemImage: "film",
                placeholderFont: .system(size: 42)
            )
        }
    }
}

// MARK: - Native AVPlayerView wrapped for SwiftUI

/// Wraps AppKit's `AVPlayerView` in an `NSViewRepresentable`.
///
/// `AVPlayerView`'s native inline controls provide full-screen (same-window
/// macOS fullscreen space, not a separate window) and Picture-in-Picture out of
/// the box, which is why we use it instead of a bare `AVPlayerLayer`.
///
/// Switching the previewed video no longer freezes the UI because the player
/// item is loaded lazily (only while `isPlaying`), a single persistent `AVPlayer`
/// is reused via `replaceCurrentItem` (never a whole-player swap), and the URL
/// change path pauses before replacing — without the `cancelPendingSeeks` /
/// `asset.cancelLoading` calls that conflicted with SwiftUI's diff loop.
struct NativeVideoPlayerView: NSViewRepresentable {
    let url: URL
    @Binding var volume: Double
    @Binding var isPlaying: Bool

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        NativeVideoPlayerConfigurator.configure(view)
        view.player = nil
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        context.coordinator.volume = $volume
        context.coordinator.playerView = nsView
        context.coordinator.updatePlayer(in: nsView, url: url, volume: volume, isPlaying: isPlaying)
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.releaseCurrentPlayer(from: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(volume: $volume)
    }

    class Coordinator {
        var currentURL: URL?
        var volume: Binding<Double>
        weak var playerView: AVPlayerView?
        private var volumeObservation: NSKeyValueObservation?
        private weak var observedPlayer: AVPlayer?
        private var isPlaybackRequested = false
        private let commands: NativeVideoPlayerCommands
        private let playerTeardown: @MainActor (AVPlayer) -> Void

        @MainActor
        init(
            volume: Binding<Double>,
            commands: NativeVideoPlayerCommands = .live,
            playerTeardown: @escaping @MainActor (AVPlayer) -> Void = NativeVideoPlayerTeardown.release
        ) {
            self.volume = volume
            self.commands = commands
            self.playerTeardown = playerTeardown
        }

        @MainActor
        func updatePlayer(in playerView: AVPlayerView, url: URL, volume: Double, isPlaying: Bool) {
            let player = player(for: playerView, volume: volume)
            if NativeVideoPlayerVolumeSync.shouldApply(boundVolume: volume, toPlayerVolume: player.volume) {
                player.volume = Float(volume)
            }

            guard isPlaying else {
                if isPlaybackRequested {
                    commands.pause(player)
                }
                if currentURL != nil || player.currentItem != nil {
                    commands.replaceCurrentItem(player, nil)
                }
                currentURL = nil
                isPlaybackRequested = false
                return
            }

            guard currentURL != url else {
                if !isPlaybackRequested {
                    isPlaybackRequested = true
                    commands.play(player)
                }
                return
            }

            // pause-before-replace: avoids stalling the SwiftUI diff loop that
            // whole-player swaps and cancelPendingSeeks triggered previously.
            if currentURL != nil || player.currentItem != nil || isPlaybackRequested {
                commands.pause(player)
            }
            if FileManager.default.fileExists(atPath: url.path) {
                commands.replaceCurrentItem(player, AVPlayerItem(url: url))
                currentURL = url
                isPlaybackRequested = true
                commands.play(player)
            } else {
                if player.currentItem != nil {
                    commands.replaceCurrentItem(player, nil)
                }
                currentURL = nil
                isPlaybackRequested = false
            }
        }

        func observeVolume(on player: AVPlayer) {
            guard observedPlayer !== player else { return }
            removeVolumeObservation()
            observedPlayer = player
            volumeObservation = player.observe(\.volume, options: [.new]) { player, _ in
                guard NativeVideoPlayerVolumeSync.shouldPersist(
                    playerVolume: player.volume,
                    storedVolume: UserDefaults.standard.double(forKey: NativeVideoPlayerVolumeSync.defaultsKey)
                ) else {
                    return
                }
                UserDefaults.standard.set(Double(player.volume), forKey: NativeVideoPlayerVolumeSync.defaultsKey)
            }
        }

        @MainActor
        func releaseCurrentPlayer(from playerView: AVPlayerView) {
            removeVolumeObservation()
            currentURL = nil
            isPlaybackRequested = false
            if let player = playerView.player {
                playerTeardown(player)
            }
        }

        @MainActor
        private func player(for playerView: AVPlayerView, volume: Double) -> AVPlayer {
            if let player = playerView.player {
                observeVolume(on: player)
                return player
            }

            let player = AVPlayer()
            player.volume = Float(volume)
            playerView.player = player
            observeVolume(on: player)
            return player
        }

        private func removeVolumeObservation() {
            volumeObservation?.invalidate()
            volumeObservation = nil
            observedPlayer = nil
        }
    }
}

struct NativeVideoPlayerCommands {
    let play: @MainActor (AVPlayer) -> Void
    let pause: @MainActor (AVPlayer) -> Void
    let replaceCurrentItem: @MainActor (AVPlayer, AVPlayerItem?) -> Void

    static let live = NativeVideoPlayerCommands(
        play: { $0.play() },
        pause: { $0.pause() },
        replaceCurrentItem: { $0.replaceCurrentItem(with: $1) }
    )
}

enum NativeVideoPlayerVolumeSync {
    static let defaultsKey = "browsePreviewPlayerVolume"
    private static let tolerance = 0.001

    static func shouldApply(boundVolume: Double, toPlayerVolume playerVolume: Float) -> Bool {
        abs(Double(playerVolume) - boundVolume) > tolerance
    }

    static func shouldPersist(playerVolume: Float, storedVolume: Double) -> Bool {
        abs(Double(playerVolume) - storedVolume) > tolerance
    }
}

enum NativeVideoPlayerTeardown {
    @MainActor
    static func release(_ player: AVPlayer) {
        player.pause()
    }
}

@MainActor
enum NativeVideoPlayerConfigurator {
    static func configure(_ view: AVPlayerView) {
        view.controlsStyle = .inline
        view.allowsPictureInPicturePlayback = true
        view.showsFullScreenToggleButton = true
    }
}
