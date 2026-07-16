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

private struct DeletionRebuildResult: Sendable {
    let items: [MediaItem]
    let relations: [SimilarityRelation]
    let groups: [SimilarityGroup]
}

private struct MediaPairIdentity: Hashable, Sendable {
    let firstID: UUID
    let secondID: UUID

    init(_ firstID: UUID, _ secondID: UUID) {
        if firstID.uuidString < secondID.uuidString {
            self.firstID = firstID
            self.secondID = secondID
        } else {
            self.firstID = secondID
            self.secondID = firstID
        }
    }
}

typealias SimilarityGroupBuilder = @Sendable (
    [MediaItem],
    [SimilarityRelation],
    Double
) async throws -> [SimilarityGroup]

enum ScanProgressLane: CaseIterable, Hashable, Sendable {
    case video
    case image
}

enum ScanProgressWorkflow: Sendable {
    case fullScan
    case discovery
}

actor ScanProgressAggregator {
    private struct AggregatedComparisonDetails {
        let phase: ScanComparisonPhase
        let completed: Int
        let total: Int
        let cacheHits: Int
        let cacheTotal: Int
        let cacheKind: ScanProgressCacheKind?
    }

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

    func complete(_ lane: ScanProgressLane, discoveredCount: Int) -> ScanProgress? {
        var progress = updates[lane] ?? ScanProgress(stage: .completed, fraction: 1)
        progress.stage = .completed
        progress.fraction = 1
        progress.discoveredCount = max(progress.discoveredCount, discoveredCount)
        updates[lane] = progress
        completedLanes.insert(lane)
        guard completedLanes.count < ScanProgressLane.allCases.count else { return nil }
        return aggregate(preferredLane: lane)
    }

    private func aggregate(preferredLane: ScanProgressLane) -> ScanProgress {
        let allLanes = ScanProgressLane.allCases
        let rawFraction = allLanes.reduce(into: (weighted: 0.0, total: 0.0)) { partial, lane in
            let progress = updates[lane] ?? ScanProgress(stage: .discovering, fraction: 0)
            let weight = Double(max(1, progress.discoveredCount))
            partial.weighted += normalizedFraction(for: progress) * weight
            partial.total += weight
        }
        let nextFraction = rawFraction.total > 0 ? rawFraction.weighted / rawFraction.total : 0
        emittedFraction = max(emittedFraction, min(1, max(0, nextFraction)))
        let currentStage = aggregateStage()
        if stageRank(currentStage) >= stageRank(emittedStage) {
            emittedStage = currentStage
        }

        let displayProgress = progressForDisplay(preferredLane: preferredLane, stage: currentStage)
            ?? fallbackProgressForDisplay(preferredLane: preferredLane)
        let displayStage = displayProgress?.stage ?? currentStage
        let comparisonDetails = displayStage == .comparing
            ? aggregatedComparisonDetails(preferredPhase: displayProgress?.comparisonPhase)
            : nil
        let expectedCacheKind = cacheKind(for: displayStage)
        let displayedCacheKind = comparisonDetails?.cacheKind
            ?? (displayProgress?.cacheKind == expectedCacheKind ? expectedCacheKind : nil)
        let displayedComparisonPhase = comparisonDetails?.phase
            ?? (displayProgress?.stage == displayStage ? displayProgress?.comparisonPhase : nil)

        return ScanProgress(
            stage: displayStage,
            fraction: emittedFraction,
            currentFile: displayProgress?.currentFile ?? "",
            discoveredCount: updates.values.reduce(0) { $0 + $1.discoveredCount },
            cacheHits: comparisonDetails?.cacheHits ?? (displayedCacheKind == nil ? 0 : displayProgress?.cacheHits ?? 0),
            cacheTotal: comparisonDetails?.cacheTotal ?? (displayedCacheKind == nil ? 0 : displayProgress?.cacheTotal ?? 0),
            cacheKind: displayedCacheKind != nil && (comparisonDetails?.cacheTotal ?? displayProgress?.cacheTotal ?? 0) > 0 ? displayedCacheKind : nil,
            comparisonPhase: displayedComparisonPhase,
            comparisonCompleted: displayedComparisonPhase == nil ? 0 : (comparisonDetails?.completed ?? displayProgress?.comparisonCompleted ?? 0),
            comparisonTotal: displayedComparisonPhase == nil ? 0 : (comparisonDetails?.total ?? displayProgress?.comparisonTotal ?? 0)
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

    private func progressForDisplay(preferredLane: ScanProgressLane, stage: ScanStage) -> ScanProgress? {
        if let preferred = updates[preferredLane],
           preferred.stage == stage,
           hasDisplayDetails(preferred, for: stage) {
            return preferred
        }
        for lane in ScanProgressLane.allCases where lane != preferredLane {
            if let progress = updates[lane],
               progress.stage == stage,
               hasDisplayDetails(progress, for: stage) {
                return progress
            }
        }
        return nil
    }

    private func aggregatedComparisonDetails(preferredPhase: ScanComparisonPhase?) -> AggregatedComparisonDetails? {
        guard let phase = preferredPhase ?? activeComparisonPhase() else { return nil }
        let matching = ScanProgressLane.allCases
            .compactMap { updates[$0] }
            .filter { progress in
                progress.comparisonPhase == phase
                    && (progress.stage == .comparing || progress.stage == .completed)
            }
        guard !matching.isEmpty else { return nil }

        let completed = matching.reduce(0) { partial, progress in
            let total = max(progress.comparisonTotal, 0)
            return partial + max(0, min(progress.comparisonCompleted, total))
        }
        let total = matching.reduce(0) { $0 + max($1.comparisonTotal, 0) }
        let cacheTotal = matching.reduce(0) { $0 + max($1.cacheTotal, 0) }
        let cacheHits = matching.reduce(0) { partial, progress in
            partial + max(0, min(progress.cacheHits, progress.cacheTotal))
        }
        let cacheKind: ScanProgressCacheKind? = matching.contains { $0.cacheKind == .relation } && cacheTotal > 0
            ? .relation
            : nil
        return AggregatedComparisonDetails(
            phase: phase,
            completed: completed,
            total: total,
            cacheHits: cacheHits,
            cacheTotal: cacheTotal,
            cacheKind: cacheKind
        )
    }

    private func activeComparisonPhase() -> ScanComparisonPhase? {
        ScanProgressLane.allCases
            .compactMap { updates[$0] }
            .first { $0.stage == .comparing }?
            .comparisonPhase
    }

    private func fallbackProgressForDisplay(preferredLane: ScanProgressLane) -> ScanProgress? {
        if let preferred = updates[preferredLane],
           isActiveDisplayStage(preferred.stage),
           hasDisplayDetails(preferred, for: preferred.stage) {
            return preferred
        }
        return ScanProgressLane.allCases
            .filter { $0 != preferredLane }
            .compactMap { updates[$0] }
            .filter { isActiveDisplayStage($0.stage) && hasDisplayDetails($0, for: $0.stage) }
            .max { stageRank($0.stage) < stageRank($1.stage) }
    }

    private func hasDisplayDetails(_ progress: ScanProgress, for stage: ScanStage) -> Bool {
        !progress.currentFile.isEmpty
            || (progress.cacheKind == cacheKind(for: stage) && progress.cacheTotal > 0)
            || progress.comparisonPhase != nil
    }

    private func isActiveDisplayStage(_ stage: ScanStage) -> Bool {
        switch stage {
        case .readingMetadata, .prehashing, .hashing, .comparing:
            true
        case .idle, .discovering, .completed, .cancelled:
            false
        }
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
    private var thresholdRebuildGeneration = 0
    private var resultsRevision = 0

    private func scheduleThresholdRebuild() {
        guard !isDeleting else { return }
        thresholdRebuildTask?.cancel()
        thresholdRebuildGeneration &+= 1
        let generation = thresholdRebuildGeneration
        thresholdRebuildTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let self else { return }

            let revision = self.resultsRevision
            let threshold = self.threshold
            let items = self.allItems
            let relations = self.allRelations
            let previousGroups = self.groups
            let groupBuilder = self.groupBuilder
            guard let rebuilt = try? await groupBuilder(items, relations, threshold) else { return }

            guard
                !Task.isCancelled,
                self.thresholdRebuildGeneration == generation,
                self.resultsRevision == revision,
                self.threshold == threshold
            else { return }
            self.applyRebuiltGroups(rebuilt, preserving: previousGroups)
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
    @Published private(set) var isScanning = false
    @Published private(set) var isClearingCache = false
    @Published private(set) var isDeleting = false
    @Published private(set) var itemsRevision = 0
    @Published private(set) var issues: [ScanIssue] = []
    @Published var presentedError: PresentedError?
    @Published var deletePrompt: DeletePrompt?
    @Published var scanMode: ScanMode = .all
    @Published var scanIntensity: ScanIntensity
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
    private let activityManager: ScanActivityManaging
    private let groupBuilder: SimilarityGroupBuilder
    private var groupSelectionAnchorID: UUID?
    private var activeScanID: UUID?
    private var scanActivity: NSObjectProtocol?

    init(
        scanner: VideoScanner = VideoScanner(),
        imageScanner: ImageScanner = ImageScanner(),
        pipeline: (any SimilarityProcessing)? = nil,
        deletionService: any DeletionServicing = DeletionService(),
        hashCache: (any HashCaching)? = ScanViewModel.makeDefaultHashCache(),
        thumbnailStore: ThumbnailStore = .shared,
        activityManager: ScanActivityManaging = ProcessInfoScanActivityManager(),
        scanIntensity: ScanIntensity = .defaultIntensity,
        groupBuilder: SimilarityGroupBuilder? = nil
    ) {
        self.deletionService = deletionService
        self.hashCache = hashCache
        self.thumbnailStore = thumbnailStore
        self.activityManager = activityManager
        self.scanIntensity = scanIntensity
        self.groupBuilder = groupBuilder ?? ScanViewModel.buildGroupsOffMain
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

    private nonisolated static func buildGroupsOffMain(
        items: [MediaItem],
        relations: [SimilarityRelation],
        threshold: Double
    ) async throws -> [SimilarityGroup] {
        let worker = Task.detached(priority: .userInitiated) {
            try SimilarityGrouper.cancellableGroups(
                items: items,
                relations: relations,
                threshold: threshold
            )
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private func beginScanRun(reason: String) -> UUID {
        let scanID = UUID()
        activeScanID = scanID
        scanActivity = activityManager.begin(reason: reason)
        isScanning = true
        return scanID
    }

    private func finishScanRun(_ scanID: UUID) {
        guard activeScanID == scanID else { return }
        activeScanID = nil
        scanTask = nil
        if let activity = scanActivity {
            activityManager.end(activity)
        }
        scanActivity = nil
        isScanning = false
    }

    private func updateProgress(_ progress: ScanProgress, for scanID: UUID) {
        guard activeScanID == scanID else { return }
        self.progress = progress
    }

    private func isCurrentScan(_ scanID: UUID) -> Bool {
        activeScanID == scanID
    }

    /// All media items discovered during scanning or file discovery.
    var items: [MediaItem] { allItems }

    var isBusy: Bool { isScanning || isClearingCache || isDeleting }

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
        guard !isBusy else { return false }
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
        guard !isBusy else { return }
        let path = folder.standardizedFileURL.path
        guard selectedFolders.contains(where: { $0.standardizedFileURL.path == path }) else { return }
        selectedFolders.removeAll { $0.standardizedFileURL.path == path }
        resetResults()
    }

    @discardableResult
    func clearFolders() -> Bool {
        guard !isBusy, !selectedFolders.isEmpty else { return false }
        selectedFolders.removeAll()
        resetResults()
        return true
    }

    func startScan() {
        guard !selectedFolders.isEmpty, !isBusy else { return }
        let folders = selectedFolders
        scanTask?.cancel()
        invalidatePendingGroupBuild()
        let scanID = beginScanRun(reason: "Scanning media for similar files")
        progress = ScanProgress(stage: .discovering)
        replaceItems(with: [])
        allRelations = []
        groups = []
        checkedMediaIDs = []
        groupSelectionAnchorID = nil
        issues = []
        scanTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishScanRun(scanID) }
            do {
                // Always scan both kinds so the user can switch All / Images /
                // Videos after scanning without re-scanning; `scanMode` only
                // filters the sidebar display.
                let scanIntensity = self.scanIntensity
                let metadataLimit = scanIntensity.metadataConcurrencyLimit(
                    processorCount: ProcessInfo.processInfo.activeProcessorCount
                )
                let scanner = self.scanner.withMaxConcurrentLoads(metadataLimit)
                let imageScanner = self.imageScanner.withMaxConcurrentLoads(metadataLimit)
                let pipeline = self.pipeline
                let imagePipeline = self.imagePipeline
                let threshold = self.threshold
                let progressAggregator = ScanProgressAggregator(workflow: .fullScan)
                async let videoSide: ScanSideResult = {
                    let result = try await Self.scanAndCompareVideos(
                        folders: folders,
                        scanner: scanner,
                        pipeline: pipeline,
                        threshold: threshold,
                        scanIntensity: scanIntensity
                    ) { [weak self] update in
                        let aggregate = await progressAggregator.update(.video, with: update)
                        await MainActor.run { self?.updateProgress(aggregate, for: scanID) }
                    }
                    if let aggregate = await progressAggregator.complete(.video, discoveredCount: result.items.count) {
                        await MainActor.run { [weak self] in self?.updateProgress(aggregate, for: scanID) }
                    }
                    return result
                }()
                async let imageSide: ScanSideResult = {
                    let result = try await Self.scanAndCompareImages(
                        folders: folders,
                        imageScanner: imageScanner,
                        imagePipeline: imagePipeline,
                        threshold: threshold,
                        scanIntensity: scanIntensity
                    ) { [weak self] update in
                        let aggregate = await progressAggregator.update(.image, with: update)
                        await MainActor.run { self?.updateProgress(aggregate, for: scanID) }
                    }
                    if let aggregate = await progressAggregator.complete(.image, discoveredCount: result.items.count) {
                        await MainActor.run { [weak self] in self?.updateProgress(aggregate, for: scanID) }
                    }
                    return result
                }()
                let (videoResult, imageResult) = try await (videoSide, imageSide)
                let items = videoResult.items + imageResult.items
                let relations = videoResult.relations + imageResult.relations
                let scanIssues = videoResult.issues + imageResult.issues
                let rebuiltGroups = try await buildGroupsForCurrentThreshold(
                    items: items,
                    relations: relations
                )
                try Task.checkCancellation()
                guard isCurrentScan(scanID) else { throw CancellationError() }
                // Publish the combined results once, after both kinds are done —
                // the sidebar shows groups only when scanning is complete.
                publish(items: items, relations: relations, groups: rebuiltGroups)
                // `publish` already wrote the final combined items/relations/groups.
                // Cache entries are historical across every scanned folder, so a
                // partial folder selection must never prune the global cache.
                issues = scanIssues
                updateProgress(
                    ScanProgress(stage: .completed, fraction: 1, discoveredCount: items.count),
                    for: scanID
                )
            } catch is CancellationError {
                updateProgress(ScanProgress(stage: .cancelled), for: scanID)
            } catch {
                guard isCurrentScan(scanID) else { return }
                groups = []
                presentedError = .message(error.localizedDescription)
                updateProgress(ScanProgress(stage: .idle), for: scanID)
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
        scanIntensity: ScanIntensity,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> ScanSideResult {
        let scanned = try await scanFolders(folders) { folder in
            let result = try await scanner.scan(folder: folder, progress: progress)
            return (result.videos, result.issues)
        }
        try Task.checkCancellation()
        let result = try await pipeline.process(
            videos: scanned.items,
            threshold: threshold,
            scanIntensity: scanIntensity,
            progress: progress
        )
        return ScanSideResult(items: result.videos, relations: result.relations, issues: scanned.issues)
    }

    private nonisolated static func scanAndCompareImages(
        folders: [URL],
        imageScanner: ImageScanner,
        imagePipeline: ImageSimilarityPipeline,
        threshold: Double,
        scanIntensity: ScanIntensity,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> ScanSideResult {
        let scanned = try await scanFolders(folders) { folder in
            let result = try await imageScanner.scan(folder: folder, progress: progress)
            return (result.images, result.issues)
        }
        try Task.checkCancellation()
        let result = try await imagePipeline.process(
            images: scanned.items,
            threshold: threshold,
            scanIntensity: scanIntensity,
            progress: progress
        )
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
        guard !selectedFolders.isEmpty, !isBusy else { return }
        guard allItems.isEmpty else { return }

        let folders = selectedFolders
        scanTask?.cancel()
        invalidatePendingGroupBuild()
        let scanID = beginScanRun(reason: "Reading media metadata")
        progress = ScanProgress(stage: .discovering)

        scanTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishScanRun(scanID) }
            do {
                // Always scan both kinds (see startScan); scanMode only filters.
                let metadataLimit = self.scanIntensity.metadataConcurrencyLimit(
                    processorCount: ProcessInfo.processInfo.activeProcessorCount
                )
                let scanner = self.scanner.withMaxConcurrentLoads(metadataLimit)
                let imageScanner = self.imageScanner.withMaxConcurrentLoads(metadataLimit)
                let progressAggregator = ScanProgressAggregator(workflow: .discovery)
                async let videoScan: (items: [MediaItem], issues: [ScanIssue]) = {
                    let result = try await Self.scanFolders(folders) { folder in
                        let scanned = try await scanner.scan(folder: folder) { [weak self] update in
                            let aggregate = await progressAggregator.update(.video, with: update)
                            await MainActor.run { self?.updateProgress(aggregate, for: scanID) }
                        }
                        return (scanned.videos, scanned.issues)
                    }
                    if let aggregate = await progressAggregator.complete(.video, discoveredCount: result.items.count) {
                        await MainActor.run { [weak self] in self?.updateProgress(aggregate, for: scanID) }
                    }
                    return result
                }()
                async let imageScan: (items: [MediaItem], issues: [ScanIssue]) = {
                    let result = try await Self.scanFolders(folders) { folder in
                        let scanned = try await imageScanner.scan(folder: folder) { [weak self] update in
                            let aggregate = await progressAggregator.update(.image, with: update)
                            await MainActor.run { self?.updateProgress(aggregate, for: scanID) }
                        }
                        return (scanned.images, scanned.issues)
                    }
                    if let aggregate = await progressAggregator.complete(.image, discoveredCount: result.items.count) {
                        await MainActor.run { [weak self] in self?.updateProgress(aggregate, for: scanID) }
                    }
                    return result
                }()
                let (videoResult, imageResult) = try await (videoScan, imageScan)
                let items = videoResult.items + imageResult.items
                let scanIssues = videoResult.issues + imageResult.issues
                try Task.checkCancellation()
                guard isCurrentScan(scanID) else { throw CancellationError() }
                invalidatePendingGroupBuild()
                replaceItems(with: items)
                issues = scanIssues
                updateProgress(
                    ScanProgress(stage: .completed, fraction: 1, discoveredCount: items.count),
                    for: scanID
                )
            } catch is CancellationError {
                updateProgress(ScanProgress(stage: .cancelled), for: scanID)
            } catch {
                guard isCurrentScan(scanID) else { return }
                presentedError = .message(error.localizedDescription)
                updateProgress(ScanProgress(stage: .idle), for: scanID)
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
        if let targetKind = kind(for: mode),
           let selectedGroup,
           selectedGroup.kind != targetKind {
            selectedGroupID = nil
            selectedMediaID = nil
            sortedGroupItems = []
            groupSelectionAnchorID = nil
        }
        checkedMediaIDs.formIntersection(visibleItemIDs(for: mode))
    }

    func setScanIntensity(_ intensity: ScanIntensity) {
        guard scanIntensity != intensity else { return }
        scanIntensity = intensity
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
        guard !isDeleting, let targets = deletePrompt?.media else { return }
        isDeleting = true
        defer { isDeleting = false }

        invalidatePendingGroupBuild()
        let groupsBeforeDeletion = groups
        var deletedIDs = Set<UUID>()
        var failures: [String] = []
        for media in targets {
            do {
                try await deletionService.delete(url: media.url, mode: mode)
                deletedIDs.insert(media.id)
            } catch { failures.append("\(media.filename): \(error.localizedDescription)") }
        }

        if !deletedIDs.isEmpty {
            let threshold = threshold
            let rebuilt = await Self.rebuildAfterDeletionOffMain(
                items: allItems,
                relations: allRelations,
                previousGroups: groupsBeforeDeletion,
                deletedIDs: deletedIDs,
                threshold: threshold
            )
            replaceItems(with: rebuilt.items)
            allRelations = rebuilt.relations
            checkedMediaIDs.subtract(deletedIDs)
            applyRebuiltGroups(
                rebuilt.groups,
                preserving: groupsBeforeDeletion,
                stableIDsAlreadyApplied: true
            )
        }
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
        let tb = Double(await thumbnailStore.totalSize()) / 1_048_576
        let hb = Double(await hashCache?.sizeInBytes() ?? 0) / 1_048_576
        return (String(format: tb < 1 ? "%.1f" : "%.0f", tb),
                String(format: hb < 1 ? "%.1f" : "%.0f", hb))
    }

    /// Clears both the on-disk thumbnail cache and the perceptual-hash cache.
    /// The next scan re-derives everything, so it'll be slower — used by the
    /// "Clear Cache" button in the main toolbar.
    @discardableResult
    func clearAllCaches() async -> Bool {
        guard !isBusy else { return false }
        isClearingCache = true
        defer { isClearingCache = false }

        MediaThumbnailImageCache.shared.removeAll()
        var failures: [String] = []
        do {
            try await thumbnailStore.clearAll()
        } catch {
            failures.append(error.localizedDescription)
        }
        do {
            try await hashCache?.clearAll()
        } catch {
            failures.append(error.localizedDescription)
        }

        guard failures.isEmpty else {
            presentedError = .message(failures.joined(separator: "\n"))
            return false
        }
        return true
    }

    /// Remove a media item from allItems (and related relations/groups).
    /// Used after deletion from Browse mode.
    func removeItem(_ id: UUID) {
        let groupsBeforeRemoval = groups
        let hadItem = allItems.contains { $0.id == id }
        allItems.removeAll { $0.id == id }
        allRelations.removeAll { $0.contains(id) }
        checkedMediaIDs.remove(id)
        if hadItem {
            invalidatePendingGroupBuild()
            noteItemsChanged()
        }
        allRelations = Self.relationsByPreservingGroupContinuity(
            items: allItems,
            relations: allRelations,
            previousGroups: groupsBeforeRemoval,
            deletedIDs: [id],
            threshold: threshold
        )
        rebuildGroups(preserving: groupsBeforeRemoval)
    }

    func replaceResultsForTesting(items: [MediaItem], relations: [SimilarityRelation]) {
        invalidatePendingGroupBuild()
        replaceItems(with: items)
        allRelations = relations
        rebuildGroups()
    }

    func replaceProgressForTesting(_ progress: ScanProgress) {
        self.progress = progress
    }

    func localizedError(_ language: AppLanguage) -> String? {
        presentedError?.localizedDescription(language)
    }

    private func rebuildGroups(preserving previousGroups: [SimilarityGroup]? = nil) {
        let beforeRebuild = previousGroups ?? groups
        let rebuilt = SimilarityGrouper.groups(items: allItems, relations: allRelations, threshold: threshold)
        applyRebuiltGroups(rebuilt, preserving: beforeRebuild)
    }

    private func applyRebuiltGroups(
        _ rebuilt: [SimilarityGroup],
        preserving beforeRebuild: [SimilarityGroup],
        stableIDsAlreadyApplied: Bool = false
    ) {
        // Remember where the selected group sat in the *visible* list before the
        // rebuild, so if it dissolves we can keep the cursor near that spot.
        let visibleBefore = beforeRebuild.filter { $0.kind.map { visibleKinds.contains($0) } ?? false }
        let visibleIndexBefore = selectedGroupID.flatMap { id in
            visibleBefore.firstIndex(where: { $0.id == id })
        }
        let dissolvedGroupKind = selectedGroup?.kind
        groups = stableIDsAlreadyApplied
            ? rebuilt
            : Self.groupsByPreservingStableIDs(rebuilt, previousGroups: beforeRebuild)
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

    private func buildGroupsForCurrentThreshold(
        items: [MediaItem],
        relations: [SimilarityRelation]
    ) async throws -> [SimilarityGroup] {
        while true {
            try Task.checkCancellation()
            let targetThreshold = threshold
            let rebuilt = try await groupBuilder(items, relations, targetThreshold)
            try Task.checkCancellation()
            if threshold == targetThreshold {
                return rebuilt
            }
        }
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

    private func publish(
        items: [MediaItem],
        relations: [SimilarityRelation],
        groups rebuiltGroups: [SimilarityGroup]
    ) {
        invalidatePendingGroupBuild()
        replaceItems(with: items)
        allRelations = relations
        groups = rebuiltGroups
        // Don't auto-select a group — let the user pick. The right pane shows
        // "Select a similar group" / "Select a file" until the user clicks.
        selectedGroupID = nil
        selectedMediaID = nil
        sortedGroupItems = []
        groupSelectionAnchorID = nil
    }

    private func resetResults() {
        invalidatePendingGroupBuild()
        replaceItems(with: [])
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

    private func replaceItems(with items: [MediaItem]) {
        guard allItems != items else { return }
        allItems = items
        noteItemsChanged()
    }

    private func noteItemsChanged() {
        itemsRevision &+= 1
    }

    private func invalidatePendingGroupBuild() {
        resultsRevision &+= 1
        thresholdRebuildGeneration &+= 1
        thresholdRebuildTask?.cancel()
        thresholdRebuildTask = nil
    }

    private nonisolated static func uniqueItemsByURL(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.url.standardizedFileURL.path).inserted }
    }

    private nonisolated static func groupsByPreservingStableIDs(
        _ rebuiltGroups: [SimilarityGroup],
        previousGroups: [SimilarityGroup]
    ) -> [SimilarityGroup] {
        guard !previousGroups.isEmpty else { return rebuiltGroups }
        var previousGroupIndicesByItemID: [UUID: [Int]] = [:]
        for (index, group) in previousGroups.enumerated() {
            for item in group.items {
                previousGroupIndicesByItemID[item.id, default: []].append(index)
            }
        }
        var availablePreviousGroupIndices = Set(previousGroups.indices)

        return rebuiltGroups.map { group in
            var overlapByPreviousGroupIndex: [Int: Int] = [:]
            for item in group.items {
                for index in previousGroupIndicesByItemID[item.id, default: []]
                    where availablePreviousGroupIndices.contains(index)
                        && previousGroups[index].kind == group.kind {
                    overlapByPreviousGroupIndex[index, default: 0] += 1
                }
            }

            var bestMatch: (index: Int, overlap: Int)?
            for (index, overlap) in overlapByPreviousGroupIndex where overlap >= 2 {
                if bestMatch == nil
                    || overlap > bestMatch!.overlap
                    || (overlap == bestMatch!.overlap && index < bestMatch!.index) {
                    bestMatch = (index, overlap)
                }
            }

            guard let bestMatch else { return group }
            availablePreviousGroupIndices.remove(bestMatch.index)
            let previousGroup = previousGroups[bestMatch.index]
            return SimilarityGroup(id: previousGroup.id, items: group.items, relations: group.relations)
        }
    }

    private nonisolated static func rebuildAfterDeletionOffMain(
        items: [MediaItem],
        relations: [SimilarityRelation],
        previousGroups: [SimilarityGroup],
        deletedIDs: Set<UUID>,
        threshold: Double
    ) async -> DeletionRebuildResult {
        await Task.detached(priority: .userInitiated) {
            let remainingItems = items.filter { !deletedIDs.contains($0.id) }
            let remainingRelations = Self.relationsByPreservingGroupContinuity(
                items: remainingItems,
                relations: relations.filter {
                    !deletedIDs.contains($0.firstID) && !deletedIDs.contains($0.secondID)
                },
                previousGroups: previousGroups,
                deletedIDs: deletedIDs,
                threshold: threshold
            )
            let rebuilt = SimilarityGrouper.groups(
                items: remainingItems,
                relations: remainingRelations,
                threshold: threshold
            )
            return DeletionRebuildResult(
                items: remainingItems,
                relations: remainingRelations,
                groups: Self.groupsByPreservingStableIDs(rebuilt, previousGroups: previousGroups)
            )
        }.value
    }

    private nonisolated static func relationsByPreservingGroupContinuity(
        items: [MediaItem],
        relations: [SimilarityRelation],
        previousGroups: [SimilarityGroup],
        deletedIDs: Set<UUID>,
        threshold: Double
    ) -> [SimilarityRelation] {
        guard !deletedIDs.isEmpty else { return relations }
        let remainingIDs = Set(items.map(\.id))
        var updatedRelations = relations
        var existingPairs = Set(relations.map { MediaPairIdentity($0.firstID, $0.secondID) })

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
                let pair = MediaPairIdentity(first.id, second.id)
                if existingPairs.insert(pair).inserted {
                    updatedRelations.append(SimilarityRelation(
                        firstID: first.id,
                        secondID: second.id,
                        score: score,
                        evidence: evidence
                    ))
                }
            }
        }
        return updatedRelations
    }
}
