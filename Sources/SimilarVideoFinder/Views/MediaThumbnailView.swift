// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import AppKit
import SwiftUI

struct MediaThumbnailView: View {
    let item: MediaItem
    let placeholderSystemImage: String
    var placeholderFont: Font = .largeTitle
    var placeholderColor: Color = .secondary

    @State private var repairedImage: NSImage?

    var body: some View {
        Group {
            if let image = repairedImage ?? MediaThumbnailImageCache.shared.image(for: item) {
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
            await repairMissingVideoThumbnail()
        }
        .onChange(of: item.id) { _, _ in
            repairedImage = nil
        }
    }

    @MainActor
    private func repairMissingVideoThumbnail() async {
        guard repairedImage == nil else { return }
        if let image = MediaThumbnailImageCache.shared.image(for: item) {
            repairedImage = image
            return
        }
        repairedImage = await MediaThumbnailImageCache.shared.image(
            for: item,
            repairingMissingVideoThumbnail: true
        )
    }
}
