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

    @Published var sortField: SortField = .name
    @Published var sortAscending: Bool = true
    @Published var mediaFilter: MediaFilter = .all
    @Published var resolutionComparator: ResolutionComparator = .lessThan
    @Published var selectedResolutionPreset: ResolutionPreset?
    @Published var manualWidth: String = ""
    @Published var manualHeight: String = ""
    @Published var selectedMediaID: UUID?
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
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Computed

    /// Filtered and sorted items ready for display.
    var displayedItems: [MediaItem] {
        var items = scanModel.items

        // Media type filter
        switch mediaFilter {
        case .all: break
        case .images: items = items.filter { $0.kind == .image }
        case .videos: items = items.filter { $0.kind == .video }
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

        return items
    }

    /// The selected item from the browse table.
    var selectedMedia: MediaItem? {
        scanModel.items.first { $0.id == selectedMediaID }
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

    // MARK: - Table sort order (KeyPathComparator binding)

    var sortComparators: [KeyPathComparator<MediaItem>] {
        let order: SortOrder = sortAscending ? .forward : .reverse
        switch sortField {
        case .name:         return [KeyPathComparator(\.filename, order: order)]
        case .fileSize:     return [KeyPathComparator(\.fileSize, order: order)]
        case .modifiedTime: return [KeyPathComparator(\.modifiedAt, order: order)]
        case .resolutionWidth:  return [KeyPathComparator(\.width, order: order)]
        case .resolutionHeight: return [KeyPathComparator(\.height, order: order)]
        }
    }

    func updateSort(from comparators: [KeyPathComparator<MediaItem>]) {
        guard let comp = comparators.first else { return }
        let kp = comp.keyPath
        if kp == \.filename      { sortField = .name }
        else if kp == \.fileSize { sortField = .fileSize }
        else if kp == \.modifiedAt { sortField = .modifiedTime }
        else if kp == \.width    { sortField = .resolutionWidth }
        else if kp == \.height   { sortField = .resolutionHeight }
        else { return }
        sortAscending = comp.order == .forward
    }

    // MARK: - Actions

    func selectMedia(_ id: UUID?) {
        selectedMediaID = id
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
        mediaFilter != .all || resolutionThreshold != nil
    }
}
