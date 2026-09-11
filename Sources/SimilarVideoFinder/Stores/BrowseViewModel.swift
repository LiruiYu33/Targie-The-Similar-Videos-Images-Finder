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
import Foundation
import SwiftUI

@MainActor
final class BrowseViewModel: ObservableObject {
    // MARK: - Filters

    enum MediaFilter: String, CaseIterable, Identifiable, Sendable {
        case all, images, videos
        var id: String { rawValue }
    }

    enum ResolutionComparator: String, CaseIterable, Identifiable, Sendable {
        case lessThan = "<"
        case greaterThan = ">"
        var id: String { rawValue }
    }

    struct ResolutionPreset: Identifiable, Sendable, Equatable {
        let id: String
        let label: String
        let shortEdge: Int
    }

    static let resolutionPresets: [ResolutionPreset] = [
        ResolutionPreset(id: "320p",  label: "320p",  shortEdge: 320),
        ResolutionPreset(id: "480p",  label: "480p",  shortEdge: 480),
        ResolutionPreset(id: "720p",  label: "720p",  shortEdge: 720),
        ResolutionPreset(id: "1080p", label: "1080p", shortEdge: 1080),
        ResolutionPreset(id: "2K",    label: "2K",    shortEdge: 1440),
    ]

    // MARK: - Sort

    enum SortField: String, CaseIterable, Identifiable, Sendable {
        case name, fileSize, modifiedTime
        case resolutionWidth, resolutionHeight
        var id: String { rawValue }

        /// Whether this field sorts by a resolution dimension (width or height).
        var isResolution: Bool { self == .resolutionWidth || self == .resolutionHeight }
    }

    // MARK: - Published State

    /// Filtered and sorted items ready for display.
    /// Explicitly published so the table reliably reorders when sort/filter changes.
    @Published var displayedItems: [MediaItem] = []

    /// Incremented on every recompute so the table reorders rows
    /// when the same items appear in a different sort order.
    @Published var sortVersion: Int = 0

    @Published var sortField: SortField = .name {
        didSet {
            guard sortField != oldValue else { return }
            requestDisplayedItemsRecompute(bumpSortVersion: true)
        }
    }
    @Published var sortAscending: Bool = true {
        didSet {
            guard sortAscending != oldValue else { return }
            requestDisplayedItemsRecompute(bumpSortVersion: true)
        }
    }
    @Published var isResolutionSortPresented: Bool = false
    @Published var mediaFilter: MediaFilter = .all {
        didSet {
            guard mediaFilter != oldValue else { return }
            requestDisplayedItemsRecompute()
        }
    }
    @Published var resolutionComparator: ResolutionComparator = .lessThan {
        didSet {
            guard resolutionComparator != oldValue else { return }
            requestDisplayedItemsRecompute()
        }
    }
    @Published private(set) var selectedResolutionPreset: ResolutionPreset? {
        didSet {
            guard selectedResolutionPreset != oldValue else { return }
            requestDisplayedItemsRecompute()
        }
    }
    @Published private(set) var manualWidth: String = "" {
        didSet {
            guard manualWidth != oldValue else { return }
            requestDisplayedItemsRecompute()
        }
    }
    @Published private(set) var manualHeight: String = "" {
        didSet {
            guard manualHeight != oldValue else { return }
            requestDisplayedItemsRecompute()
        }
    }
    @Published var searchText: String = "" {
        didSet {
            guard searchText != oldValue else { return }
            requestDisplayedItemsRecompute()
        }
    }
    @Published var selectedMediaIDs: Set<UUID> = []
    @Published var primarySelectionID: UUID?
    @Published var selectionAnchorID: UUID?
    @Published var isBatchSelectionMode = false
    @Published var isFilterPresented: Bool = false

    let scanModel: ScanViewModel
    private var cancellables = Set<AnyCancellable>()
    private var isBatchingDisplayedItemsRecompute = false
    private var hasPendingDisplayedItemsRecompute = false
    private var pendingSortVersionBump = false
    private(set) var displayedItemsRecomputeCount = 0

    init(scanModel: ScanViewModel) {
        self.scanModel = scanModel

        // Forward scan state changes needed by Browse progress and controls,
        // but only an item revision should rebuild the sorted media list.
        scanModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        scanModel.$itemsRevision
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.requestDisplayedItemsRecompute()
            }
            .store(in: &cancellables)

        recomputeDisplayedItems()
    }

    // MARK: - Displayed items computation

    private func requestDisplayedItemsRecompute(bumpSortVersion: Bool = false) {
        if isBatchingDisplayedItemsRecompute {
            hasPendingDisplayedItemsRecompute = true
            pendingSortVersionBump = pendingSortVersionBump || bumpSortVersion
            return
        }
        recomputeDisplayedItems(bumpSortVersion: bumpSortVersion)
    }

    private func batchDisplayedItemsChanges(_ changes: () -> Void) {
        isBatchingDisplayedItemsRecompute = true
        changes()
        isBatchingDisplayedItemsRecompute = false
        guard hasPendingDisplayedItemsRecompute else { return }
        let bumpSortVersion = pendingSortVersionBump
        hasPendingDisplayedItemsRecompute = false
        pendingSortVersionBump = false
        recomputeDisplayedItems(bumpSortVersion: bumpSortVersion)
    }

    private func recomputeDisplayedItems(bumpSortVersion: Bool = false) {
        displayedItemsRecomputeCount &+= 1
        let previousDisplayedItems = displayedItems
        let previousSelectedIDs = selectedMediaIDs
        let previousPrimarySelectionID = effectivePrimarySelectionID ?? primarySelectionID
        var items = scanModel.items

        // Media type filter
        switch mediaFilter {
        case .all: break
        case .images: items = items.filter { $0.kind == .image }
        case .videos: items = items.filter { $0.kind == .video }
        }

        let searchQuery = normalizedSearchText
        if !searchQuery.isEmpty {
            items = items.filter { item in
                item.filename.localizedCaseInsensitiveContains(searchQuery)
                    || item.url.path.localizedCaseInsensitiveContains(searchQuery)
            }
        }

        // Resolution filter
        if let threshold = resolutionThreshold {
            items = items.filter { item in
                let shortEdge = min(item.width, item.height)
                switch resolutionComparator {
                case .lessThan:    return shortEdge < threshold
                case .greaterThan: return shortEdge > threshold
                }
            }
        }

        // Sort
        items.sort(by: isOrderedBefore)

        let orderedIDsChanged = previousDisplayedItems.map(\.id) != items.map(\.id)
        if orderedIDsChanged {
            displayedItems = items
        }
        pruneSelection(
            previousDisplayedItems: previousDisplayedItems,
            previousSelectedIDs: previousSelectedIDs,
            previousPrimarySelectionID: previousPrimarySelectionID
        )
        if bumpSortVersion && orderedIDsChanged {
            sortVersion &+= 1
        }
    }

    private func isOrderedBefore(_ first: MediaItem, _ second: MediaItem) -> Bool {
        let primaryComparison: ComparisonResult
        switch sortField {
        case .name:
            primaryComparison = first.filename.localizedStandardCompare(second.filename)
        case .fileSize:
            primaryComparison = compare(first.fileSize, second.fileSize)
        case .modifiedTime:
            primaryComparison = compare(first.modifiedAt ?? .distantPast, second.modifiedAt ?? .distantPast)
        case .resolutionWidth:
            primaryComparison = compare(first.width, second.width)
        case .resolutionHeight:
            primaryComparison = compare(first.height, second.height)
        }

        if primaryComparison != .orderedSame {
            return sortAscending
                ? primaryComparison == .orderedAscending
                : primaryComparison == .orderedDescending
        }

        let pathComparison = first.url.standardizedFileURL.path
            .localizedStandardCompare(second.url.standardizedFileURL.path)
        if pathComparison != .orderedSame {
            return pathComparison == .orderedAscending
        }
        return first.id.uuidString < second.id.uuidString
    }

    private func compare<Value: Comparable>(_ first: Value, _ second: Value) -> ComparisonResult {
        if first < second { return .orderedAscending }
        if first > second { return .orderedDescending }
        return .orderedSame
    }

    /// The primary selected item from the browse table.
    var selectedMedia: MediaItem? {
        guard let id = effectivePrimarySelectionID else { return nil }
        return scanModel.items.first { $0.id == id }
    }

    var selectedMediaList: [MediaItem] {
        displayedItems.filter { selectedMediaIDs.contains($0.id) }
    }

    var hasMultipleSelection: Bool {
        selectedMediaIDs.count > 1
    }

    var primarySelectedID: UUID? {
        effectivePrimarySelectionID
    }

    private var effectivePrimarySelectionID: UUID? {
        if let primarySelectionID, selectedMediaIDs.contains(primarySelectionID) {
            return primarySelectionID
        }
        return displayedItems.first { selectedMediaIDs.contains($0.id) }?.id
    }

    // MARK: - Resolution Threshold

    /// The effective resolution threshold in pixels (from preset or manual input).
    private var resolutionThreshold: Int? {
        if let preset = selectedResolutionPreset {
            return preset.shortEdge
        }
        let w = Int(manualWidth)
        let h = Int(manualHeight)
        if let w, let h, w > 0, h > 0 {
            return min(w, h)
        }
        if let w, w > 0 { return w }
        if let h, h > 0 { return h }
        return nil
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Actions

    func selectMedia(_ id: UUID?) {
        guard let id else {
            deselectAll()
            return
        }
        selectedMediaIDs = [id]
        primarySelectionID = id
        selectionAnchorID = id
    }

    func replaceSelection(with ids: Set<UUID>) {
        let changedID = changedSelectionID(from: ids)
        selectedMediaIDs = ids
        if let changedID {
            primarySelectionID = changedID
            selectionAnchorID = changedID
        }
        pruneSelection()
    }

    func toggleMedia(_ id: UUID) {
        if selectedMediaIDs.contains(id) {
            selectedMediaIDs.remove(id)
        } else {
            selectedMediaIDs.insert(id)
            primarySelectionID = id
            selectionAnchorID = id
        }
        pruneSelection()
    }

    func extendSelection(to id: UUID) {
        let anchor = selectionAnchorID ?? primarySelectionID ?? id
        guard let anchorIndex = displayedItems.firstIndex(where: { $0.id == anchor }),
              let targetIndex = displayedItems.firstIndex(where: { $0.id == id }) else {
            selectMedia(id)
            return
        }
        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedMediaIDs = Set(displayedItems[range].map(\.id))
        primarySelectionID = id
    }

    /// Keyboard arrow navigation. Moves the primary selection by `offset`
    /// rows (−1 up, +1 down), clamped to the displayed list bounds. When
    /// `extend` is true (Shift held), the selection grows/shrinks from the
    /// anchor toward the new row, mirroring a click-Shift-click range.
    /// If nothing is selected, the first item becomes the selection.
    func moveSelection(by offset: Int, extend: Bool) {
        guard !displayedItems.isEmpty else { return }
        if extend {
            moveExtendSelection(by: offset)
        } else {
            moveReplaceSelection(by: offset)
        }
    }

    private func moveReplaceSelection(by offset: Int) {
        let currentIndex = primarySelectedID.flatMap { id in
            displayedItems.firstIndex(where: { $0.id == id })
        } ?? -1
        // When nothing is selected, pressing Down selects the first row;
        // pressing Up from nothing selects the last row - matches NSTableView.
        let baseIndex = currentIndex < 0 ? (offset > 0 ? -1 : displayedItems.count) : currentIndex
        let targetIndex = min(max(baseIndex + offset, 0), displayedItems.count - 1)
        guard targetIndex != currentIndex else { return }
        selectMedia(displayedItems[targetIndex].id)
    }

    private func moveExtendSelection(by offset: Int) {
        let anchorID = selectionAnchorID ?? primarySelectionID ?? displayedItems.first?.id
        guard let anchorID,
              let anchorIndex = displayedItems.firstIndex(where: { $0.id == anchorID })
        else { return }
        let current = primarySelectedID.flatMap { id in
            displayedItems.firstIndex(where: { $0.id == id })
        } ?? anchorIndex
        let targetIndex = min(max(current + offset, 0), displayedItems.count - 1)
        guard targetIndex != current else { return }
        let targetID = displayedItems[targetIndex].id
        extendSelection(to: targetID)
    }

    func selectAllDisplayed() {
        selectedMediaIDs = Set(displayedItems.map(\.id))
        if primarySelectionID == nil || !selectedMediaIDs.contains(primarySelectionID!) {
            primarySelectionID = displayedItems.first?.id
        }
        selectionAnchorID = primarySelectionID
    }

    func deselectAll() {
        selectedMediaIDs = []
        primarySelectionID = nil
        selectionAnchorID = nil
    }

    func toggleBatchSelectionMode() {
        isBatchSelectionMode.toggle()
    }

    private func changedSelectionID(from newSelection: Set<UUID>) -> UUID? {
        let added = newSelection.subtracting(selectedMediaIDs)
        if let id = displayedItems.first(where: { added.contains($0.id) })?.id { return id }
        let removed = selectedMediaIDs.subtracting(newSelection)
        if let id = displayedItems.first(where: { removed.contains($0.id) })?.id { return id }
        return newSelection.first
    }

    private func pruneSelection(
        previousDisplayedItems: [MediaItem] = [],
        previousSelectedIDs: Set<UUID>? = nil,
        previousPrimarySelectionID: UUID? = nil
    ) {
        let displayedIDs = Set(displayedItems.map(\.id))
        let selectedIDsBeforePruning = selectedMediaIDs
        selectedMediaIDs.formIntersection(displayedIDs)
        if selectedMediaIDs.isEmpty,
           let fallbackID = fallbackSelectionID(
               previousDisplayedItems: previousDisplayedItems,
               previousSelectedIDs: previousSelectedIDs ?? selectedIDsBeforePruning,
               previousPrimarySelectionID: previousPrimarySelectionID,
               displayedIDs: displayedIDs
           ) {
            selectedMediaIDs = [fallbackID]
            primarySelectionID = fallbackID
            selectionAnchorID = fallbackID
            return
        }
        if let primarySelectionID, !selectedMediaIDs.contains(primarySelectionID) {
            self.primarySelectionID = displayedItems.first { selectedMediaIDs.contains($0.id) }?.id
        }
        if let selectionAnchorID, !displayedIDs.contains(selectionAnchorID) {
            self.selectionAnchorID = primarySelectionID
        }
        if selectedMediaIDs.isEmpty {
            primarySelectionID = nil
            selectionAnchorID = nil
        }
    }

    private func fallbackSelectionID(
        previousDisplayedItems: [MediaItem],
        previousSelectedIDs: Set<UUID>,
        previousPrimarySelectionID: UUID?,
        displayedIDs: Set<UUID>
    ) -> UUID? {
        guard !previousSelectedIDs.isEmpty, !displayedItems.isEmpty else { return nil }
        let removedSelectedIDs = previousSelectedIDs.subtracting(displayedIDs)
        guard !removedSelectedIDs.isEmpty else { return nil }

        let removedIndex: Int?
        if let previousPrimarySelectionID,
           removedSelectedIDs.contains(previousPrimarySelectionID),
           let primaryIndex = previousDisplayedItems.firstIndex(where: { $0.id == previousPrimarySelectionID }) {
            removedIndex = primaryIndex
        } else {
            removedIndex = previousDisplayedItems.firstIndex { removedSelectedIDs.contains($0.id) }
        }

        guard let removedIndex else { return displayedItems.first?.id }

        if let nextID = previousDisplayedItems
            .dropFirst(removedIndex + 1)
            .first(where: { displayedIDs.contains($0.id) })?
            .id {
            return nextID
        }

        return previousDisplayedItems
            .prefix(removedIndex)
            .reversed()
            .first(where: { displayedIDs.contains($0.id) })?
            .id ?? displayedItems.first?.id
    }

    func toggleSort(field: SortField) {
        if sortField == field {
            sortAscending.toggle()
        } else {
            setSort(field: field, ascending: true)
        }
    }

    func setSort(field: SortField, ascending: Bool) {
        batchDisplayedItemsChanges {
            sortField = field
            sortAscending = ascending
        }
    }

    /// Reset sort back to name/ascending (used by the resolution sort popover's Clear button).
    func clearResolutionSort() {
        setSort(field: .name, ascending: true)
    }

    func setResolutionPreset(_ preset: ResolutionPreset) {
        batchDisplayedItemsChanges {
            selectedResolutionPreset = preset
            manualWidth = ""
            manualHeight = ""
        }
    }

    /// User edits switch to manual filtering. Programmatic field clearing when
    /// choosing a preset must not be interpreted as a new manual edit.
    func setManualWidth(_ value: String) {
        batchDisplayedItemsChanges {
            selectedResolutionPreset = nil
            manualWidth = value
        }
    }

    func setManualHeight(_ value: String) {
        batchDisplayedItemsChanges {
            selectedResolutionPreset = nil
            manualHeight = value
        }
    }

    func clearResolutionFilter() {
        batchDisplayedItemsChanges {
            selectedResolutionPreset = nil
            manualWidth = ""
            manualHeight = ""
        }
    }

    var hasActiveFilter: Bool {
        mediaFilter != .all || resolutionThreshold != nil || !normalizedSearchText.isEmpty
    }
}
