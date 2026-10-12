// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import Observation
import SwiftUI

@MainActor
@Observable
final class BrowseSessionCoordinator {
    private(set) var browseModel: BrowseViewModel?

    func prepareIfPossible(scanModel: ScanViewModel) {
        guard scanModel.hasDiscoveredItems else { return }
        _ = model(for: scanModel)
    }

    func model(for scanModel: ScanViewModel) -> BrowseViewModel {
        if let browseModel, browseModel.scanModel === scanModel {
            return browseModel
        }
        let browseModel = BrowseViewModel(scanModel: scanModel)
        self.browseModel = browseModel
        return browseModel
    }

    func leaveBrowseMode() {
        // Keep the prepared model alive so returning to Browse doesn't rebuild
        // the large display list and its cached sort/filter state.
    }
}
