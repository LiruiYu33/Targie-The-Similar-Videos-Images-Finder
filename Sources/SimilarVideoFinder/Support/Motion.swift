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

/// Shared motion so every transition in the app feels the same. Springs give
/// panels and cards a little momentum; everything still settles well under
/// half a second so motion never slows anyone down.
enum Motion {
    /// Panels, mode switches and content swaps.
    static let standard: Animation = .spring(response: 0.42, dampingFraction: 0.8)
    /// Selection, check and other small state feedback.
    static let quick: Animation = .snappy(duration: 0.22)
    /// Badges and highlights that should pop.
    static let bouncy: Animation = .spring(response: 0.34, dampingFraction: 0.6)
    /// Thumbnails and previews appearing after an async load.
    static let fade: Animation = .easeOut(duration: 0.25)

    /// Delay between cards when a group cascades in. Only the first screenful
    /// staggers; cards created later by scrolling appear without waiting.
    static func cascadeDelay(index: Int) -> Double {
        index < 12 ? Double(index) * 0.035 : 0
    }

    /// Slides in from `edge`, or only crossfades when Reduce Motion is on.
    static func slide(from edge: Edge, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}

extension View {
    /// Rises and fades in shortly after appearing, `index` steps behind its
    /// predecessor. Reduce Motion keeps only the fade.
    /// Pass `isEnabled: false` to show the view immediately, e.g. when a
    /// screen is rebuilt rather than newly navigated to.
    func cascadeIn(index: Int, isEnabled: Bool = true, reduceMotion: Bool) -> some View {
        modifier(CascadeInModifier(index: index, reduceMotion: reduceMotion, isShown: !isEnabled))
    }
}

private struct CascadeInModifier: ViewModifier {
    let index: Int
    let reduceMotion: Bool
    @State private var isShown: Bool

    init(index: Int, reduceMotion: Bool, isShown: Bool) {
        self.index = index
        self.reduceMotion = reduceMotion
        _isShown = State(initialValue: isShown)
    }

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .scaleEffect(isShown || reduceMotion ? 1 : 0.94)
            .offset(y: isShown || reduceMotion ? 0 : 18)
            // No blur here: a filter stays attached even at radius 0 and makes
            // every later change to the card re-render it offscreen.
            .onAppear {
                guard !isShown else { return }
                withAnimation(Motion.standard.delay(Motion.cascadeDelay(index: index))) {
                    isShown = true
                }
            }
    }
}
