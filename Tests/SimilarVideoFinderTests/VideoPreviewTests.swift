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
import XCTest
@testable import SimilarVideoFinder

@MainActor
final class VideoPreviewTests: XCTestCase {
    func testNativePlayerViewConfiguredWithInlineControlsAndFullScreen() {
        let playerView = AVPlayerView()

        NativeVideoPlayerConfigurator.configure(playerView)

        XCTAssertEqual(playerView.controlsStyle, .inline)
        XCTAssertTrue(playerView.allowsPictureInPicturePlayback)
        XCTAssertTrue(playerView.showsFullScreenToggleButton)
    }

    func testCoordinatorKeepsPlayerAttachedWhenReleasingCurrentPlayer() {
        let playerView = AVPlayerView()
        let player = AVPlayer()
        playerView.player = player
        let coordinator = NativeVideoPlayerView.Coordinator(volume: .constant(0.5))

        coordinator.releaseCurrentPlayer(from: playerView)

        XCTAssertTrue(playerView.player === player)
        XCTAssertNil(player.currentItem)
    }

    func testCoordinatorKeepsPlayerAttachedBeforeTeardownRuns() {
        let playerView = AVPlayerView()
        let player = AVPlayer()
        playerView.player = player
        var playerInViewDuringTeardown: AVPlayer?
        var tornDownPlayer: AVPlayer?
        let coordinator = NativeVideoPlayerView.Coordinator(volume: .constant(0.5)) { player in
            playerInViewDuringTeardown = playerView.player
            tornDownPlayer = player
        }

        coordinator.currentURL = URL(fileURLWithPath: "/tmp/current.mov")
        coordinator.releaseCurrentPlayer(from: playerView)

        XCTAssertTrue(playerInViewDuringTeardown === player)
        XCTAssertTrue(tornDownPlayer === player)
        XCTAssertTrue(playerView.player === player)
        XCTAssertNil(coordinator.currentURL)
    }

    func testCoordinatorDoesNotLoadPlayerItemUntilPlaybackStarts() throws {
        let firstURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewSwitchA-\(UUID().uuidString).mov")
        let secondURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewSwitchB-\(UUID().uuidString).mov")
        try Data([0]).write(to: firstURL)
        try Data([1]).write(to: secondURL)
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }
        let playerView = AVPlayerView()
        let player = AVPlayer()
        playerView.player = player
        let coordinator = NativeVideoPlayerView.Coordinator(volume: .constant(0.5))

        coordinator.updatePlayer(in: playerView, url: firstURL, volume: 0.5, isPlaying: false)
        coordinator.updatePlayer(in: playerView, url: secondURL, volume: 0.5, isPlaying: false)

        XCTAssertTrue(playerView.player === player)
        XCTAssertNil(player.currentItem)
        XCTAssertNil(coordinator.currentURL)
    }

    func testCoordinatorReusesAttachedPlayerWhenSwitchingPlayingURLs() throws {
        let firstURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewPlayingSwitchA-\(UUID().uuidString).mov")
        let secondURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewPlayingSwitchB-\(UUID().uuidString).mov")
        try Data([0]).write(to: firstURL)
        try Data([1]).write(to: secondURL)
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }
        let playerView = AVPlayerView()
        let player = AVPlayer()
        playerView.player = player
        let coordinator = NativeVideoPlayerView.Coordinator(volume: .constant(0.5))

        coordinator.updatePlayer(in: playerView, url: firstURL, volume: 0.5, isPlaying: true)
        coordinator.updatePlayer(in: playerView, url: secondURL, volume: 0.5, isPlaying: true)

        XCTAssertTrue(playerView.player === player)
        XCTAssertEqual(coordinator.currentURL, secondURL)
    }

    func testRepeatedPlayingUpdateForSameURLIssuesOnePlayCommand() throws {
        let url = try temporaryPlayableURL(named: "PreviewRepeatedPlay")
        defer { try? FileManager.default.removeItem(at: url) }
        let playerView = AVPlayerView()
        playerView.player = AVPlayer()
        let recorder = PlayerCommandRecorder()
        let coordinator = NativeVideoPlayerView.Coordinator(
            volume: .constant(0.5),
            commands: recorder.commands
        )

        coordinator.updatePlayer(in: playerView, url: url, volume: 0.5, isPlaying: true)
        coordinator.updatePlayer(in: playerView, url: url, volume: 0.5, isPlaying: true)

        XCTAssertEqual(recorder.events, ["replace", "play"])
    }

    func testVolumeUpdateDoesNotResumeNativePausedPlayer() throws {
        let url = try temporaryPlayableURL(named: "PreviewNativePause")
        defer { try? FileManager.default.removeItem(at: url) }
        let playerView = AVPlayerView()
        let player = AVPlayer()
        playerView.player = player
        let recorder = PlayerCommandRecorder()
        let coordinator = NativeVideoPlayerView.Coordinator(
            volume: .constant(0.5),
            commands: recorder.commands
        )

        coordinator.updatePlayer(in: playerView, url: url, volume: 0.5, isPlaying: true)
        player.pause()
        coordinator.updatePlayer(in: playerView, url: url, volume: 0.7, isPlaying: true)

        XCTAssertEqual(recorder.events.filter { $0 == "play" }.count, 1)
    }

    func testPlayingURLChangePausesBeforeReplacingAndStartingOnce() throws {
        let firstURL = try temporaryPlayableURL(named: "PreviewCommandOrderA")
        let secondURL = try temporaryPlayableURL(named: "PreviewCommandOrderB")
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }
        let playerView = AVPlayerView()
        playerView.player = AVPlayer()
        let recorder = PlayerCommandRecorder()
        let coordinator = NativeVideoPlayerView.Coordinator(
            volume: .constant(0.5),
            commands: recorder.commands
        )
        coordinator.updatePlayer(in: playerView, url: firstURL, volume: 0.5, isPlaying: true)
        recorder.events.removeAll()

        coordinator.updatePlayer(in: playerView, url: secondURL, volume: 0.5, isPlaying: true)

        XCTAssertEqual(recorder.events, ["pause", "replace", "play"])
    }

    func testRepeatedStoppedUpdatePausesAndClearsOnlyOnce() throws {
        let url = try temporaryPlayableURL(named: "PreviewRepeatedStop")
        defer { try? FileManager.default.removeItem(at: url) }
        let playerView = AVPlayerView()
        playerView.player = AVPlayer()
        let recorder = PlayerCommandRecorder()
        let coordinator = NativeVideoPlayerView.Coordinator(
            volume: .constant(0.5),
            commands: recorder.commands
        )
        coordinator.updatePlayer(in: playerView, url: url, volume: 0.5, isPlaying: true)
        recorder.events.removeAll()

        coordinator.updatePlayer(in: playerView, url: url, volume: 0.5, isPlaying: false)
        coordinator.updatePlayer(in: playerView, url: url, volume: 0.5, isPlaying: false)

        XCTAssertEqual(recorder.events, ["pause", "clear"])
    }

    func testVolumeSyncIgnoresEffectivelyUnchangedValues() {
        XCTAssertFalse(NativeVideoPlayerVolumeSync.shouldApply(boundVolume: 0.5, toPlayerVolume: 0.5))
        XCTAssertFalse(NativeVideoPlayerVolumeSync.shouldPersist(playerVolume: 0.5, storedVolume: 0.5004))
        XCTAssertTrue(NativeVideoPlayerVolumeSync.shouldApply(boundVolume: 0.7, toPlayerVolume: 0.5))
        XCTAssertTrue(NativeVideoPlayerVolumeSync.shouldPersist(playerVolume: 0.7, storedVolume: 0.5))
    }

    func testDefaultTeardownDoesNotForceReplaceCurrentItem() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewTeardown-\(UUID().uuidString).mov")
        try Data([0]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)

        NativeVideoPlayerTeardown.release(player)
        try await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertTrue(player.currentItem === item)
        XCTAssertEqual(player.rate, 0)
    }

    private func temporaryPlayableURL(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).mov")
        try Data([0]).write(to: url)
        return url
    }

}

@MainActor
private final class PlayerCommandRecorder {
    var events: [String] = []

    var commands: NativeVideoPlayerCommands {
        NativeVideoPlayerCommands(
            play: { [weak self] _ in self?.events.append("play") },
            pause: { [weak self] player in
                self?.events.append("pause")
                player.pause()
            },
            replaceCurrentItem: { [weak self] player, item in
                self?.events.append(item == nil ? "clear" : "replace")
                player.replaceCurrentItem(with: item)
            }
        )
    }
}
