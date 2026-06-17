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

/// A toolbar button rendered as an SF Symbol icon stacked above its title.
/// Uses a custom hover/press pill background sized to the actual content,
/// since macOS's default toolbar pill is sized for single-line content and
/// crops a vertical icon+text layout.
struct ToolbarLabeledButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ToolbarLabelContent(title: title, systemImage: systemImage)
        }
        .buttonStyle(ToolbarPillStyle())
    }
}

/// Same icon-over-title layout, but reveals a popover of `content` on tap.
/// Works around `Menu` flattening custom labels into a single horizontal row.
struct ToolbarLabeledPopover<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            ToolbarLabelContent(title: title, systemImage: systemImage)
        }
        .buttonStyle(ToolbarPillStyle())
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            content()
                .padding(.vertical, 4)
        }
    }
}

// MARK: - Internal

struct ToolbarLabelContent: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .regular))
            Text(title)
                .font(.system(size: 10))
                .lineLimit(1)
        }
        .frame(minWidth: 44)
    }
}

/// Custom button style that draws a rounded hover/press pill correctly sized
/// to the content (icon + title), with macOS-feeling tinting.
struct ToolbarPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ToolbarPillBody(configuration: configuration)
    }
}

private struct ToolbarPillBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor)
            )
            .opacity(isEnabled ? 1.0 : 0.4)
            .contentShape(Capsule(style: .continuous))
            .onHover { hovering in
                if isEnabled { isHovered = hovering }
            }
    }

    private var backgroundColor: Color {
        if !isEnabled { return .clear }
        if configuration.isPressed { return Color.secondary.opacity(0.30) }
        if isHovered                { return Color.secondary.opacity(0.15) }
        return .clear
    }
}
