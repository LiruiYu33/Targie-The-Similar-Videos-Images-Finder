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
import AppKit
import QuartzCore
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

// MARK: - Browse Media Preview (with video playback via native AVPlayerLayer)

struct BrowseMediaPreview: View {
    let media: MediaItem

    var body: some View {
        Group {
            if media.kind == .video {
                VideoPlaybackPreview(media: media)
                    .id(media.id)
                    .aspectRatio(16 / 9, contentMode: .fit)
            } else if let image = MediaThumbnailImageCache.shared.image(for: media) {
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

struct VideoPlaybackPreview: View {
    let media: MediaItem
    @AppStorage(NativeVideoPlayerVolumeSync.defaultsKey) private var playerVolume = 0.5
    @State private var isPlaying = false

    var body: some View {
        ZStack(alignment: isPlaying ? .bottomTrailing : .center) {
            videoPlaceholder
            NativeVideoPlayerView(url: media.url, volume: $playerVolume, isPlaying: $isPlaying)
                .opacity(isPlaying ? 1 : 0)

            Button {
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: isPlaying ? 16 : 28, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: isPlaying ? 34 : 58, height: isPlaying ? 34 : 58)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(isPlaying ? 12 : 0)
        }
        .background(Color.black.opacity(0.88))
        .onChange(of: media.id) { _, _ in
            isPlaying = false
        }
    }

    @ViewBuilder
    private var videoPlaceholder: some View {
        if let image = MediaThumbnailImageCache.shared.image(for: media) {
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
}

// MARK: - Native AVPlayerLayer wrapped for SwiftUI

/// Wraps an `AVPlayerLayer` in an `NSViewRepresentable`.
/// This avoids SwiftUI `VideoPlayer` crashes and avoids `AVPlayerView`'s
/// native controls, whose key-view updates can recurse through SwiftUI focus.
struct NativeVideoPlayerView: NSViewRepresentable {
    let url: URL
    @Binding var volume: Double
    @Binding var isPlaying: Bool

    func makeNSView(context: Context) -> NativeVideoPlayerContainerView {
        let view = NativeVideoPlayerContainerView()
        NativeVideoPlayerConfigurator.configure(view)
        let player = AVPlayer()
        player.volume = Float(volume)
        view.playerLayer.player = player
        context.coordinator.observeVolume(on: player)
        return view
    }

    func updateNSView(_ nsView: NativeVideoPlayerContainerView, context: Context) {
        context.coordinator.volume = $volume
        context.coordinator.playerView = nsView
        context.coordinator.updatePlayer(in: nsView, url: url, volume: volume, isPlaying: isPlaying)
    }

    static func dismantleNSView(_ nsView: NativeVideoPlayerContainerView, coordinator: Coordinator) {
        coordinator.releaseCurrentPlayer(from: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(volume: $volume)
    }

    class Coordinator {
        var currentURL: URL?
        var volume: Binding<Double>
        weak var playerView: NativeVideoPlayerContainerView?
        private var volumeObservation: NSKeyValueObservation?
        private weak var observedPlayer: AVPlayer?
        private let playerTeardown: @MainActor (AVPlayer) -> Void

        init(
            volume: Binding<Double>,
            playerTeardown: @escaping @MainActor (AVPlayer) -> Void = NativeVideoPlayerTeardown.release
        ) {
            self.volume = volume
            self.playerTeardown = playerTeardown
        }

        @MainActor
        func updatePlayer(in playerView: NativeVideoPlayerContainerView, url: URL, volume: Double, isPlaying: Bool) {
            let player = player(for: playerView, volume: volume)
            if NativeVideoPlayerVolumeSync.shouldApply(boundVolume: volume, toPlayerVolume: player.volume) {
                player.volume = Float(volume)
            }

            guard isPlaying else {
                player.pause()
                if currentURL != nil || player.currentItem != nil {
                    player.replaceCurrentItem(with: nil)
                }
                currentURL = nil
                return
            }

            guard currentURL != url else {
                player.play()
                return
            }

            player.pause()
            if FileManager.default.fileExists(atPath: url.path) {
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                currentURL = url
                if isPlaying {
                    player.play()
                }
            } else {
                player.replaceCurrentItem(with: nil)
                currentURL = nil
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
        func releaseCurrentPlayer(from playerView: NativeVideoPlayerContainerView) {
            removeVolumeObservation()
            currentURL = nil
            if let player = playerView.playerLayer.player {
                playerTeardown(player)
            }
        }

        @MainActor
        private func player(for playerView: NativeVideoPlayerContainerView, volume: Double) -> AVPlayer {
            if let player = playerView.playerLayer.player {
                observeVolume(on: player)
                return player
            }

            let player = AVPlayer()
            player.volume = Float(volume)
            playerView.playerLayer.player = player
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

final class NativeVideoPlayerContainerView: NSView {
    let playerLayer = AVPlayerLayer()

    override var acceptsFirstResponder: Bool { false }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
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
    static func configure(_ view: NativeVideoPlayerContainerView) {
        view.wantsLayer = true
        if view.layer == nil {
            view.layer = CALayer()
        }
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.playerLayer.videoGravity = .resizeAspect
        if view.playerLayer.superlayer !== view.layer {
            view.layer?.addSublayer(view.playerLayer)
        }
    }
}
