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

    struct ResolutionPreset: Identifiable, Sendable {
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
    /// Explicitly published so the List reliably reorders when sort/filter changes.
    @Published var displayedItems: [MediaItem] = []

    /// Incremented on every recompute so SwiftUI List reorders rows
    /// when the same items appear in a different sort order.
    @Published var sortVersion: Int = 0

    @Published var sortField: SortField = .name { didSet { recomputeDisplayedItems(bumpSortVersion: true) } }
    @Published var sortAscending: Bool = true  { didSet { recomputeDisplayedItems(bumpSortVersion: true) } }
    @Published var isResolutionSortPresented: Bool = false
    @Published var mediaFilter: MediaFilter = .all { didSet { recomputeDisplayedItems() } }
    @Published var resolutionComparator: ResolutionComparator = .lessThan { didSet { recomputeDisplayedItems() } }
    @Published var selectedResolutionPreset: ResolutionPreset? { didSet { recomputeDisplayedItems() } }
    @Published var manualWidth: String = "" { didSet { recomputeDisplayedItems() } }
    @Published var manualHeight: String = "" { didSet { recomputeDisplayedItems() } }
    @Published var searchText: String = "" { didSet { recomputeDisplayedItems() } }
    @Published var selectedMediaIDs: Set<UUID> = []
    @Published var primarySelectionID: UUID?
    @Published var selectionAnchorID: UUID?
    @Published var isBatchSelectionMode = false
    @Published var isFilterPresented: Bool = false

    let scanModel: ScanViewModel
    private var cancellables = Set<AnyCancellable>()

    init(scanModel: ScanViewModel) {
        self.scanModel = scanModel

        // Forward scanModel changes so views observing browseModel
        // re-render when scanModel's @Published properties change
        // (e.g. progress, allItems via computed `items`).
        scanModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
                self.recomputeDisplayedItems()
            }
            .store(in: &cancellables)

        recomputeDisplayedItems()
    }

    // MARK: - Displayed items computation

    private func recomputeDisplayedItems(bumpSortVersion: Bool = false) {
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
        items.sort { a, b in
            let result: Bool
            switch sortField {
            case .name:
                result = a.filename.localizedStandardCompare(b.filename) == .orderedAscending
            case .fileSize:
                result = a.fileSize < b.fileSize
            case .modifiedTime:
                let d1 = a.modifiedAt ?? .distantPast
                let d2 = b.modifiedAt ?? .distantPast
                result = d1 < d2
            case .resolutionWidth:
                result = a.width < b.width
            case .resolutionHeight:
                result = a.height < b.height
            }
            return sortAscending ? result : !result
        }

        displayedItems = items
        pruneSelection(
            previousDisplayedItems: previousDisplayedItems,
            previousSelectedIDs: previousSelectedIDs,
            previousPrimarySelectionID: previousPrimarySelectionID
        )
        if bumpSortVersion {
            sortVersion &+= 1
        }
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
            sortField = field
            sortAscending = true
        }
    }

    /// Reset sort back to name/ascending (used by the resolution sort popover's Clear button).
    func clearResolutionSort() {
        sortField = .name
        sortAscending = true
    }

    func clearResolutionFilter() {
        selectedResolutionPreset = nil
        manualWidth = ""
        manualHeight = ""
    }

    var hasActiveFilter: Bool {
        mediaFilter != .all || resolutionThreshold != nil || !normalizedSearchText.isEmpty
    }
}
