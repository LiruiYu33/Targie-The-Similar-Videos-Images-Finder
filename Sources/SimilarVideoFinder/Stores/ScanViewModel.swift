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

import AppKit
import Foundation
import SwiftUI

enum DeletePromptStep: Equatable {
    case choosingMethod
    case confirmingPermanent
}

struct DeletePrompt: Identifiable, Equatable {
    let id = UUID()
    let media: MediaItem
    var step: DeletePromptStep
}

enum PresentedError {
    case deletion(DeletionError)
    case message(String)

    func localizedDescription(_ language: AppLanguage) -> String {
        switch self {
        case .deletion(let error): error.localizedDescription(language)
        case .message(let message): message
        }
    }
}

@MainActor
final class ScanViewModel: ObservableObject {
    @Published var selectedFolder: URL?
    @Published var threshold = 0.88 {
        didSet { rebuildGroups() }
    }
    @Published private(set) var groups: [SimilarityGroup] = []
    @Published var selectedGroupID: UUID?
    @Published var selectedMediaID: UUID?
    @Published private(set) var progress = ScanProgress()
    @Published private(set) var issues: [ScanIssue] = []
    @Published var presentedError: PresentedError?
    @Published var deletePrompt: DeletePrompt?

    private var allItems: [MediaItem] = []
    private var allRelations: [SimilarityRelation] = []
    private var scanTask: Task<Void, Never>?
    private let scanner: VideoScanner
    private let pipeline: any SimilarityProcessing
    private let deletionService: any DeletionServicing
    private let hashCache: (any HashCaching)?

    init(
        scanner: VideoScanner = VideoScanner(),
        pipeline: (any SimilarityProcessing)? = nil,
        deletionService: any DeletionServicing = DeletionService(),
        hashCache: (any HashCaching)? = ScanViewModel.makeDefaultHashCache()
    ) {
        self.scanner = scanner
        self.deletionService = deletionService
        self.hashCache = hashCache
        self.pipeline = pipeline ?? SimilarityPipeline(cache: hashCache)
    }

    private static func makeDefaultHashCache() -> (any HashCaching)? {
        try? HashCache()
    }

    var isScanning: Bool {
        [.discovering, .readingMetadata, .prehashing, .hashing, .comparing].contains(progress.stage)
    }

    var selectedGroup: SimilarityGroup? {
        groups.first { $0.id == selectedGroupID }
    }

    var selectedMedia: MediaItem? {
        selectedGroup?.items.first { $0.id == selectedMediaID }
    }

    func chooseFolder(language: AppLanguage) {
        let panel = NSOpenPanel()
        panel.title = L10n.chooseVideoFolder(language)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            selectedFolder = url
            groups = []
            selectedGroupID = nil
            selectedMediaID = nil
            progress = ScanProgress()
            issues = []
        }
    }

    func startScan() {
        guard let folder = selectedFolder, !isScanning else { return }
        scanTask?.cancel()
        progress = ScanProgress(stage: .discovering)
        groups = []
        issues = []
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let scanned = try await scanner.scan(folder: folder) { [weak self] update in
                    await MainActor.run { self?.progress = update }
                }
                issues = scanned.issues
                let result = try await pipeline.process(videos: scanned.videos, threshold: threshold) { [weak self] update in
                    await MainActor.run { self?.progress = update }
                }
                try Task.checkCancellation()
                allItems = result.videos
                allRelations = result.relations
                groups = result.groups
                selectFirstAvailable()
                progress = ScanProgress(stage: .completed, fraction: 1, discoveredCount: result.videos.count)

                // 清理缓存中已不存在的视频条目
                if let hashCache {
                    let validPaths = Set(result.videos.map { $0.url.path })
                    Task { await hashCache.pruneStale(validPaths: validPaths) }
                }
            } catch is CancellationError {
                allItems = []
                allRelations = []
                groups = []
                progress = ScanProgress(stage: .cancelled)
            } catch {
                groups = []
                presentedError = .message(error.localizedDescription)
                progress = ScanProgress(stage: .idle)
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func selectGroup(_ id: UUID?) {
        selectedGroupID = id
        selectedMediaID = selectedGroup?.items.first?.id
    }

    func requestDeletion(of media: MediaItem) {
        deletePrompt = DeletePrompt(media: media, step: .choosingMethod)
    }

    func askForPermanentConfirmation() {
        deletePrompt?.step = .confirmingPermanent
    }

    func confirmDeletion(of media: MediaItem, mode: DeletionMode) async {
        do {
            try await deletionService.delete(url: media.url, mode: mode)
            allItems.removeAll { $0.id == media.id }
            allRelations.removeAll { $0.contains(media.id) }
            rebuildGroups()
            deletePrompt = nil
        } catch let error as DeletionError {
            presentedError = .deletion(error)
        } catch {
            presentedError = .message(error.localizedDescription)
        }
    }

    func revealSelectedMedia() {
        if let media = selectedMedia { deletionService.reveal(media.url) }
    }

    func openSelectedMedia() {
        if let media = selectedMedia { deletionService.open(media.url) }
    }

    func replaceResultsForTesting(items: [MediaItem], relations: [SimilarityRelation]) {
        allItems = items
        allRelations = relations
        rebuildGroups()
    }

    func localizedError(_ language: AppLanguage) -> String? {
        presentedError?.localizedDescription(language)
    }

    private func rebuildGroups() {
        groups = SimilarityGrouper.groups(items: allItems, relations: allRelations, threshold: threshold)
        if !groups.contains(where: { $0.id == selectedGroupID }) { selectFirstAvailable() }
    }

    private func selectFirstAvailable() {
        selectedGroupID = groups.first?.id
        selectedMediaID = groups.first?.items.first?.id
    }
}
