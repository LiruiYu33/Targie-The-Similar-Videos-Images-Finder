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
import SwiftUI

struct VideoCardView: View {
    let video: MediaItem
    let score: Double
    let evidence: Set<SimilarityEvidence>
    let language: AppLanguage
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black.opacity(0.88))
                if let data = video.thumbnailData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(alignment: .firstTextBaseline) {
                Text(video.filename)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(DisplayFormatters.percent(score))
                    .font(.caption.bold())
                    .foregroundStyle(score >= 0.9 ? .green : .secondary)
            }
            Text("\(DisplayFormatters.fileSize(video.fileSize)) · \(DisplayFormatters.duration(video.duration ?? 0, language: language)) · \(video.resolution(language: language))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(video.url.deletingLastPathComponent().path)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            if !evidence.isEmpty {
                Text(evidence.map { L10n.evidence($0, language) }.sorted().joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
