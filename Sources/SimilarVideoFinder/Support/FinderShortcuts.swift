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

/// Finder keyboard shortcuts the app mirrors.
enum FinderShortcut: Equatable {
    /// ⌘F — focus the search field.
    case find
    /// ⌘⌫ — move the selection to the Trash (through the delete prompt).
    case moveToTrash

    private static let deleteKeyCode: UInt16 = 51

    /// Returns the shortcut for a key event, or nil to let the event through.
    /// While text is being edited ⌘⌫ keeps its text meaning (delete to line
    /// start), exactly as it does in Finder's rename field.
    static func match(
        keyCode: UInt16,
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags,
        isEditingText: Bool
    ) -> FinderShortcut? {
        let modifiers = modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard modifiers == .command else { return nil }
        if charactersIgnoringModifiers?.lowercased() == "f" { return .find }
        if keyCode == deleteKeyCode, !isEditingText { return .moveToTrash }
        return nil
    }
}

/// Handles `FinderShortcut`s for the window this view lives in. Events in
/// other windows and sheets (such as the delete prompt) are left alone.
struct FinderShortcutMonitor: NSViewRepresentable {
    /// Whether ⌘F focuses the toolbar search field of this window.
    var focusesToolbarSearch = false
    let onMoveToTrash: () -> Void

    func makeNSView(context: Context) -> MonitoringView {
        let view = MonitoringView()
        view.handler = handle
        return view
    }

    func updateNSView(_ view: MonitoringView, context: Context) {
        view.handler = handle
    }

    static func dismantleNSView(_ view: MonitoringView, coordinator: ()) {
        view.stopMonitoring()
    }

    private func handle(_ shortcut: FinderShortcut, in window: NSWindow) -> Bool {
        switch shortcut {
        case .find:
            guard focusesToolbarSearch else { return false }
            ToolbarSearch.focus(in: window)
            return true
        case .moveToTrash:
            onMoveToTrash()
            return true
        }
    }

    final class MonitoringView: NSView {
        var handler: ((FinderShortcut, NSWindow) -> Bool)?
        private let eventMonitorStore = EventMonitorStore()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      window.attachedSheet == nil,
                      let shortcut = FinderShortcut.match(
                          keyCode: event.keyCode,
                          charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                          modifierFlags: event.modifierFlags,
                          isEditingText: window.firstResponder is NSText
                      ),
                      self.handler?(shortcut, window) == true
                else { return event }
                return nil
            }
            eventMonitorStore.startMonitoring(monitor)
        }

        func stopMonitoring() {
            eventMonitorStore.stopMonitoring()
        }
    }
}

/// What Return does in the delete prompt. Return asks for permanent deletion
/// and then confirms it; the second press only counts once the confirmation
/// step has been visible briefly, and auto-repeat from a held key never counts.
enum DeletePromptReturnKey {
    enum Action: Equatable {
        case askForPermanentConfirmation
        case confirmPermanentDeletion
    }

    static let returnKeyCodes: Set<UInt16> = [36, 76] // Return, keypad Enter
    static let confirmationArmingDelay: TimeInterval = 0.4

    static func action(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        isRepeat: Bool,
        step: DeletePromptStep,
        timeInStep: TimeInterval
    ) -> Action? {
        let modifiers = modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard returnKeyCodes.contains(keyCode), modifiers.isEmpty, !isRepeat else { return nil }
        switch step {
        case .choosingMethod:
            return .askForPermanentConfirmation
        case .confirmingPermanent:
            return timeInStep >= confirmationArmingDelay ? .confirmPermanentDeletion : nil
        }
    }
}

enum ToolbarSearch {
    /// Puts the cursor in the window's toolbar search field (from `.searchable`).
    @MainActor
    static func focus(in window: NSWindow?) {
        guard let toolbar = window?.toolbar else { return }
        if let item = toolbar.items.lazy.compactMap({ $0 as? NSSearchToolbarItem }).first {
            item.beginSearchInteraction()
            return
        }
        // Fallback for a search field hosted in a plain toolbar item.
        for item in toolbar.items {
            if let field = item.view.flatMap(findSearchField) {
                window?.makeFirstResponder(field)
                return
            }
        }
    }

    @MainActor
    private static func findSearchField(in view: NSView) -> NSSearchField? {
        if let field = view as? NSSearchField { return field }
        for subview in view.subviews {
            if let field = findSearchField(in: subview) { return field }
        }
        return nil
    }
}
