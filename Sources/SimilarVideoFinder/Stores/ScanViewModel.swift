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

/// Sort dimension for the cards within a single similar group (Compare Media).
/// Mirrors `BrowseViewModel.SortField` but adds `similarity` and `duration`,
/// which only make sense within a group.
enum GroupSortField: String, CaseIterable, Identifiable, Sendable {
    case similarity, fileSize, name, duration, resolutionWidth, resolutionHeight
    var id: String { rawValue }

    /// Whether this field sorts by a resolution dimension (width or height).
    var isResolution: Bool { self == .resolutionWidth || self == .resolutionHeight }
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

private struct ScanSideResult: Sendable {
    let items: [MediaItem]
    let relations: [SimilarityRelation]
    let issues: [ScanIssue]
}

private enum ScanProgressLane: CaseIterable, Hashable, Sendable {
    case video
    case image
}

private enum ScanProgressWorkflow: Sendable {
    case fullScan
    case discovery
}

private actor ScanProgressAggregator {
    private let workflow: ScanProgressWorkflow
    private var updates: [ScanProgressLane: ScanProgress] = [:]
    private var completedLanes = Set<ScanProgressLane>()
    private var emittedFraction = 0.0
    private var emittedStage: ScanStage = .discovering

    init(workflow: ScanProgressWorkflow) {
        self.workflow = workflow
    }

    func update(_ lane: ScanProgressLane, with progress: ScanProgress) -> ScanProgress {
        updates[lane] = progress
        return aggregate(preferredLane: lane)
    }

    func complete(_ lane: ScanProgressLane, discoveredCount: Int) -> ScanProgress {
        var progress = updates[lane] ?? ScanProgress(stage: .completed, fraction: 1)
        progress.stage = .completed
        progress.fraction = 1
        progress.discoveredCount = max(progress.discoveredCount, discoveredCount)
        updates[lane] = progress
        completedLanes.insert(lane)
        return aggregate(preferredLane: lane)
    }

    private func aggregate(preferredLane: ScanProgressLane) -> ScanProgress {
        let allLanes = ScanProgressLane.allCases
        let allCompleted = completedLanes.count == allLanes.count
        let rawFraction = allLanes.reduce(into: (weighted: 0.0, total: 0.0)) { partial, lane in
            let progress = updates[lane] ?? ScanProgress(stage: .discovering, fraction: 0)
            let weight = Double(max(1, progress.discoveredCount))
            partial.weighted += normalizedFraction(for: progress) * weight
            partial.total += weight
        }
        if allCompleted {
            emittedFraction = 1
            emittedStage = .completed
        } else {
            let nextFraction = rawFraction.total > 0 ? rawFraction.weighted / rawFraction.total : 0
            emittedFraction = max(emittedFraction, min(1, max(0, nextFraction)))
            let nextStage = aggregateStage()
            if stageRank(nextStage) >= stageRank(emittedStage) {
                emittedStage = nextStage
            }
        }

        let cacheKind = cacheKind(for: emittedStage)
        let cacheStats = updates.values.reduce(into: (hits: 0, total: 0)) { partial, progress in
            guard progress.cacheKind == cacheKind else { return }
            partial.hits += progress.cacheHits
            partial.total += progress.cacheTotal
        }

        return ScanProgress(
            stage: emittedStage,
            fraction: emittedFraction,
            currentFile: currentFile(preferredLane: preferredLane, stage: emittedStage),
            discoveredCount: updates.values.reduce(0) { $0 + $1.discoveredCount },
            cacheHits: cacheStats.hits,
            cacheTotal: cacheStats.total,
            cacheKind: cacheStats.total > 0 ? cacheKind : nil
        )
    }

    private func aggregateStage() -> ScanStage {
        updates.values
            .map(\.stage)
            .filter { $0 != .completed && $0 != .cancelled && $0 != .idle }
            .max { stageRank($0) < stageRank($1) } ?? .discovering
    }

    private func normalizedFraction(for progress: ScanProgress) -> Double {
        let fraction = min(1, max(0, progress.fraction))
        switch workflow {
        case .discovery:
            switch progress.stage {
            case .completed:
                return 1
            case .readingMetadata:
                return fraction
            default:
                return 0
            }
        case .fullScan:
            switch progress.stage {
            case .completed:
                return 1
            case .comparing:
                return 0.65 + (0.35 * fraction)
            case .hashing:
                return 0.35 + (0.30 * fraction)
            case .prehashing:
                return 0.25 + (0.10 * fraction)
            case .readingMetadata:
                return 0.25 * fraction
            default:
                return 0
            }
        }
    }

    private func cacheKind(for stage: ScanStage) -> ScanProgressCacheKind? {
        switch stage {
        case .readingMetadata: .metadata
        case .hashing: .fingerprint
        case .comparing: .relation
        default: nil
        }
    }

    private func currentFile(preferredLane: ScanProgressLane, stage: ScanStage) -> String {
        if let preferred = updates[preferredLane],
           preferred.stage == stage,
           !preferred.currentFile.isEmpty {
            return preferred.currentFile
        }
        if let matching = updates.values.first(where: { $0.stage == stage && !$0.currentFile.isEmpty }) {
            return matching.currentFile
        }
        return updates[preferredLane]?.currentFile ?? ""
    }

    private func stageRank(_ stage: ScanStage) -> Int {
        switch stage {
        case .idle: 0
        case .discovering: 0
        case .readingMetadata: 1
        case .prehashing: 2
        case .hashing: 3
        case .comparing: 4
        case .completed: 5
        case .cancelled: 5
        }
    }
}

@MainActor
final class ScanViewModel: ObservableObject {
    static let displayThresholdRange = DisplayThresholdEditing.allowedRange

    @Published var selectedFolders: [URL] = []
    @Published var threshold = 0.88 {
        didSet { scheduleThresholdRebuild() }
    }

    /// Coalesces threshold-driven group rebuilds so dragging the slider does
    /// not recompute groups on every intermediate value (which freezes the UI
    /// on large libraries). The rebuild fires shortly after the last change.
    private var thresholdRebuildTask: Task<Void, Never>?

    private func scheduleThresholdRebuild() {
        thresholdRebuildTask?.cancel()
        thresholdRebuildTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self?.rebuildGroups(preserving: self?.groups ?? [])
        }
    }
    @Published private(set) var groups: [SimilarityGroup] = []
    @Published var selectedGroupID: UUID?
    @Published var selectedMediaID: UUID?

    /// Sort order for the cards within the selected group (Compare Media).
    /// Default is similarity descending: the most-similar item surfaces first,
    /// which fits the "pick a keeper, delete the rest" workflow.
    @Published var groupSortField: GroupSortField = .similarity {
        didSet { recomputeSortedGroupItems() }
    }
    @Published var groupSortAscending = false {
        didSet { recomputeSortedGroupItems() }
    }

    /// Cached sort of the selected group's items. Stored (not computed) so the
    /// Compare Media grid reads a stable array identity across unrelated model
    /// changes — e.g. dragging the display threshold fires `objectWillChange`
    /// every frame, and a computed `sortedItems` would hand `ForEach` a fresh
    /// array each frame, rebuilding every card (each decoding its thumbnail
    /// from disk) and freezing the UI. Refreshed only when the selected group,
    /// its contents, or the sort field/direction actually change.
    @Published private(set) var sortedGroupItems: [MediaItem] = []
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
    private let thumbnailStore: ThumbnailStore
    private var groupSelectionAnchorID: UUID?

    init(
        scanner: VideoScanner = VideoScanner(),
        imageScanner: ImageScanner = ImageScanner(),
        pipeline: (any SimilarityProcessing)? = nil,
        deletionService: any DeletionServicing = DeletionService(),
        hashCache: (any HashCaching)? = ScanViewModel.makeDefaultHashCache(),
        thumbnailStore: ThumbnailStore = .shared
    ) {
        self.deletionService = deletionService
        self.hashCache = hashCache
        self.thumbnailStore = thumbnailStore
        self.pipeline = pipeline ?? SimilarityPipeline(cache: hashCache)
        self.imagePipeline = ImageSimilarityPipeline(cache: hashCache)
        // Use caller-provided scanners, but if they used the default loader,
        // replace it with a cache-equipped default so re-scan skips media I/O.
        self.scanner = scanner.metadataCache == nil && scanner.usesDefaultLoader
            ? VideoScanner(maxConcurrentLoads: scanner.maxConcurrentLoads, thumbnailStore: thumbnailStore, metadataCache: hashCache)
            : scanner
        self.imageScanner = imageScanner.metadataCache == nil && imageScanner.usesDefaultLoader
            ? ImageScanner(maxConcurrentLoads: imageScanner.maxConcurrentLoads, thumbnailStore: thumbnailStore, metadataCache: hashCache)
            : imageScanner
    }

    private static func makeDefaultHashCache() -> (any HashCaching)? {
        try? HashCache()
    }

    /// All media items discovered during scanning or file discovery.
    var items: [MediaItem] { allItems }

    var isScanning: Bool {
        [.discovering, .readingMetadata, .prehashing, .hashing, .comparing].contains(progress.stage)
    }

    /// Whether browse mode has data to show.
    var hasDiscoveredItems: Bool { !allItems.isEmpty }

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

    @discardableResult
    func clearFolders() -> Bool {
        guard !isScanning, !selectedFolders.isEmpty else { return false }
        selectedFolders.removeAll()
        resetResults()
        return true
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
        groupSelectionAnchorID = nil
        issues = []
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Always scan both kinds so the user can switch All / Images /
                // Videos after scanning without re-scanning; `scanMode` only
                // filters the sidebar display.
                let scanner = self.scanner
                let imageScanner = self.imageScanner
                let pipeline = self.pipeline
                let imagePipeline = self.imagePipeline
                let threshold = self.threshold
                let progressAggregator = ScanProgressAggregator(workflow: .fullScan)
                async let videoSide: ScanSideResult = {
                    let result = try await Self.scanAndCompareVideos(
                        folders: folders,
                        scanner: scanner,
                        pipeline: pipeline,
                        threshold: threshold
                    ) { [weak self] update in
                        let aggregate = await progressAggregator.update(.video, with: update)
                        await MainActor.run { self?.progress = aggregate }
                    }
                    let aggregate = await progressAggregator.complete(.video, discoveredCount: result.items.count)
                    await MainActor.run { [weak self] in self?.progress = aggregate }
                    return result
                }()
                async let imageSide: ScanSideResult = {
                    let result = try await Self.scanAndCompareImages(
                        folders: folders,
                        imageScanner: imageScanner,
                        imagePipeline: imagePipeline,
                        threshold: threshold
                    ) { [weak self] update in
                        let aggregate = await progressAggregator.update(.image, with: update)
                        await MainActor.run { self?.progress = aggregate }
                    }
                    let aggregate = await progressAggregator.complete(.image, discoveredCount: result.items.count)
                    await MainActor.run { [weak self] in self?.progress = aggregate }
                    return result
                }()
                let (videoResult, imageResult) = try await (videoSide, imageSide)
                let items = videoResult.items + imageResult.items
                let relations = videoResult.relations + imageResult.relations
                let scanIssues = videoResult.issues + imageResult.issues
                // Publish the combined results once, after both kinds are done —
                // the sidebar shows groups only when scanning is complete.
                publish(items: items, relations: relations)
                try Task.checkCancellation()
                // `publish` already wrote the final combined items/relations/groups,
                // so only the progress and cache cleanup remain here.
                issues = scanIssues
                progress = ScanProgress(stage: .completed, fraction: 1, discoveredCount: items.count)
                pruneCaches(for: items)
            } catch is CancellationError {
                progress = ScanProgress(stage: .cancelled)
            } catch {
                groups = []
                presentedError = .message(error.localizedDescription)
                progress = ScanProgress(stage: .idle)
            }
        }
    }

    /// Scans every folder with the given loader, deduping items by URL and
    /// collecting issues. Shared by `startScan` and `discoverFiles` so the
    /// folder-iteration/cancellation/progress logic lives in one place.
    private nonisolated static func scanFolders(
        _ folders: [URL],
        load: @escaping @Sendable (URL) async throws -> (items: [MediaItem], issues: [ScanIssue])
    ) async throws -> (items: [MediaItem], issues: [ScanIssue]) {
        var items: [MediaItem] = []
        var issues: [ScanIssue] = []
        for folder in folders {
            try Task.checkCancellation()
            let result = try await load(folder)
            items.append(contentsOf: result.items)
            issues.append(contentsOf: result.issues)
        }
        return (Self.uniqueItemsByURL(items), issues)
    }

    private nonisolated static func scanAndCompareVideos(
        folders: [URL],
        scanner: VideoScanner,
        pipeline: any SimilarityProcessing,
        threshold: Double,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> ScanSideResult {
        let scanned = try await scanFolders(folders) { folder in
            let result = try await scanner.scan(folder: folder, progress: progress)
            return (result.videos, result.issues)
        }
        try Task.checkCancellation()
        let result = try await pipeline.process(videos: scanned.items, threshold: threshold, progress: progress)
        return ScanSideResult(items: result.videos, relations: result.relations, issues: scanned.issues)
    }

    private nonisolated static func scanAndCompareImages(
        folders: [URL],
        imageScanner: ImageScanner,
        imagePipeline: ImageSimilarityPipeline,
        threshold: Double,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> ScanSideResult {
        let scanned = try await scanFolders(folders) { folder in
            let result = try await imageScanner.scan(folder: folder, progress: progress)
            return (result.images, result.issues)
        }
        try Task.checkCancellation()
        let result = try await imagePipeline.process(images: scanned.items, threshold: threshold, progress: progress)
        return ScanSideResult(items: result.images, relations: result.relations, issues: scanned.issues)
    }

    private func scanFolders(
        _ folders: [URL],
        load: (URL) async throws -> (items: [MediaItem], issues: [ScanIssue])
    ) async throws -> (items: [MediaItem], issues: [ScanIssue]) {
        var items: [MediaItem] = []
        var issues: [ScanIssue] = []
        for folder in folders {
            try Task.checkCancellation()
            let result = try await load(folder)
            items.append(contentsOf: result.items)
            issues.append(contentsOf: result.issues)
        }
        return (Self.uniqueItemsByURL(items), issues)
    }

    private func loadVideos(folder: URL) async throws -> (items: [MediaItem], issues: [ScanIssue]) {
        let scanned = try await scanner.scan(folder: folder) { [weak self] update in
            await MainActor.run { self?.progress = update }
        }
        return (scanned.videos, scanned.issues)
    }

    private func loadImages(folder: URL) async throws -> (items: [MediaItem], issues: [ScanIssue]) {
        let scanned = try await imageScanner.scan(folder: folder) { [weak self] update in
            await MainActor.run { self?.progress = update }
        }
        return (scanned.images, scanned.issues)
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    /// Lightweight file discovery — populates `allItems` without running
    /// similarity pipelines.  Used by Browse mode.
    func discoverFiles() {
        guard !selectedFolders.isEmpty, !isScanning else { return }
        guard allItems.isEmpty else { return }

        let folders = selectedFolders
        scanTask?.cancel()
        progress = ScanProgress(stage: .discovering)

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Always scan both kinds (see startScan); scanMode only filters.
                let scanner = self.scanner
                let imageScanner = self.imageScanner
                let progressAggregator = ScanProgressAggregator(workflow: .discovery)
                async let videoScan: (items: [MediaItem], issues: [ScanIssue]) = {
                    let result = try await Self.scanFolders(folders) { folder in
                        let scanned = try await scanner.scan(folder: folder) { [weak self] update in
                            let aggregate = await progressAggregator.update(.video, with: update)
                            await MainActor.run { self?.progress = aggregate }
                        }
                        return (scanned.videos, scanned.issues)
                    }
                    let aggregate = await progressAggregator.complete(.video, discoveredCount: result.items.count)
                    await MainActor.run { [weak self] in self?.progress = aggregate }
                    return result
                }()
                async let imageScan: (items: [MediaItem], issues: [ScanIssue]) = {
                    let result = try await Self.scanFolders(folders) { folder in
                        let scanned = try await imageScanner.scan(folder: folder) { [weak self] update in
                            let aggregate = await progressAggregator.update(.image, with: update)
                            await MainActor.run { self?.progress = aggregate }
                        }
                        return (scanned.images, scanned.issues)
                    }
                    let aggregate = await progressAggregator.complete(.image, discoveredCount: result.items.count)
                    await MainActor.run { [weak self] in self?.progress = aggregate }
                    return result
                }()
                let (videoResult, imageResult) = try await (videoScan, imageScan)
                let items = videoResult.items + imageResult.items
                let scanIssues = videoResult.issues + imageResult.issues
                try Task.checkCancellation()
                allItems = items
                issues = scanIssues
                progress = ScanProgress(stage: .completed, fraction: 1, discoveredCount: items.count)
                pruneCaches(for: items)
            } catch is CancellationError {
                progress = ScanProgress(stage: .cancelled)
            } catch {
                presentedError = .message(error.localizedDescription)
                progress = ScanProgress(stage: .idle)
            }
        }
    }

    func setScanMode(_ mode: ScanMode) {
        guard scanMode != mode else { return }
        scanMode = mode
        // Scanning always covers both kinds, so switching mode is a pure
        // display filter — keep the data and selection; SidebarView filters
        // the group list by kind. If the selected group isn't visible under
        // the new mode, clear the selection so the detail pane doesn't show a
        // hidden group.
        if let selectedGroup, selectedGroup.kind != kind(for: mode) {
            selectedGroupID = nil
            selectedMediaID = nil
            sortedGroupItems = []
            groupSelectionAnchorID = nil
        }
        checkedMediaIDs.formIntersection(visibleItemIDs(for: mode))
    }

    private func pruneCaches(for items: [MediaItem]) {
        let validPaths = Set(items.map { $0.url.path })
        if let hashCache {
            Task { await hashCache.pruneStale(validPaths: validPaths) }
        }

        let thumbnailStore = self.thumbnailStore
        let validSourceURLs = Set(items.map(\.url))
        Task.detached(priority: .utility) {
            try? thumbnailStore.pruneStale(validSourceURLs: validSourceURLs)
        }
    }

    private func kind(for mode: ScanMode) -> MediaKind? {
        switch mode {
        case .all: nil
        case .videos: .video
        case .images: .image
        }
    }

    private func visibleItemIDs(for mode: ScanMode) -> Set<UUID> {
        guard let k = kind(for: mode) else { return Set(allItems.map(\.id)) }
        return Set(allItems.filter { $0.kind == k }.map(\.id))
    }

    func selectGroup(_ id: UUID?) {
        selectedGroupID = id
        checkedMediaIDs.removeAll()
        recomputeSortedGroupItems()
        // Select the first item *under the current sort order*, not the
        // grouper's raw items order, so the highlight matches the visual.
        selectedMediaID = sortedGroupItems.first?.id
        groupSelectionAnchorID = selectedMediaID
    }

    func selectGroupItem(_ id: UUID) {
        selectedMediaID = id
        groupSelectionAnchorID = id
        checkedMediaIDs.removeAll()
    }

    func toggleGroupItemSelection(_ id: UUID) {
        selectedMediaID = id
        toggleChecked(id)
    }

    func clearGroupItemSelection() {
        checkedMediaIDs.removeAll()
        groupSelectionAnchorID = selectedMediaID
    }

    func extendGroupItemSelection(to id: UUID) {
        let anchorID = groupSelectionAnchorID ?? selectedMediaID ?? id
        selectedMediaID = id

        guard
            let anchorIndex = sortedGroupItems.firstIndex(where: { $0.id == anchorID }),
            let targetIndex = sortedGroupItems.firstIndex(where: { $0.id == id })
        else {
            checkedMediaIDs.insert(id)
            groupSelectionAnchorID = id
            return
        }

        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        checkedMediaIDs.formUnion(sortedGroupItems[range].map(\.id))
    }

    /// Recomputes `sortedGroupItems` from the currently selected group. Cheap
    /// (one group's worth of items), and called only when the selected group,
    /// its contents, or the sort field/direction change — never on every frame
    /// of an unrelated change like dragging the display threshold.
    private func recomputeSortedGroupItems() {
        guard let group = selectedGroup else {
            sortedGroupItems = []
            return
        }
        sortedGroupItems = sorted(group.items, in: group)
    }

    /// Sorts `items` by the current Compare Media field and direction. Uses a
    /// filename-sorted base so equal keys stay stable.
    private func sorted(_ items: [MediaItem], in group: SimilarityGroup) -> [MediaItem] {
        // Stable base order, then stable-sort by the primary key.
        let base = items.sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
        let ascending = groupSortAscending
        let primary: (MediaItem, MediaItem) -> Bool
        switch groupSortField {
        case .similarity:
            primary = { group.score(for: $0.id) < group.score(for: $1.id) }
        case .fileSize:
            primary = { $0.fileSize < $1.fileSize }
        case .name:
            primary = { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
        case .duration:
            primary = { ($0.duration ?? 0) < ($1.duration ?? 0) }
        case .resolutionWidth:
            primary = { $0.width < $1.width }
        case .resolutionHeight:
            primary = { $0.height < $1.height }
        }
        // Swift's sort isn't guaranteed stable; emulate by ignoring order when
        // the primary key ties (falls through to the `base` order). Direction is
        // applied by flipping the comparator (not by reversing the array), so
        // tied items always keep their filename-ascending order regardless of
        // ascending vs descending — reversing the array would also flip ties,
        // which reads as random.
        return base.sorted { a, b in
            let less = primary(a, b)
            let greater = primary(b, a)
            if less == greater {
                return false // tie → keep base order
            }
            return ascending ? less : greater
        }
    }

    /// Toggles a Compare Media sort field: selecting the active field flips
    /// direction; a newly selected field starts descending (first click =
    /// descending, second click on the same field = ascending), which surfaces
    /// the "biggest / most-similar / longest" item at the top — the usual intent
    /// when reviewing duplicates.
    func toggleGroupSort(field: GroupSortField) {
        if groupSortField == field {
            groupSortAscending.toggle()
        } else {
            groupSortField = field
            groupSortAscending = false
        }
    }

    func requestDeletion(of media: MediaItem) {
        requestDeletion(of: [media])
    }

    func requestDeletion(of media: [MediaItem]) {
        if !media.isEmpty { deletePrompt = DeletePrompt(media: media, step: .choosingMethod) }
    }

    func requestCheckedDeletion() {
        let selected = allItems.filter { checkedMediaIDs.contains($0.id) }
        if !selected.isEmpty { deletePrompt = DeletePrompt(media: selected, step: .choosingMethod) }
    }

    func requestPreviewDeletion(defaultingTo media: MediaItem) {
        if checkedMediaIDs.isEmpty {
            requestDeletion(of: media)
        } else {
            requestCheckedDeletion()
        }
    }

    func toggleChecked(_ id: UUID) {
        if checkedMediaIDs.contains(id) { checkedMediaIDs.remove(id) } else { checkedMediaIDs.insert(id) }
        groupSelectionAnchorID = id
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
        rebuildGroups(preserving: groupsBeforeDeletion)
        deletePrompt = nil
        if !failures.isEmpty { presentedError = .message(failures.joined(separator: "\n")) }
    }

    func revealSelectedMedia() {
        if let media = selectedMedia { deletionService.reveal(media.url) }
    }

    func revealIssue(_ issue: ScanIssue) {
        deletionService.reveal(issue.url)
    }

    func openSelectedMedia() {
        if let media = selectedMedia { deletionService.open(media.url) }
    }

    func revealMedia(_ media: MediaItem) { deletionService.reveal(media.url) }
    func openMedia(_ media: MediaItem) { deletionService.open(media.url) }

    /// Returns the current cache footprint in human-readable size strings so the
    /// UI can show users what they'd be deleting.
    func cacheStats() async -> (thumbnailMB: String, hashMB: String) {
        let tb = Double(ThumbnailStore.shared.totalSize()) / 1_048_576
        let hb = Double(await hashCache?.sizeInBytes() ?? 0) / 1_048_576
        return (String(format: tb < 1 ? "%.1f" : "%.0f", tb),
                String(format: hb < 1 ? "%.1f" : "%.0f", hb))
    }

    /// Clears both the on-disk thumbnail cache and the perceptual-hash cache.
    /// The next scan re-derives everything, so it'll be slower — used by the
    /// "Clear Cache" button in Browse.
    func clearAllCaches() async {
        try? ThumbnailStore.shared.clearAll()
        await hashCache?.clearAll()
    }

    /// Remove a media item from allItems (and related relations/groups).
    /// Used after deletion from Browse mode.
    func removeItem(_ id: UUID) {
        let groupsBeforeRemoval = groups
        allItems.removeAll { $0.id == id }
        allRelations.removeAll { $0.contains(id) }
        checkedMediaIDs.remove(id)
        preserveGroupContinuity(groupsBeforeRemoval, deletedIDs: [id])
        rebuildGroups(preserving: groupsBeforeRemoval)
    }

    func replaceResultsForTesting(items: [MediaItem], relations: [SimilarityRelation]) {
        allItems = items
        allRelations = relations
        rebuildGroups()
    }

    func localizedError(_ language: AppLanguage) -> String? {
        presentedError?.localizedDescription(language)
    }

    private func rebuildGroups(preserving previousGroups: [SimilarityGroup]? = nil) {
        let beforeRebuild = previousGroups ?? groups
        // Remember where the selected group sat in the *visible* list before the
        // rebuild, so if it dissolves we can keep the cursor near that spot.
        let visibleBefore = beforeRebuild.filter { $0.kind.map { visibleKinds.contains($0) } ?? false }
        let visibleIndexBefore = selectedGroupID.flatMap { id in
            visibleBefore.firstIndex(where: { $0.id == id })
        }
        let rebuilt = SimilarityGrouper.groups(items: allItems, relations: allRelations, threshold: threshold)
        let dissolvedGroupKind = selectedGroup?.kind
        groups = groupsByPreservingStableIDs(rebuilt, previousGroups: beforeRebuild)
        checkedMediaIDs.formIntersection(Set(allItems.map(\.id)))
        if let selectedGroupID, groups.contains(where: { $0.id == selectedGroupID }) {
            // Group still exists; recompute the cached sort so the fallback below
            // picks the sorted-first item (not the grouper's raw first item).
            recomputeSortedGroupItems()
            let stillPresent = selectedMediaID.map { id in
                selectedGroup?.items.contains(where: { $0.id == id }) ?? false
            } ?? false
            if !stillPresent {
                selectedMediaID = sortedGroupItems.first?.id
            }
        } else if selectedGroupID != nil {
            // The selected group vanished (e.g. its last duplicate was deleted).
            // Pick the next group the user would expect to see: prefer the same
            // media kind at/near the old position, and stay within the current
            // scanMode's visible groups. Only cross kinds in .all mode, and only
            // after every same-kind group is exhausted.
            selectNextVisibleGroup(afterDissolving: dissolvedGroupKind, at: visibleIndexBefore)
        }
        // else: nothing was selected before — leave it that way.
    }

    /// The groups currently visible in the sidebar, in the order they're shown.
    /// In `.all` mode that's every video group followed by every image group
    /// (matching the sidebar's Videos/Images sections); in `.videos`/`.images`
    /// mode only the matching kind.
    private var visibleGroups: [SimilarityGroup] {
        switch scanMode {
        case .all: groups // sidebar renders videos-then-images, but the relative
                          // ordering within a kind is preserved, so a same-kind
                          // "next" lookup works on `groups` directly.
        case .videos: groups.filter { $0.kind == .video }
        case .images: groups.filter { $0.kind == .image }
        }
    }

    /// The media kinds shown under the current scanMode.
    private var visibleKinds: Set<MediaKind> {
        switch scanMode {
        case .all: [.video, .image]
        case .videos: [.video]
        case .images: [.image]
        }
    }

    /// After a group dissolves, pick the group the user expects to see next:
    /// prefer the next same-kind group in the visible list; if none follows,
    /// the preceding same-kind group (keeps the cursor near the old spot);
    /// only .all mode crosses to the other kind once same-kind groups are
    /// exhausted. In a single-kind mode, exhausting same-kind clears selection
    /// rather than jumping to a hidden group.
    private func selectNextVisibleGroup(afterDissolving kind: MediaKind?, at index: Int?) {
        let visible = visibleGroups
        guard !visible.isEmpty else {
            selectGroup(nil)
            return
        }

        guard let kind else {
            selectGroup(visible.last?.id)
            return
        }

        // Old visible index, clamped to the (already-rebuilt, shorter) list.
        let start = index.map { min(max($0, 0), max(visible.count - 1, 0)) } ?? 0

        // First same-kind group at or after the old position.
        if let after = visible.indices.dropFirst(start).first(where: { visible[$0].kind == kind }).map({ visible[$0] }) {
            selectGroup(after.id)
            return
        }
        // Else the nearest preceding same-kind group (keeps the cursor put).
        if let before = visible.indices.prefix(start).reversed().first(where: { visible[$0].kind == kind }).map({ visible[$0] }) {
            selectGroup(before.id)
            return
        }

        // No same-kind group remains at all.
        if scanMode == .all {
            // Fall back to the other kind at the same spot.
            let otherKind = other(kind)
            if let afterOther = visible.indices.dropFirst(start).first(where: { visible[$0].kind == otherKind }).map({ visible[$0] }) {
                selectGroup(afterOther.id)
            } else {
                selectGroup(visible.last?.id)
            }
        } else {
            // Single-kind mode: nothing visible of this kind left.
            selectGroup(nil)
        }
    }

    private func other(_ kind: MediaKind?) -> MediaKind? {
        switch kind {
        case .video: .image
        case .image: .video
        default: nil
        }
    }

    private func publish(items: [MediaItem], relations: [SimilarityRelation]) {
        allItems = items
        allRelations = relations
        groups = SimilarityGrouper.groups(items: items, relations: relations, threshold: threshold)
        // Don't auto-select a group — let the user pick. The right pane shows
        // "Select a similar group" / "Select a file" until the user clicks.
        selectedGroupID = nil
        selectedMediaID = nil
        sortedGroupItems = []
        groupSelectionAnchorID = nil
    }

    private func resetResults() {
        allItems = []
        allRelations = []
        groups = []
        selectedGroupID = nil
        selectedMediaID = nil
        sortedGroupItems = []
        checkedMediaIDs = []
        groupSelectionAnchorID = nil
        progress = ScanProgress()
        issues = []
    }

    private nonisolated static func uniqueItemsByURL(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.url.standardizedFileURL.path).inserted }
    }

    private func groupsByPreservingStableIDs(
        _ rebuiltGroups: [SimilarityGroup],
        previousGroups: [SimilarityGroup]
    ) -> [SimilarityGroup] {
        guard !previousGroups.isEmpty else { return rebuiltGroups }
        var availablePreviousGroups = previousGroups

        return rebuiltGroups.map { group in
            let groupItemIDs = Set(group.items.map(\.id))
            var bestMatch: (index: Int, overlap: Int)?

            for (index, previousGroup) in availablePreviousGroups.enumerated() where previousGroup.kind == group.kind {
                let previousItemIDs = Set(previousGroup.items.map(\.id))
                let overlap = groupItemIDs.intersection(previousItemIDs).count
                guard overlap >= 2 else { continue }
                if bestMatch == nil || overlap > bestMatch!.overlap {
                    bestMatch = (index, overlap)
                }
            }

            guard let bestMatch else { return group }
            let previousGroup = availablePreviousGroups.remove(at: bestMatch.index)
            return SimilarityGroup(id: previousGroup.id, items: group.items, relations: group.relations)
        }
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
