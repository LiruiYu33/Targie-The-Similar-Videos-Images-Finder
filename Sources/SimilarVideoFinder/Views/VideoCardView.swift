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

/// Equatable so SwiftUI can skip unchanged cards: the `toggleChecked`
/// closure would otherwise make every card look changed, re-rendering the
/// whole grid on each selection change (noticeable during a marquee drag).
struct VideoCardView: View, Equatable {
    let video: MediaItem
    let score: Double
    let evidence: Set<SimilarityEvidence>
    let language: AppLanguage
    let isSelected: Bool
    let isChecked: Bool
    var previewHeight: CGFloat = 320
    let toggleChecked: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    nonisolated static func == (lhs: VideoCardView, rhs: VideoCardView) -> Bool {
        lhs.video == rhs.video
            && lhs.score == rhs.score
            && lhs.evidence == rhs.evidence
            && lhs.language == rhs.language
            && lhs.isSelected == rhs.isSelected
            && lhs.isChecked == rhs.isChecked
            && lhs.previewHeight == rhs.previewHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { isChecked }, set: { _ in toggleChecked() })) { EmptyView() }
                .toggleStyle(.checkbox)
                .accessibilityLabel(video.filename)
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(video.kind == .image ? Color(nsColor: .underPageBackgroundColor) : .black.opacity(0.88))
                MediaThumbnailView(
                    item: video,
                    placeholderSystemImage: video.kind == .video ? "film" : "photo",
                    placeholderColor: .white.opacity(0.7)
                )
            }
            .frame(height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                if isChecked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .padding(8)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.3).combined(with: .opacity))
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(video.filename)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(DisplayFormatters.percent(score))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .help(L10n.similarityScoreHelp(language))
            }
            Text(video.duration.map { "\(DisplayFormatters.fileSize(video.fileSize)) · \(DisplayFormatters.duration($0, language: language)) · \(video.resolution(language: language))" } ?? "\(DisplayFormatters.fileSize(video.fileSize)) · \(video.resolution(language: language))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Label(video.url.deletingLastPathComponent().lastPathComponent, systemImage: "folder")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(video.url.deletingLastPathComponent().path)

            if !evidence.isEmpty {
                Text(evidence.map { L10n.evidence($0, language) }.sorted().joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background {
            // The shadow sits on this opaque shape rather than on the whole
            // card: shadowing the card makes Core Animation render its image
            // and text offscreen every frame, which stalled marquee drags.
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(isChecked ? 0.08 : 0))
                }
                // Hover lifts the card; the focused card glows in the accent colour.
                .shadow(
                    color: isSelected ? Color.accentColor.opacity(0.35) : .black.opacity(isHovered ? 0.18 : 0.06),
                    radius: isSelected ? 12 : (isHovered ? 14 : 4),
                    y: isHovered ? 6 : 2
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .scaleEffect(isHovered && !reduceMotion ? 1.015 : 1)
        .onHover { hovering in
            // No lift while a button is held: a marquee drag passes over many
            // cards and bobbing them would also move their hit frames.
            let isDragging = NSEvent.pressedMouseButtons != 0
            withAnimation(Motion.quick) { isHovered = hovering && !isDragging }
        }
        .animation(Motion.quick, value: isSelected)
        .animation(Motion.bouncy, value: isChecked)
    }

}
