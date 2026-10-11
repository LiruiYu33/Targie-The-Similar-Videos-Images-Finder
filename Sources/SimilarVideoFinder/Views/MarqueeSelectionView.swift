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

// MARK: - Item frames

/// Where each selectable item currently is. A plain reference rather than
/// SwiftUI state or a preference: frames change on every animation frame
/// (cards cascade in, lists scroll), and routing them through the view graph
/// cost about a third of each group switch even though they are only read
/// once a drag starts.
@MainActor
final class MarqueeFrameRegistry {
    var frames: [UUID: CGRect] = [:]

    /// Forgets items that are no longer listed. Frames of items that are
    /// listed but not currently laid out (scrolled away in a lazy stack) are
    /// kept so they stay selectable during an auto-scroll.
    func retain(only ids: [UUID]) {
        let current = Set(ids)
        frames = frames.filter { current.contains($0.key) }
    }
}

private struct MarqueeFrameRegistryKey: EnvironmentKey {
    static let defaultValue: MarqueeFrameRegistry? = nil
}

private extension EnvironmentValues {
    var marqueeFrameRegistry: MarqueeFrameRegistry? {
        get { self[MarqueeFrameRegistryKey.self] }
        set { self[MarqueeFrameRegistryKey.self] = newValue }
    }
}

private struct MarqueeItemModifier: ViewModifier {
    let id: UUID
    @Environment(\.marqueeFrameRegistry) private var registry

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(MarqueeSelectionModifier.coordinateSpace))
        } action: { frame in
            registry?.frames[id] = frame
        }
    }
}

extension View {
    /// Registers this view as something a marquee drag can select.
    func marqueeItem(_ id: UUID) -> some View {
        modifier(MarqueeItemModifier(id: id))
    }

    /// Finder-style rubber-band selection over the scroll content this is
    /// applied to. `onChange` receives the IDs currently under the marquee;
    /// the caller combines them with the selection captured in `onBegin`.
    func marqueeSelection(
        isEnabled: Bool = true,
        resetKey: [UUID],
        onBegin: @escaping (MarqueeSelectionMode) -> Void,
        onChange: @escaping (Set<UUID>) -> Void,
        onEnd: @escaping () -> Void = {}
    ) -> some View {
        modifier(MarqueeSelectionModifier(
            isEnabled: isEnabled,
            resetKey: resetKey,
            onBegin: onBegin,
            onChange: onChange,
            onEnd: onEnd
        ))
    }
}

// MARK: - Container

struct MarqueeSelectionModifier: ViewModifier {
    static let coordinateSpace = "marqueeSelection"

    let isEnabled: Bool
    let resetKey: [UUID]
    let onBegin: (MarqueeSelectionMode) -> Void
    let onChange: (Set<UUID>) -> Void
    let onEnd: () -> Void

    @State private var registry = MarqueeFrameRegistry()
    @State private var origin: CGPoint?
    @State private var pointer: CGPoint = .zero
    @State private var lastHits: Set<UUID> = []
    @State private var autoScroller = MarqueeAutoScroller()

    func body(content: Content) -> some View {
        content
            .background(EnclosingScrollViewReader { autoScroller.scrollView = $0 })
            .coordinateSpace(name: Self.coordinateSpace)
            .environment(\.marqueeFrameRegistry, registry)
            .onChange(of: resetKey) { _, ids in registry.retain(only: ids) }
            .overlay(alignment: .topLeading) {
                if let origin {
                    let rect = MarqueeGeometry.rect(from: origin, to: pointer)
                    MarqueeRectangle()
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .simultaneousGesture(dragGesture, including: isEnabled ? .all : .subviews)
            .onDisappear { autoScroller.stop() }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                if origin == nil {
                    origin = value.startLocation
                    lastHits = []
                    onBegin(MarqueeSelectionMode(modifierFlags: NSEvent.modifierFlags))
                }
                pointer = value.location
                publishHits()
                autoScroller.track { delta in
                    pointer.y += delta
                    publishHits()
                }
            }
            .onEnded { _ in
                autoScroller.stop()
                withAnimation(Motion.quick) { origin = nil }
                onEnd()
            }
    }

    private func publishHits() {
        guard let origin else { return }
        let hits = MarqueeGeometry.hits(in: MarqueeGeometry.rect(from: origin, to: pointer), frames: registry.frames)
        guard hits != lastHits else { return }
        lastHits = hits
        onChange(hits)
    }
}

private struct MarqueeRectangle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.accentColor.opacity(0.14))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 1)
            }
            .shadow(color: Color.accentColor.opacity(0.25), radius: 6)
    }
}

// MARK: - Auto-scroll

/// Scrolls the enclosing NSScrollView while the pointer rests near its top or
/// bottom edge during a marquee drag, reporting how far the content moved so
/// the marquee can keep growing even though the mouse itself stays still.
@MainActor
final class MarqueeAutoScroller {
    weak var scrollView: NSScrollView?
    private var timer: Timer?
    private var onScroll: ((CGFloat) -> Void)?

    func track(onScroll: @escaping (CGFloat) -> Void) {
        self.onScroll = onScroll
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        onScroll = nil
    }

    private func tick() {
        guard let scrollView, let window = scrollView.window, let documentView = scrollView.documentView else { return }
        let clipView = scrollView.contentView
        let pointer = clipView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let insets = clipView.contentInsets
        let visible = clipView.bounds
        // Distances measured in the clip view, whose y grows downward when flipped.
        let flipped = clipView.isFlipped
        let topEdge = flipped ? visible.minY + insets.top : visible.maxY - insets.top
        let bottomEdge = flipped ? visible.maxY - insets.bottom : visible.minY + insets.bottom
        let distanceToTop = flipped ? pointer.y - topEdge : topEdge - pointer.y
        let distanceToBottom = flipped ? bottomEdge - pointer.y : pointer.y - bottomEdge

        let down = MarqueeGeometry.autoScrollSpeed(distanceToEdge: distanceToBottom)
        let up = MarqueeGeometry.autoScrollSpeed(distanceToEdge: distanceToTop)
        let contentDelta = down > 0 ? down : (up > 0 ? -up : 0)
        guard contentDelta != 0 else { return }

        let documentHeight = documentView.frame.height
        let minOrigin = -insets.top
        let maxOrigin = max(minOrigin, documentHeight - visible.height + insets.bottom)
        let oldY = visible.origin.y
        let proposed = documentView.isFlipped ? oldY + contentDelta : oldY - contentDelta
        let newY = min(max(proposed, minOrigin), maxOrigin)
        guard newY != oldY else { return }
        clipView.scroll(to: NSPoint(x: visible.origin.x, y: newY))
        scrollView.reflectScrolledClipView(clipView)
        let applied = documentView.isFlipped ? newY - oldY : oldY - newY
        onScroll?(applied)
    }
}

private struct EnclosingScrollViewReader: NSViewRepresentable {
    let onResolve: (NSScrollView?) -> Void

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(view.enclosingScrollView) }
    }
}
