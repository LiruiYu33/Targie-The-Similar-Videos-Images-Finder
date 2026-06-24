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

    func testDeletePromptStartsByChoosingMethod() {
        let model = ScanViewModel()
        model.requestDeletion(of: SimilarityScoringTests.video(name: "a.mov"))
        XCTAssertEqual(model.deletePrompt?.step, .choosingMethod)
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
        // Selection and checked state are reset so stale video selections don't
        // show under Images mode.
        XCTAssertNil(model.selectedGroupID)
        XCTAssertNil(model.selectedMediaID)
        XCTAssertTrue(model.checkedMediaIDs.isEmpty)
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

    func testCancellingImageStageKeepsCompletedVideoGroups() async throws {
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
        try await waitUntil { model.groups.count == 1 && model.progress.stage == .readingMetadata }
        model.cancelScan()
        try await waitUntil { model.progress.stage == .cancelled }

        XCTAssertEqual(model.groups.count, 1)
        XCTAssertEqual(model.groups[0].kind, .video)
        XCTAssertEqual(model.groups[0].items.count, 2)
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

@MainActor
private final class FakeDeletionService: DeletionServicing {
    var deletedURLs: [URL] = []
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

    func reveal(_ url: URL) {}
    func open(_ url: URL) {}
}
