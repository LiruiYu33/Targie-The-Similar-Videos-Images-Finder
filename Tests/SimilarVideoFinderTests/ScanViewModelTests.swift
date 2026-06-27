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

import Combine
import XCTest
@testable import SimilarVideoFinder

@MainActor
final class ScanViewModelTests: XCTestCase {
    func testAddingFoldersKeepsMultipleUniqueDirectoriesAndRejectsFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderSelection-\(UUID().uuidString)", isDirectory: true)
        let first = root.appendingPathComponent("first", isDirectory: true)
        let second = root.appendingPathComponent("second", isDirectory: true)
        let file = root.appendingPathComponent("notes.txt")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ScanViewModel(hashCache: nil)

        let added = model.addFolders([first, second, first, file])

        XCTAssertTrue(added)
        XCTAssertEqual(model.selectedFolders, [first, second])
    }

    func testClearFoldersRemovesAllSelectedFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClearFolders-\(UUID().uuidString)", isDirectory: true)
        let first = root.appendingPathComponent("first", isDirectory: true)
        let second = root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let model = ScanViewModel(hashCache: nil)
        model.selectedFolders = [first, second]

        let cleared = model.clearFolders()

        XCTAssertTrue(cleared)
        XCTAssertTrue(model.selectedFolders.isEmpty)
    }

    func testVideoScanComparesFilesAcrossSelectedFolders() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultiFolderScan-\(UUID().uuidString)", isDirectory: true)
        let first = root.appendingPathComponent("first", isDirectory: true)
        let second = root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try Data().write(to: first.appendingPathComponent("a.mp4"))
        try Data().write(to: second.appendingPathComponent("b.mp4"))
        defer { try? FileManager.default.removeItem(at: root) }

        let scanner = VideoScanner(maxConcurrentLoads: 2) { url in
            MediaItem(
                kind: .video,
                url: url,
                fileSize: 1,
                duration: 1,
                width: 16,
                height: 9,
                modifiedAt: nil,
                thumbnailData: nil
            )
        }
        let model = ScanViewModel(
            scanner: scanner,
            pipeline: ExactDuplicatePipeline(),
            hashCache: nil
        )
        model.scanMode = .videos
        model.selectedFolders = [first, second]

        model.startScan()
        try await waitUntil { model.progress.stage == .completed }

        XCTAssertEqual(model.groups.count, 1)
        XCTAssertEqual(Set(model.groups[0].items.map { $0.url.standardizedFileURL.path }), [
            first.appendingPathComponent("a.mp4").standardizedFileURL.path,
            second.appendingPathComponent("b.mp4").standardizedFileURL.path
        ])
    }

    func testDefaultScannerUsesInjectedMetadataCache() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetadataCacheScan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cachedVideo = root.appendingPathComponent("cached.mp4")
        try Data([1, 2, 3]).write(to: cachedVideo)
        let cache = MetadataHitCache()
        let model = ScanViewModel(
            pipeline: ExactDuplicatePipeline(),
            hashCache: cache,
            thumbnailStore: ThumbnailStore(directoryURL: root.appendingPathComponent("thumbs", isDirectory: true))
        )
        model.scanMode = .videos
        model.selectedFolders = [root]

        model.startScan()
        try await waitUntil { model.progress.stage == .completed }

        XCTAssertEqual(model.items.map { $0.url.standardizedFileURL.path }, [cachedVideo.standardizedFileURL.path])
        let metadataLookups = await cache.metadataLookupCount()
        XCTAssertEqual(metadataLookups, 1)
    }

    func testVideoAndImageScansStartConcurrently() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParallelKindScan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: root.appendingPathComponent("clip.mp4"))
        try Data([2]).write(to: root.appendingPathComponent("photo.jpg"))
        let tracker = CrossKindScanTracker()
        let scanner = VideoScanner(maxConcurrentLoads: 1) { url in
            await tracker.videoStarted()
            await tracker.waitForImageStarted()
            return MediaItem(
                kind: .video,
                url: url,
                fileSize: 1,
                duration: 1,
                width: 16,
                height: 9,
                modifiedAt: nil,
                thumbnailData: nil
            )
        }
        let imageScanner = ImageScanner(maxConcurrentLoads: 1) { url in
            await tracker.imageStarted()
            return MediaItem(
                kind: .image,
                url: url,
                fileSize: 1,
                duration: nil,
                width: 16,
                height: 9,
                modifiedAt: nil,
                thumbnailData: Data([1])
            )
        }
        let model = ScanViewModel(
            scanner: scanner,
            imageScanner: imageScanner,
            pipeline: ExactDuplicatePipeline(),
            hashCache: nil
        )
        model.selectedFolders = [root]
        defer { model.cancelScan() }

        model.startScan()
        try await waitUntilAsync(timeoutIterations: 100) { await tracker.bothStarted() }

        let bothStarted = await tracker.bothStarted()
        XCTAssertTrue(bothStarted)
    }

    func testConcurrentKindProgressDoesNotMoveBackward() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParallelProgress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: root.appendingPathComponent("clip.mp4"))
        try Data([2]).write(to: root.appendingPathComponent("a.jpg"))
        try Data([3]).write(to: root.appendingPathComponent("b.jpg"))

        let tracker = CrossKindProgressTracker()
        let scanner = VideoScanner(maxConcurrentLoads: 1) { url in
            MediaItem(
                kind: .video,
                url: url,
                fileSize: 1,
                duration: 1,
                width: 16,
                height: 9,
                modifiedAt: nil,
                thumbnailData: nil
            )
        }
        let imageScanner = ImageScanner(maxConcurrentLoads: 1) { url in
            await tracker.waitForVideoComparingProgress()
            return MediaItem(
                kind: .image,
                url: url,
                fileSize: 1,
                duration: nil,
                width: 16,
                height: 9,
                modifiedAt: nil,
                thumbnailData: Data([1])
            )
        }
        let model = ScanViewModel(
            scanner: scanner,
            imageScanner: imageScanner,
            pipeline: ProgressReportingPipeline(tracker: tracker),
            hashCache: nil
        )
        var fractions: [Double] = []
        let cancellable = model.$progress.sink { progress in
            fractions.append(progress.fraction)
        }
        defer {
            cancellable.cancel()
            model.cancelScan()
        }

        model.selectedFolders = [root]
        model.startScan()
        try await waitUntil { model.progress.stage == .completed }

        let regressions = zip(fractions, fractions.dropFirst()).filter { previous, next in
            next < previous
        }
        XCTAssertTrue(regressions.isEmpty, "Progress moved backward: \(fractions)")
    }

    func testDeletePromptStartsByChoosingMethod() {
        let model = ScanViewModel()
        model.requestDeletion(of: SimilarityScoringTests.video(name: "a.mov"))
        XCTAssertEqual(model.deletePrompt?.step, .choosingMethod)
    }

    func testRevealIssueOpensSkippedFileLocationInFinder() {
        let deletion = FakeDeletionService()
        let model = ScanViewModel(deletionService: deletion)
        let skippedURL = URL(fileURLWithPath: "/tmp/TargieSkipped/broken.mp4")
        let issue = ScanIssue(url: skippedURL, reason: .noVideoTrack)

        model.revealIssue(issue)

        XCTAssertEqual(deletion.revealedURLs, [skippedURL])
    }

    func testSuccessfulDeletionDropsSingletonGroup() async {
        let a = SimilarityScoringTests.video(name: "a.mov")
        let b = SimilarityScoringTests.video(name: "b.mov")
        let relation = SimilarityRelation(firstID: a.id, secondID: b.id, score: 0.95, evidence: [.similarFrames])
        let deletion = FakeDeletionService()
        let model = ScanViewModel(deletionService: deletion)
        model.replaceResultsForTesting(items: [a, b], relations: [relation])

        await model.confirmDeletion(of: b, mode: .permanent)

        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertEqual(deletion.deletedURLs, [b.url])
    }

    func testDeletingBridgeItemKeepsGroupWhenTwoFilesRemain() async {
        let a = SimilarityScoringTests.video(name: "a.mov")
        let b = SimilarityScoringTests.video(name: "b.mov")
        let c = SimilarityScoringTests.video(name: "c.mov")
        let relations = [
            SimilarityRelation(firstID: a.id, secondID: b.id, score: 0.94, evidence: [.similarFrames]),
            SimilarityRelation(firstID: b.id, secondID: c.id, score: 0.91, evidence: [.similarPerceptualHash])
        ]
        let model = ScanViewModel(deletionService: FakeDeletionService())
        model.replaceResultsForTesting(items: [a, b, c], relations: relations)

        await model.confirmDeletion(of: b, mode: .permanent)

        XCTAssertEqual(model.groups.count, 1)
        XCTAssertEqual(Set(model.groups[0].items.map(\.id)), [a.id, c.id])
    }

    func testDeletingOneOfThreeFilesKeepsSelectedGroupIdentityWhenPairRemains() async {
        let a = SimilarityScoringTests.video(name: "a.mov")
        let b = SimilarityScoringTests.video(name: "b.mov")
        let c = SimilarityScoringTests.video(name: "c.mov")
        let relations = [
            SimilarityRelation(firstID: a.id, secondID: b.id, score: 0.95, evidence: [.similarFrames]),
            SimilarityRelation(firstID: b.id, secondID: c.id, score: 0.94, evidence: [.similarFrames]),
            SimilarityRelation(firstID: a.id, secondID: c.id, score: 0.93, evidence: [.similarFrames])
        ]
        let model = ScanViewModel(deletionService: FakeDeletionService())
        model.replaceResultsForTesting(items: [a, b, c], relations: relations)
        let originalGroupID = model.groups[0].id
        model.selectGroup(originalGroupID)

        await model.confirmDeletion(of: b, mode: .permanent)

        XCTAssertEqual(model.groups.count, 1)
        XCTAssertEqual(model.groups[0].id, originalGroupID)
        XCTAssertEqual(model.selectedGroupID, originalGroupID)
        XCTAssertEqual(Set(model.groups[0].items.map(\.id)), [a.id, c.id])
    }

    func testDeletingOneImageFromTripletImageGroupKeepsSelection() async {
        let a = MediaItem(kind: .image, url: URL(fileURLWithPath: "/tmp/a.png"), fileSize: 1_000, duration: nil, width: 100, height: 100, modifiedAt: nil, thumbnailData: nil)
        let b = MediaItem(kind: .image, url: URL(fileURLWithPath: "/tmp/b.png"), fileSize: 1_000, duration: nil, width: 100, height: 100, modifiedAt: nil, thumbnailData: nil)
        let c = MediaItem(kind: .image, url: URL(fileURLWithPath: "/tmp/c.png"), fileSize: 1_000, duration: nil, width: 100, height: 100, modifiedAt: nil, thumbnailData: nil)
        let relations = [
            SimilarityRelation(firstID: a.id, secondID: b.id, score: 0.95, evidence: [.similarPerceptualHash]),
            SimilarityRelation(firstID: b.id, secondID: c.id, score: 0.94, evidence: [.similarPerceptualHash]),
            SimilarityRelation(firstID: a.id, secondID: c.id, score: 0.93, evidence: [.similarPerceptualHash])
        ]
        let model = ScanViewModel(deletionService: FakeDeletionService())
        model.replaceResultsForTesting(items: [a, b, c], relations: relations)
        model.setScanMode(.images)
        let originalGroupID = model.groups[0].id
        model.selectGroup(originalGroupID)

        await model.confirmDeletion(of: b, mode: .trash)

        XCTAssertEqual(model.groups.count, 1, "triplet → pair, group survives")
        XCTAssertEqual(model.selectedGroupID, originalGroupID, "same group must stay selected")
    }

    func testDeletingDissolvedGroupSelectsNextGroupNotFirst() async {
        // Three independent duplicate pairs → three groups. Distinct scores pin
        // the display order (highest score first) so the test is deterministic.
        let a = SimilarityScoringTests.video(name: "a.mov")
        let b = SimilarityScoringTests.video(name: "b.mov")
        let c = SimilarityScoringTests.video(name: "c.mov")
        let d = SimilarityScoringTests.video(name: "d.mov")
        let e = SimilarityScoringTests.video(name: "e.mov")
        let f = SimilarityScoringTests.video(name: "f.mov")
        let relations = [
            SimilarityRelation(firstID: a.id, secondID: b.id, score: 0.95, evidence: [.similarFrames]),
            SimilarityRelation(firstID: c.id, secondID: d.id, score: 0.92, evidence: [.similarFrames]),
            SimilarityRelation(firstID: e.id, secondID: f.id, score: 0.90, evidence: [.similarFrames])
        ]
        let model = ScanViewModel(deletionService: FakeDeletionService())
        model.replaceResultsForTesting(items: [a, b, c, d, e, f], relations: relations)
        XCTAssertEqual(model.groups.count, 3)
        let middleGroupID = model.groups[1].id
        let nextGroupID = model.groups[2].id
        model.selectGroup(middleGroupID)

        // Delete one file of the middle pair → that group dissolves.
        await model.confirmDeletion(of: c, mode: .permanent)

        XCTAssertEqual(model.groups.count, 2)
        XCTAssertEqual(model.selectedGroupID, nextGroupID)
    }

    func testDeletingLastDissolvedGroupSelectsPrecedingGroup() async {
        let a = SimilarityScoringTests.video(name: "a.mov")
        let b = SimilarityScoringTests.video(name: "b.mov")
        let c = SimilarityScoringTests.video(name: "c.mov")
        let d = SimilarityScoringTests.video(name: "d.mov")
        let e = SimilarityScoringTests.video(name: "e.mov")
        let f = SimilarityScoringTests.video(name: "f.mov")
        let relations = [
            SimilarityRelation(firstID: a.id, secondID: b.id, score: 0.95, evidence: [.similarFrames]),
            SimilarityRelation(firstID: c.id, secondID: d.id, score: 0.92, evidence: [.similarFrames]),
            SimilarityRelation(firstID: e.id, secondID: f.id, score: 0.90, evidence: [.similarFrames])
        ]
        let model = ScanViewModel(deletionService: FakeDeletionService())
        model.replaceResultsForTesting(items: [a, b, c, d, e, f], relations: relations)
        XCTAssertEqual(model.groups.count, 3)
        let lastGroupID = model.groups[2].id
        let precedingGroupID = model.groups[1].id
        model.selectGroup(lastGroupID)

        // Delete one file of the last pair → that group dissolves; no group
        // follows it, so selection should fall back to the preceding group.
        await model.confirmDeletion(of: e, mode: .permanent)

        XCTAssertEqual(model.groups.count, 2)
        XCTAssertEqual(model.selectedGroupID, precedingGroupID)
    }

    func testDeletingDissolvedGroupKeepsCursorPositionNotRecombinedFarGroup() async {
        // Three pairs. The middle pair (c,d) sits at list index 1. After deleting
        // c, that pair dissolves — but d is unrelated to anything else, so no
        // far-off group absorbs it. Selection should stay at the visual position
        // of the dissolved group (index 1), landing on whatever group now holds
        // that slot — not jump to a reshuffled group far down the list.
        let a = SimilarityScoringTests.video(name: "a.mov")
        let b = SimilarityScoringTests.video(name: "b.mov")
        let c = SimilarityScoringTests.video(name: "c.mov")
        let d = SimilarityScoringTests.video(name: "d.mov")
        let e = SimilarityScoringTests.video(name: "e.mov")
        let f = SimilarityScoringTests.video(name: "f.mov")
        let relations = [
            SimilarityRelation(firstID: a.id, secondID: b.id, score: 0.95, evidence: [.similarFrames]),
            SimilarityRelation(firstID: c.id, secondID: d.id, score: 0.92, evidence: [.similarFrames]),
            SimilarityRelation(firstID: e.id, secondID: f.id, score: 0.90, evidence: [.similarFrames])
        ]
        let model = ScanViewModel(deletionService: FakeDeletionService())
        model.replaceResultsForTesting(items: [a, b, c, d, e, f], relations: relations)
        XCTAssertEqual(model.groups.count, 3)
        let middleGroupID = model.groups[1].id
        let groupAtSameIndexAfter = model.groups[2].id // shifts into index 1 once middle dissolves
        model.selectGroup(middleGroupID)
        let selectedIndex = model.groups.firstIndex(where: { $0.id == middleGroupID })

        await model.confirmDeletion(of: c, mode: .permanent)

        XCTAssertEqual(model.groups.count, 2)
        XCTAssertEqual(model.selectedGroupID, groupAtSameIndexAfter)
        // The new selection sits at the same list index the cursor had before.
        XCTAssertEqual(
            model.groups.firstIndex(where: { $0.id == model.selectedGroupID }),
            selectedIndex
        )
    }

    func testDeletingVideoGroupInAllModeSelectsNextVideoNotFarImageGroup() async {
        // Two video pairs + two image pairs. Videos section comes first in
        // .all mode. Deleting a file from the first video group should dissolve
        // it and select the NEXT video group — not jump to an image group.
        let v1 = SimilarityScoringTests.video(name: "v1.mov")
        let v2 = SimilarityScoringTests.video(name: "v2.mov")
        let v3 = SimilarityScoringTests.video(name: "v3.mov")
        let v4 = SimilarityScoringTests.video(name: "v4.mov")
        let i1 = MediaItem(kind: .image, url: URL(fileURLWithPath: "/tmp/i1.png"), fileSize: 1_000, duration: nil, width: 100, height: 100, modifiedAt: nil, thumbnailData: nil)
        let i2 = MediaItem(kind: .image, url: URL(fileURLWithPath: "/tmp/i2.png"), fileSize: 1_000, duration: nil, width: 100, height: 100, modifiedAt: nil, thumbnailData: nil)
        let i3 = MediaItem(kind: .image, url: URL(fileURLWithPath: "/tmp/i3.png"), fileSize: 1_000, duration: nil, width: 100, height: 100, modifiedAt: nil, thumbnailData: nil)
        let i4 = MediaItem(kind: .image, url: URL(fileURLWithPath: "/tmp/i4.png"), fileSize: 1_000, duration: nil, width: 100, height: 100, modifiedAt: nil, thumbnailData: nil)
        let relations = [
            SimilarityRelation(firstID: v1.id, secondID: v2.id, score: 0.95, evidence: [.similarFrames]),
            SimilarityRelation(firstID: v3.id, secondID: v4.id, score: 0.94, evidence: [.similarFrames]),
            SimilarityRelation(firstID: i1.id, secondID: i2.id, score: 0.93, evidence: [.similarPerceptualHash]),
            SimilarityRelation(firstID: i3.id, secondID: i4.id, score: 0.92, evidence: [.similarPerceptualHash])
        ]
        let model = ScanViewModel(deletionService: FakeDeletionService())
        model.replaceResultsForTesting(items: [v1, v2, v3, v4, i1, i2, i3, i4], relations: relations)
        model.setScanMode(.all)
        let firstVideoGroupID = model.groups.first { $0.items.first?.kind == .video }!.id
        let secondVideoGroupID = model.groups.filter { $0.items.first?.kind == .video }[1].id
        model.selectGroup(firstVideoGroupID)

        await model.confirmDeletion(of: v1, mode: .permanent)

        // Should land on the next video group, not any image group.
        XCTAssertEqual(model.selectedGroupID, secondVideoGroupID)
        XCTAssertEqual(model.selectedGroup?.kind, .video)
    }

    func testDeletingLastVideoGroupInAllModeFallsBackToImageGroup() async {
        // One video pair + one image pair. Deleting the only video group's file
        // dissolves it; .all mode should then fall back to the image group.
        let v1 = SimilarityScoringTests.video(name: "v1.mov")
        let v2 = SimilarityScoringTests.video(name: "v2.mov")
        let i1 = MediaItem(kind: .image, url: URL(fileURLWithPath: "/tmp/i1.png"), fileSize: 1_000, duration: nil, width: 100, height: 100, modifiedAt: nil, thumbnailData: nil)
        let i2 = MediaItem(kind: .image, url: URL(fileURLWithPath: "/tmp/i2.png"), fileSize: 1_000, duration: nil, width: 100, height: 100, modifiedAt: nil, thumbnailData: nil)
        let relations = [
            SimilarityRelation(firstID: v1.id, secondID: v2.id, score: 0.95, evidence: [.similarFrames]),
            SimilarityRelation(firstID: i1.id, secondID: i2.id, score: 0.93, evidence: [.similarPerceptualHash])
        ]
        let model = ScanViewModel(deletionService: FakeDeletionService())
        model.replaceResultsForTesting(items: [v1, v2, i1, i2], relations: relations)
        model.setScanMode(.all)
        let imageGroupID = model.groups.first { $0.items.first?.kind == .image }!.id
        model.selectGroup(model.groups.first { $0.items.first?.kind == .video }!.id)

        await model.confirmDeletion(of: v1, mode: .permanent)

        XCTAssertEqual(model.selectedGroupID, imageGroupID)
    }

    func testDeletingVideoGroupInVideosModeDoesNotSelectImageGroup() async {
        // .videos mode hides image groups entirely. Deleting the last video
        // group's file dissolves it; selection must NOT jump to a (hidden)
        // image group — it clears instead.
        let v1 = SimilarityScoringTests.video(name: "v1.mov")
        let v2 = SimilarityScoringTests.video(name: "v2.mov")
        let i1 = MediaItem(kind: .image, url: URL(fileURLWithPath: "/tmp/i1.png"), fileSize: 1_000, duration: nil, width: 100, height: 100, modifiedAt: nil, thumbnailData: nil)
        let i2 = MediaItem(kind: .image, url: URL(fileURLWithPath: "/tmp/i2.png"), fileSize: 1_000, duration: nil, width: 100, height: 100, modifiedAt: nil, thumbnailData: nil)
        let relations = [
            SimilarityRelation(firstID: v1.id, secondID: v2.id, score: 0.95, evidence: [.similarFrames]),
            SimilarityRelation(firstID: i1.id, secondID: i2.id, score: 0.93, evidence: [.similarPerceptualHash])
        ]
        let model = ScanViewModel(deletionService: FakeDeletionService())
        model.replaceResultsForTesting(items: [v1, v2, i1, i2], relations: relations)
        model.setScanMode(.videos)
        model.selectGroup(model.groups.first { $0.items.first?.kind == .video }!.id)

        await model.confirmDeletion(of: v1, mode: .permanent)

        // No video group remains; selection clears rather than landing on a
        // hidden image group.
        XCTAssertNil(model.selectedGroupID)
    }

    func testDeletingLastVideoGroupInVideosModeClearsNotLast() async {
        // Three video pairs in .videos mode. Deleting the last pair's file
        // dissolves it; there's no same-kind group after it, so selection
        // should move to the PRECEDING video group (keep cursor near old spot),
        // not jump to "the last visible group" which would be the same wrong
        // behavior the user saw (selecting the now-last group arbitrarily).
        let v1 = SimilarityScoringTests.video(name: "v1.mov")
        let v2 = SimilarityScoringTests.video(name: "v2.mov")
        let v3 = SimilarityScoringTests.video(name: "v3.mov")
        let v4 = SimilarityScoringTests.video(name: "v4.mov")
        let v5 = SimilarityScoringTests.video(name: "v5.mov")
        let v6 = SimilarityScoringTests.video(name: "v6.mov")
        let relations = [
            SimilarityRelation(firstID: v1.id, secondID: v2.id, score: 0.95, evidence: [.similarFrames]),
            SimilarityRelation(firstID: v3.id, secondID: v4.id, score: 0.94, evidence: [.similarFrames]),
            SimilarityRelation(firstID: v5.id, secondID: v6.id, score: 0.93, evidence: [.similarFrames])
        ]
        let model = ScanViewModel(deletionService: FakeDeletionService())
        model.replaceResultsForTesting(items: [v1, v2, v3, v4, v5, v6], relations: relations)
        model.setScanMode(.videos)
        let videoGroups = model.groups.filter { $0.items.first?.kind == .video }
        let lastVideoGroupID = videoGroups.last!.id
        let precedingVideoGroupID = videoGroups[videoGroups.count - 2].id
        model.selectGroup(lastVideoGroupID)

        await model.confirmDeletion(of: v5, mode: .permanent)

        // Falls back to the preceding video group, not the (now) last one arbitrarily.
        XCTAssertEqual(model.selectedGroupID, precedingVideoGroupID)
        XCTAssertEqual(model.selectedGroup?.kind, .video)
    }



    func testChangingScanModePreservesResultsButClearsSelection() {
        let first = SimilarityScoringTests.video(name: "a.mov")
        let second = SimilarityScoringTests.video(name: "b.mov")
        let relation = SimilarityRelation(firstID: first.id, secondID: second.id, score: 0.95, evidence: [.similarFrames])
        let model = ScanViewModel()
        model.replaceResultsForTesting(items: [first, second], relations: [relation])
        model.toggleChecked(first.id)

        model.setScanMode(.images)

        XCTAssertEqual(model.scanMode, .images)
        // Groups persist — switching mode isn't a re-scan.
        XCTAssertFalse(model.groups.isEmpty)
        // The checked video item isn't visible under Images mode, so it's pruned.
        XCTAssertTrue(model.checkedMediaIDs.isEmpty)
    }

    func testChangingScanModeClearsSelectionWhenGroupNotVisibleUnderNewMode() {
        // Selected video group must drop when switching to Images (it's hidden),
        // and re-selecting it is still possible back under Videos.
        let v1 = SimilarityScoringTests.video(name: "v1.mov")
        let v2 = SimilarityScoringTests.video(name: "v2.mov")
        let img1 = MediaItem(kind: .image, url: URL(fileURLWithPath: "/tmp/i1.png"), fileSize: 1_000, duration: nil, width: 100, height: 100, modifiedAt: nil, thumbnailData: nil)
        let img2 = MediaItem(kind: .image, url: URL(fileURLWithPath: "/tmp/i2.png"), fileSize: 1_000, duration: nil, width: 100, height: 100, modifiedAt: nil, thumbnailData: nil)
        let relations = [
            SimilarityRelation(firstID: v1.id, secondID: v2.id, score: 0.95, evidence: [.similarFrames]),
            SimilarityRelation(firstID: img1.id, secondID: img2.id, score: 0.94, evidence: [.similarPerceptualHash])
        ]
        let model = ScanViewModel()
        model.replaceResultsForTesting(items: [v1, v2, img1, img2], relations: relations)
        let videoGroupID = model.groups.first { $0.items.first?.kind == .video }!.id
        model.selectGroup(videoGroupID)
        XCTAssertEqual(model.selectedGroupID, videoGroupID)

        model.setScanMode(.images)
        XCTAssertEqual(model.scanMode, .images)
        XCTAssertNil(model.selectedGroupID, "video group selection hidden under Images must clear")

        model.setScanMode(.videos)
        XCTAssertEqual(model.scanMode, .videos)
        // Selecting the video group again works — data was never dropped.
        model.selectGroup(videoGroupID)
        XCTAssertEqual(model.selectedGroupID, videoGroupID)
    }

    // MARK: - Compare Media group sort

    /// Builds a connected group of three files with controllable metadata so
    /// sort order is unambiguous, and selects it so `sortedGroupItems` is
    /// populated (the cached sort only exists for the selected group).
    private func sortableGroup() -> ScanViewModel {
        // sizes: a=3MB, b=1MB, c=2MB ; durations: a=30, b=10, c=20 ; res: a=1280x720, b=1920x1080, c=1600x900
        let a = MediaItem(kind: .video, url: URL(fileURLWithPath: "/tmp/a.mov"), fileSize: 3_000_000, duration: 30, width: 1280, height: 720, modifiedAt: nil, thumbnailData: nil)
        let b = MediaItem(kind: .video, url: URL(fileURLWithPath: "/tmp/b.mov"), fileSize: 1_000_000, duration: 10, width: 1920, height: 1080, modifiedAt: nil, thumbnailData: nil)
        let c = MediaItem(kind: .video, url: URL(fileURLWithPath: "/tmp/c.mov"), fileSize: 2_000_000, duration: 20, width: 1600, height: 900, modifiedAt: nil, thumbnailData: nil)
        // Distinct scores so group items have differing per-item similarity:
        // a-b 0.95, b-c 0.93, a-c 0.91 → scores: a=0.95, b=0.95, c=0.93.
        let relations = [
            SimilarityRelation(firstID: a.id, secondID: b.id, score: 0.95, evidence: [.similarFrames]),
            SimilarityRelation(firstID: b.id, secondID: c.id, score: 0.93, evidence: [.similarFrames]),
            SimilarityRelation(firstID: a.id, secondID: c.id, score: 0.91, evidence: [.similarFrames])
        ]
        let model = ScanViewModel()
        model.replaceResultsForTesting(items: [a, b, c], relations: relations)
        model.selectGroup(model.groups.first?.id)
        return model
    }

    func testGroupSortDefaultIsSimilarityDescending() {
        let model = sortableGroup()
        XCTAssertEqual(model.groupSortField, .similarity)
        XCTAssertFalse(model.groupSortAscending)

        let names = model.sortedGroupItems.map(\.filename)
        // a and b tie at 0.95 (sorted above c at 0.93); tie broken by filename asc → a, b, then c.
        XCTAssertEqual(names, ["a.mov", "b.mov", "c.mov"])
    }

    func testGroupSortByFileSizeAscending() {
        let model = sortableGroup()
        model.groupSortField = .fileSize
        model.groupSortAscending = true
        XCTAssertEqual(model.sortedGroupItems.map(\.filename), ["b.mov", "c.mov", "a.mov"]) // 1MB, 2MB, 3MB
    }

    func testGroupSortByFileSizeDescending() {
        let model = sortableGroup()
        model.groupSortField = .fileSize
        model.groupSortAscending = false
        XCTAssertEqual(model.sortedGroupItems.map(\.filename), ["a.mov", "c.mov", "b.mov"]) // 3MB, 2MB, 1MB
    }

    func testGroupSortByDurationDescending() {
        let model = sortableGroup()
        model.groupSortField = .duration
        model.groupSortAscending = false
        XCTAssertEqual(model.sortedGroupItems.map(\.filename), ["a.mov", "c.mov", "b.mov"]) // 30, 20, 10
    }

    func testGroupSortByResolutionWidthDescending() {
        let model = sortableGroup()
        model.groupSortField = .resolutionWidth
        model.groupSortAscending = false
        XCTAssertEqual(model.sortedGroupItems.map(\.filename), ["b.mov", "c.mov", "a.mov"]) // 1920, 1600, 1280
    }

    func testGroupSortByResolutionHeightDescending() {
        let model = sortableGroup()
        model.groupSortField = .resolutionHeight
        model.groupSortAscending = false
        XCTAssertEqual(model.sortedGroupItems.map(\.filename), ["b.mov", "c.mov", "a.mov"]) // 1080, 900, 720
    }

    func testGroupSortByNameAscending() {
        let model = sortableGroup()
        model.groupSortField = .name
        model.groupSortAscending = true
        XCTAssertEqual(model.sortedGroupItems.map(\.filename), ["a.mov", "b.mov", "c.mov"])
    }

    func testGroupSortToggleFlipsDirection() {
        let model = sortableGroup()
        model.groupSortField = .fileSize
        model.groupSortAscending = false
        model.toggleGroupSort(field: .fileSize) // same field → flip to ascending
        XCTAssertEqual(model.groupSortField, .fileSize)
        XCTAssertTrue(model.groupSortAscending)
        model.toggleGroupSort(field: .name) // new field → starts descending (first click)
        XCTAssertEqual(model.groupSortField, .name)
        XCTAssertFalse(model.groupSortAscending)
        model.toggleGroupSort(field: .name) // same field again → flip to ascending
        XCTAssertTrue(model.groupSortAscending)
    }

    func testCommandSelectingGroupItemTogglesCheckedItemWithoutClearingOthers() {
        let model = sortableGroup()
        let items = model.sortedGroupItems

        model.toggleGroupItemSelection(items[0].id)
        model.toggleGroupItemSelection(items[2].id)

        XCTAssertEqual(model.checkedMediaIDs, [items[0].id, items[2].id])
        XCTAssertEqual(model.selectedMediaID, items[2].id)

        model.toggleGroupItemSelection(items[0].id)

        XCTAssertEqual(model.checkedMediaIDs, [items[2].id])
    }

    func testShiftSelectingGroupItemChecksRangeFromAnchorInCurrentSortOrder() {
        let model = sortableGroup()
        model.groupSortField = .fileSize
        model.groupSortAscending = false
        let items = model.sortedGroupItems
        XCTAssertEqual(items.map(\.filename), ["a.mov", "c.mov", "b.mov"])

        model.selectGroupItem(items[1].id)
        model.extendGroupItemSelection(to: items[2].id)

        XCTAssertEqual(model.checkedMediaIDs, [items[1].id, items[2].id])
        XCTAssertEqual(model.selectedMediaID, items[2].id)
    }

    func testPlainSelectingGroupItemClearsCheckedSelection() {
        let model = sortableGroup()
        let items = model.sortedGroupItems
        model.toggleGroupItemSelection(items[0].id)
        model.toggleGroupItemSelection(items[1].id)

        model.selectGroupItem(items[2].id)

        XCTAssertTrue(model.checkedMediaIDs.isEmpty)
        XCTAssertEqual(model.selectedMediaID, items[2].id)
    }

    func testClearingGroupItemSelectionKeepsPreviewedItemButClearsCheckedSelection() {
        let model = sortableGroup()
        let items = model.sortedGroupItems
        model.toggleGroupItemSelection(items[0].id)
        model.toggleGroupItemSelection(items[1].id)

        model.clearGroupItemSelection()

        XCTAssertTrue(model.checkedMediaIDs.isEmpty)
        XCTAssertEqual(model.selectedMediaID, items[1].id)
    }

    func testRequestCheckedDeletionDoesNotClearCheckedSelection() {
        let model = sortableGroup()
        let items = model.sortedGroupItems
        model.toggleGroupItemSelection(items[0].id)
        model.toggleGroupItemSelection(items[1].id)

        model.requestCheckedDeletion()

        XCTAssertEqual(model.checkedMediaIDs, [items[0].id, items[1].id])
        XCTAssertEqual(Set(model.deletePrompt?.media.map(\.id) ?? []), [items[0].id, items[1].id])
    }

    func testSelectingAnotherGroupClearsCheckedSelection() {
        let a = SimilarityScoringTests.video(name: "a.mov")
        let b = SimilarityScoringTests.video(name: "b.mov")
        let c = SimilarityScoringTests.video(name: "c.mov")
        let d = SimilarityScoringTests.video(name: "d.mov")
        let relations = [
            SimilarityRelation(firstID: a.id, secondID: b.id, score: 0.95, evidence: [.similarFrames]),
            SimilarityRelation(firstID: c.id, secondID: d.id, score: 0.92, evidence: [.similarFrames])
        ]
        let model = ScanViewModel()
        model.replaceResultsForTesting(items: [a, b, c, d], relations: relations)
        model.selectGroup(model.groups[0].id)
        model.toggleGroupItemSelection(a.id)
        model.toggleGroupItemSelection(b.id)

        model.selectGroup(model.groups[1].id)

        XCTAssertTrue(model.checkedMediaIDs.isEmpty)
        XCTAssertEqual(model.selectedGroupID, model.groups[1].id)
    }

    func testGroupSortRefreshesAfterSelectionOrRebuild() {
        // Cached sort must repopulate when the selected group changes and when
        // its contents change (e.g. a deletion), not just on sort-field edits.
        let a = SimilarityScoringTests.video(name: "a.mov")
        let b = SimilarityScoringTests.video(name: "b.mov")
        let c = SimilarityScoringTests.video(name: "c.mov")
        let d = SimilarityScoringTests.video(name: "d.mov")
        let relations = [
            SimilarityRelation(firstID: a.id, secondID: b.id, score: 0.95, evidence: [.similarFrames]),
            SimilarityRelation(firstID: c.id, secondID: d.id, score: 0.92, evidence: [.similarFrames])
        ]
        let model = ScanViewModel(deletionService: FakeDeletionService())
        model.replaceResultsForTesting(items: [a, b, c, d], relations: relations)
        model.selectGroup(model.groups[0].id)
        XCTAssertEqual(Set(model.sortedGroupItems.map(\.id)), Set(model.groups[0].items.map(\.id)))

        // Selecting the other group swaps the cached items.
        let otherGroupID = model.groups[1].id
        model.selectGroup(otherGroupID)
        XCTAssertEqual(Set(model.sortedGroupItems.map(\.id)), Set(model.groups[1].items.map(\.id)))
    }

    func testGroupSortPersistsAfterDeletionDissolvesGroup() async {
        // Group 0: two files, score 0.95. Group 1: two files, score 0.92.
        // Set sort to fileSize descending. Delete one file from group 0 so it
        // dissolves. The auto-selected group 1 must stay sorted by fileSize
        // (not revert to the grouper's filename order).
        let a = SimilarityScoringTests.video(name: "a.mov", size: 3_000_000)
        let b = SimilarityScoringTests.video(name: "b.mov", size: 1_000_000)
        let c = SimilarityScoringTests.video(name: "c.mov", size: 5_000_000)
        let d = SimilarityScoringTests.video(name: "d.mov", size: 2_000_000)
        let relations = [
            SimilarityRelation(firstID: a.id, secondID: b.id, score: 0.95, evidence: [.similarFrames]),
            SimilarityRelation(firstID: c.id, secondID: d.id, score: 0.92, evidence: [.similarFrames])
        ]
        let model = ScanViewModel(deletionService: FakeDeletionService())
        model.replaceResultsForTesting(items: [a, b, c, d], relations: relations)
        XCTAssertEqual(model.groups.count, 2)

        model.groupSortField = .fileSize
        model.groupSortAscending = false
        model.selectGroup(model.groups[0].id)
        // fileSize descending: a(3MB) then b(1MB).
        XCTAssertEqual(model.sortedGroupItems.map(\.filename), ["a.mov", "b.mov"])

        // Deleting b dissolves group 0 (a becomes a singleton).
        await model.confirmDeletion(of: b, mode: .trash)

        // Group 1 should now be selected with items still sorted by fileSize desc.
        XCTAssertEqual(model.groups.count, 1)
        XCTAssertEqual(model.groupSortField, .fileSize)
        XCTAssertFalse(model.groupSortAscending)
        XCTAssertEqual(model.sortedGroupItems.map(\.filename), ["c.mov", "d.mov"], "must stay sorted by fileSize descending, not filename order")
    }


    func testBatchDeletionKeepsFailuresAndRemovesSuccessfulItems() async {
        let first = SimilarityScoringTests.video(name: "a.mov")
        let second = SimilarityScoringTests.video(name: "b.mov")
        let relation = SimilarityRelation(firstID: first.id, secondID: second.id, score: 0.95, evidence: [.similarFrames])
        let deletion = FakeDeletionService(failingURLs: [second.url])
        let model = ScanViewModel(deletionService: deletion)
        model.replaceResultsForTesting(items: [first, second], relations: [relation])
        model.toggleChecked(first.id)
        model.toggleChecked(second.id)
        model.requestCheckedDeletion()

        await model.confirmPromptDeletion(mode: .trash)

        XCTAssertEqual(deletion.deletedURLs, [first.url, second.url])
        XCTAssertEqual(model.checkedMediaIDs, [second.id])
        XCTAssertNotNil(model.presentedError)
    }

    func testPreviewDeletionUsesCheckedItemsWhenAnyAreSelected() {
        let first = SimilarityScoringTests.video(name: "a.mov")
        let second = SimilarityScoringTests.video(name: "b.mov")
        let relation = SimilarityRelation(firstID: first.id, secondID: second.id, score: 0.95, evidence: [.similarFrames])
        let model = ScanViewModel()
        model.replaceResultsForTesting(items: [first, second], relations: [relation])
        model.toggleChecked(first.id)
        model.toggleChecked(second.id)

        model.requestPreviewDeletion(defaultingTo: first)

        XCTAssertEqual(Set(model.deletePrompt?.media.map(\.id) ?? []), [first.id, second.id])
    }

    func testPreviewDeletionUsesCurrentItemWhenNothingIsChecked() {
        let first = SimilarityScoringTests.video(name: "a.mov")
        let second = SimilarityScoringTests.video(name: "b.mov")
        let relation = SimilarityRelation(firstID: first.id, secondID: second.id, score: 0.95, evidence: [.similarFrames])
        let model = ScanViewModel()
        model.replaceResultsForTesting(items: [first, second], relations: [relation])

        model.requestPreviewDeletion(defaultingTo: first)

        XCTAssertEqual(model.deletePrompt?.media.map(\.id), [first.id])
    }

    func testCancellingImageStageShowsNoGroups() async throws {
        // Groups are published only after both kinds finish; cancelling during
        // the image stage means nothing was published yet, so the sidebar shows
        // no groups.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanCancellation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["first.mp4", "second.mp4", "image.jpg"] {
            try Data().write(to: root.appendingPathComponent(name))
        }

        let videoScanner = VideoScanner(maxConcurrentLoads: 2) { url in
            MediaItem(
                kind: .video,
                url: url,
                fileSize: 1,
                duration: 1,
                width: 16,
                height: 9,
                modifiedAt: nil,
                thumbnailData: nil
            )
        }
        let imageScanner = ImageScanner(maxConcurrentLoads: 1) { url in
            try await Task.sleep(for: .seconds(10))
            return MediaItem(
                kind: .image,
                url: url,
                fileSize: 1,
                duration: nil,
                width: 1,
                height: 1,
                modifiedAt: nil,
                thumbnailData: nil
            )
        }
        let model = ScanViewModel(
            scanner: videoScanner,
            imageScanner: imageScanner,
            pipeline: ExactDuplicatePipeline(),
            hashCache: nil
        )
        model.selectedFolders = [root]

        model.startScan()
        // Wait until the image stage is underway (videos already processed but
        // no groups published yet).
        try await waitUntil { model.progress.stage == .readingMetadata }
        model.cancelScan()
        try await waitUntil { model.progress.stage == .cancelled }

        XCTAssertTrue(model.groups.isEmpty)
    }

    func testDiscoverFilesPrunesHashCacheToDiscoveredPaths() async throws {
        let root = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appendingPathComponent("DiscoverPrune-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let keepURL = root.appendingPathComponent("keep.mp4")
        try Data([1]).write(to: keepURL)
        let discoveredPath = try XCTUnwrap(VideoScanner.discoverVideoURLs(in: root).first).path
        let cache = PruneRecordingCache()
        let scanner = VideoScanner(maxConcurrentLoads: 1) { url in
            MediaItem(
                kind: .video,
                url: url,
                fileSize: 1,
                duration: 1,
                width: 16,
                height: 9,
                modifiedAt: nil,
                thumbnailData: nil
            )
        }
        let model = ScanViewModel(scanner: scanner, hashCache: cache)
        model.selectedFolders = [root]

        model.discoverFiles()
        try await waitUntil { model.progress.stage == .completed }
        try await waitUntilAsync { await cache.lastPrunedPaths() != nil }

        let prunedPaths = await cache.lastPrunedPaths()
        XCTAssertEqual(prunedPaths, [discoveredPath])
    }

    private func waitUntil(
        timeoutIterations: Int = 200,
        condition: () -> Bool
    ) async throws {
        for _ in 0..<timeoutIterations {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for scan state")
    }

    private func waitUntilAsync(
        timeoutIterations: Int = 200,
        condition: () async -> Bool
    ) async throws {
        for _ in 0..<timeoutIterations {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for async scan state")
    }
}

private struct ExactDuplicatePipeline: SimilarityProcessing {
    func process(
        videos: [MediaItem],
        threshold: Double,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> PipelineResult {
        guard videos.count == 2 else {
            return PipelineResult(videos: videos, relations: [], groups: [])
        }
        let relation = SimilarityRelation(
            firstID: videos[0].id,
            secondID: videos[1].id,
            score: 1,
            evidence: [.identicalContentHash]
        )
        return PipelineResult(
            videos: videos,
            relations: [relation],
            groups: SimilarityGrouper.groups(items: videos, relations: [relation], threshold: threshold)
        )
    }
}

private struct ProgressReportingPipeline: SimilarityProcessing {
    let tracker: CrossKindProgressTracker

    func process(
        videos: [MediaItem],
        threshold: Double,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> PipelineResult {
        await progress(ScanProgress(stage: .comparing, fraction: 0.8, discoveredCount: videos.count))
        await tracker.videoComparingProgressReported()
        return PipelineResult(videos: videos, relations: [], groups: [])
    }
}

private actor CrossKindScanTracker {
    private var didStartVideo = false
    private var didStartImage = false

    func videoStarted() {
        didStartVideo = true
    }

    func imageStarted() {
        didStartImage = true
    }

    func bothStarted() -> Bool {
        didStartVideo && didStartImage
    }

    func waitForImageStarted() async {
        for _ in 0..<300 {
            if didStartImage { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor CrossKindProgressTracker {
    private var didReportVideoComparingProgress = false

    func videoComparingProgressReported() {
        didReportVideoComparingProgress = true
    }

    func waitForVideoComparingProgress() async {
        for _ in 0..<300 {
            if didReportVideoComparingProgress { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class FakeDeletionService: DeletionServicing {
    var deletedURLs: [URL] = []
    var revealedURLs: [URL] = []
    let failingURLs: Set<URL>

    init(failingURLs: Set<URL> = []) {
        self.failingURLs = failingURLs
    }

    func delete(url: URL, mode: DeletionMode) async throws {
        deletedURLs.append(url)
        if failingURLs.contains(url) {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    func reveal(_ url: URL) {
        revealedURLs.append(url)
    }

    func open(_ url: URL) {}
}

private actor PruneRecordingCache: HashCaching {
    private var prunedPaths: Set<String>?

    func lookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, algorithmVersion: String) -> CacheRecord? {
        nil
    }

    func upsert(_ record: CacheRecord) {}

    func pruneStale(validPaths: Set<String>) {
        prunedPaths = validPaths
    }

    func count() -> Int { 0 }

    func clearAll() {}

    func sizeInBytes() -> Int64 { 0 }

    func lastPrunedPaths() -> Set<String>? {
        prunedPaths
    }
}

private actor MetadataHitCache: HashCaching {
    private(set) var metadataLookups = 0

    func lookup(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind, algorithmVersion: String) -> CacheRecord? {
        nil
    }

    func upsert(_ record: CacheRecord) {}

    func pruneStale(validPaths: Set<String>) {}

    func count() -> Int { 0 }

    func clearAll() {}

    func sizeInBytes() -> Int64 { 0 }

    func lookupMetadata(filePath: String, fileSize: Int64, modifiedAt: Date?, mediaKind: MediaKind) -> (duration: Double?, width: Int?, height: Int?)? {
        metadataLookups += 1
        return mediaKind == .video ? (duration: 12, width: 1920, height: 1080) : nil
    }

    func metadataLookupCount() -> Int {
        metadataLookups
    }
}
