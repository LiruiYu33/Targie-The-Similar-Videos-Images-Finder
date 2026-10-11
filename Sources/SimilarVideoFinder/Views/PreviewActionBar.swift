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

import SwiftUI

/// One button under a media preview.
struct PreviewAction {
    let kind: PreviewActionKind
    let title: String
    let systemImage: String
    var isDestructive = false
    let perform: () -> Void
}

/// Preview action buttons laid out as a tidy block: opening the file gets a
/// full-width row; the remaining actions share the next row in equal widths,
/// or stack at full width when their labels do not fit side by side.
struct PreviewActionBar: View {
    let actions: [PreviewAction]

    var body: some View {
        let rows = PreviewActionArrangement.rows(for: actions.map(\.kind))
        VStack(spacing: 8) {
            if let lead = rows.lead, let action = action(for: lead) {
                button(action)
            }
            let shared = rows.shared.compactMap(action(for:))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(shared, id: \.kind) { button($0) }
                }
                VStack(spacing: 8) {
                    ForEach(shared, id: \.kind) { button($0) }
                }
            }
        }
        .controlSize(.large)
    }

    private func action(for kind: PreviewActionKind) -> PreviewAction? {
        actions.first { $0.kind == kind }
    }

    private func button(_ action: PreviewAction) -> some View {
        Button(role: action.isDestructive ? .destructive : nil, action: action.perform) {
            Label(action.title, systemImage: action.systemImage)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity)
                .foregroundStyle(action.isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.bordered)
    }
}
