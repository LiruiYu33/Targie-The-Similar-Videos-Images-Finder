// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import AppKit
import SwiftUI

@MainActor
final class MediaThumbnailLoader: ObservableObject {
    @Published private(set) var loadedItemID: UUID?
    @Published private(set) var loadedImage: NSImage?

    private let cache: MediaThumbnailImageCache
    private var requestedItemID: UUID?

    init(cache: MediaThumbnailImageCache = .shared) {
        self.cache = cache
    }

    func image(for item: MediaItem) -> NSImage? {
        if loadedItemID == item.id {
            return loadedImage
        }
        return cache.image(for: item)
    }

    func load(_ item: MediaItem) async {
        requestedItemID = item.id
        loadedItemID = item.id
        loadedImage = cache.image(for: item)
        guard loadedImage == nil else { return }

        let loadedImage = await cache.image(
            for: item,
            repairingMissingVideoThumbnail: true
        )
        guard !Task.isCancelled, requestedItemID == item.id else { return }
        loadedItemID = item.id
        self.loadedImage = loadedImage
    }
}

struct MediaThumbnailView: View {
    let item: MediaItem
    let placeholderSystemImage: String
    var placeholderFont: Font = .largeTitle
    var placeholderColor: Color = .secondary

    @StateObject private var loader = MediaThumbnailLoader()

    var body: some View {
        Group {
            if let image = loader.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: placeholderSystemImage)
                    .font(placeholderFont)
                    .foregroundStyle(placeholderColor)
            }
        }
        .task(id: item.id) {
            await loader.load(item)
        }
    }
}
