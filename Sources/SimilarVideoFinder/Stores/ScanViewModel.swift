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
    let media: [MediaItem]
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
    static let displayThresholdRange = 0.50...1.0

    @Published var selectedFolders: [URL] = []
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
    @Published var scanMode: ScanMode = .all
    @Published var checkedMediaIDs = Set<UUID>()

    private var allItems: [MediaItem] = []
    private var allRelations: [SimilarityRelation] = []
    private var scanTask: Task<Void, Never>?
    private let scanner: VideoScanner
    private let imageScanner: ImageScanner
    private let imagePipeline: ImageSimilarityPipeline
    private let pipeline: any SimilarityProcessing
    private let deletionService: any DeletionServicing
    private let hashCache: (any HashCaching)?

    init(
        scanner: VideoScanner = VideoScanner(),
        imageScanner: ImageScanner = ImageScanner(),
        pipeline: (any SimilarityProcessing)? = nil,
        deletionService: any DeletionServicing = DeletionService(),
        hashCache: (any HashCaching)? = ScanViewModel.makeDefaultHashCache()
    ) {
        self.scanner = scanner
        self.imageScanner = imageScanner
        self.deletionService = deletionService
        self.hashCache = hashCache
        self.pipeline = pipeline ?? SimilarityPipeline(cache: hashCache)
        self.imagePipeline = ImageSimilarityPipeline(cache: hashCache)
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
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            addFolders(panel.urls)
        }
    }

    @discardableResult
    func addFolders(_ urls: [URL]) -> Bool {
        guard !isScanning else { return false }
        let directories = urls.compactMap { url -> URL? in
            let normalized = url.standardizedFileURL
            guard (try? normalized.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return normalized
        }
        guard !directories.isEmpty else { return false }

        var seen = Set(selectedFolders.map { $0.standardizedFileURL.path })
        let additions = directories.filter { seen.insert($0.path).inserted }
        guard !additions.isEmpty else { return true }

        selectedFolders.append(contentsOf: additions)
        resetResults()
        return true
    }

    func removeFolder(_ folder: URL) {
        guard !isScanning else { return }
        let path = folder.standardizedFileURL.path
        guard selectedFolders.contains(where: { $0.standardizedFileURL.path == path }) else { return }
        selectedFolders.removeAll { $0.standardizedFileURL.path == path }
        resetResults()
    }

    func startScan() {
        guard !selectedFolders.isEmpty, !isScanning else { return }
        let folders = selectedFolders
        scanTask?.cancel()
        progress = ScanProgress(stage: .discovering)
        allItems = []
        allRelations = []
        groups = []
        checkedMediaIDs = []
        issues = []
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                var items: [MediaItem] = []
                var relations: [SimilarityRelation] = []
                var scanIssues: [ScanIssue] = []
                if scanMode != .images {
                    var videos: [MediaItem] = []
                    for folder in folders {
                        let scanned = try await scanner.scan(folder: folder) { [weak self] update in await MainActor.run { self?.progress = update } }
                        videos.append(contentsOf: scanned.videos)
                        scanIssues.append(contentsOf: scanned.issues)
                    }
                    videos = uniqueItemsByURL(videos)
                    issues = scanIssues
                    let result = try await pipeline.process(videos: videos, threshold: threshold) { [weak self] update in await MainActor.run { self?.progress = update } }
                    items.append(contentsOf: result.videos)
                    relations.append(contentsOf: result.relations)
                    publish(items: items, relations: relations)
                }
                if scanMode != .videos {
                    var images: [MediaItem] = []
                    for folder in folders {
                        let scanned = try await imageScanner.scan(folder: folder) { [weak self] update in await MainActor.run { self?.progress = update } }
                        images.append(contentsOf: scanned.images)
                        scanIssues.append(contentsOf: scanned.issues)
                    }
                    images = uniqueItemsByURL(images)
                    issues = scanIssues
                    let result = try await imagePipeline.process(images: images, threshold: threshold) { [weak self] update in await MainActor.run { self?.progress = update } }
                    items.append(contentsOf: result.images)
                    relations.append(contentsOf: result.relations)
                    publish(items: items, relations: relations)
                }
                try Task.checkCancellation()
                allItems = items
                allRelations = relations
                groups = SimilarityGrouper.groups(items: items, relations: relations, threshold: threshold)
                selectFirstAvailable()
                progress = ScanProgress(stage: .completed, fraction: 1, discoveredCount: items.count)

                // 清理缓存中已不存在的视频条目
                if let hashCache {
                    let validPaths = Set(items.map { $0.url.path })
                    Task { await hashCache.pruneStale(validPaths: validPaths) }
                }
            } catch is CancellationError {
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

    func setScanMode(_ mode: ScanMode) {
        guard scanMode != mode else { return }
        scanTask?.cancel()
        scanMode = mode
        allItems = []
        allRelations = []
        groups = []
        selectedGroupID = nil
        selectedMediaID = nil
        checkedMediaIDs = []
        issues = []
        progress = ScanProgress()
    }

    func selectGroup(_ id: UUID?) {
        selectedGroupID = id
        selectedMediaID = selectedGroup?.items.first?.id
    }

    func requestDeletion(of media: MediaItem) {
        deletePrompt = DeletePrompt(media: [media], step: .choosingMethod)
    }

    func requestCheckedDeletion() {
        let selected = allItems.filter { checkedMediaIDs.contains($0.id) }
        if !selected.isEmpty { deletePrompt = DeletePrompt(media: selected, step: .choosingMethod) }
    }

    func toggleChecked(_ id: UUID) {
        if checkedMediaIDs.contains(id) { checkedMediaIDs.remove(id) } else { checkedMediaIDs.insert(id) }
    }

    func askForPermanentConfirmation() {
        deletePrompt?.step = .confirmingPermanent
    }

    func confirmDeletion(of media: MediaItem, mode: DeletionMode) async {
        deletePrompt = DeletePrompt(media: [media], step: deletePrompt?.step ?? .choosingMethod)
        await confirmPromptDeletion(mode: mode)
    }

    func confirmPromptDeletion(mode: DeletionMode) async {
        guard let targets = deletePrompt?.media else { return }
        let groupsBeforeDeletion = groups
        var deletedIDs = Set<UUID>()
        var failures: [String] = []
        for media in targets {
            do {
                try await deletionService.delete(url: media.url, mode: mode)
                deletedIDs.insert(media.id)
                allItems.removeAll { $0.id == media.id }
                allRelations.removeAll { $0.contains(media.id) }
                checkedMediaIDs.remove(media.id)
            } catch { failures.append("\(media.filename): \(error.localizedDescription)") }
        }
        preserveGroupContinuity(groupsBeforeDeletion, deletedIDs: deletedIDs)
        rebuildGroups()
        deletePrompt = nil
        if !failures.isEmpty { presentedError = .message(failures.joined(separator: "\n")) }
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
        checkedMediaIDs.formIntersection(Set(allItems.map(\.id)))
        if !groups.contains(where: { $0.id == selectedGroupID }) { selectFirstAvailable() }
    }

    private func publish(items: [MediaItem], relations: [SimilarityRelation]) {
        allItems = items
        allRelations = relations
        groups = SimilarityGrouper.groups(items: items, relations: relations, threshold: threshold)
        selectFirstAvailable()
    }

    private func selectFirstAvailable() {
        selectedGroupID = groups.first?.id
        selectedMediaID = groups.first?.items.first?.id
    }

    private func resetResults() {
        allItems = []
        allRelations = []
        groups = []
        selectedGroupID = nil
        selectedMediaID = nil
        checkedMediaIDs = []
        progress = ScanProgress()
        issues = []
    }

    private func uniqueItemsByURL(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.url.standardizedFileURL.path).inserted }
    }

    private func preserveGroupContinuity(_ previousGroups: [SimilarityGroup], deletedIDs: Set<UUID>) {
        guard !deletedIDs.isEmpty else { return }
        let remainingIDs = Set(allItems.map(\.id))

        for group in previousGroups where group.items.contains(where: { deletedIDs.contains($0.id) }) {
            let survivors = group.items.filter { remainingIDs.contains($0.id) }
            guard survivors.count >= 2 else { continue }

            let score = group.relations
                .filter { $0.score >= threshold }
                .map(\.score)
                .min() ?? threshold
            let evidence = group.relations.reduce(into: Set<SimilarityEvidence>()) {
                $0.formUnion($1.evidence)
            }

            for (first, second) in zip(survivors, survivors.dropFirst()) {
                let pairExists = allRelations.contains {
                    ($0.firstID == first.id && $0.secondID == second.id)
                        || ($0.firstID == second.id && $0.secondID == first.id)
                }
                if !pairExists {
                    allRelations.append(SimilarityRelation(
                        firstID: first.id,
                        secondID: second.id,
                        score: score,
                        evidence: evidence
                    ))
                }
            }
        }
    }
}
