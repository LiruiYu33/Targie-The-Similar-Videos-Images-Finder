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

    func testDisplayThresholdSupportsExactMatchFiltering() {
        XCTAssertEqual(ScanViewModel.displayThresholdRange.lowerBound, 0.50)
        XCTAssertEqual(ScanViewModel.displayThresholdRange.upperBound, 1.0)
    }

    func testChangingScanModeClearsExistingResultsAndSelection() {
        let first = SimilarityScoringTests.video(name: "a.mov")
        let second = SimilarityScoringTests.video(name: "b.mov")
        let relation = SimilarityRelation(firstID: first.id, secondID: second.id, score: 0.95, evidence: [.similarFrames])
        let model = ScanViewModel()
        model.replaceResultsForTesting(items: [first, second], relations: [relation])
        model.toggleChecked(first.id)

        model.setScanMode(.images)

        XCTAssertEqual(model.scanMode, .images)
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertNil(model.selectedGroupID)
        XCTAssertNil(model.selectedMediaID)
        XCTAssertTrue(model.checkedMediaIDs.isEmpty)
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
