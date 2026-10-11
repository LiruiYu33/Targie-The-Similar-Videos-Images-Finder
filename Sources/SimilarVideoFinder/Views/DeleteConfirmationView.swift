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

struct DeleteConfirmationView: View {
    @ObservedObject var model: ScanViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @State private var stepShownAt = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let prompt = model.deletePrompt {
                Image(systemName: prompt.step == .choosingMethod ? "trash" : "exclamationmark.triangle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(prompt.step == .choosingMethod ? Color.secondary : Color.red)

                Text(prompt.step == .choosingMethod ? L10n.deleteHow(language) : L10n.permanentWarningTitle(language))
                    .font(.title2.bold())
                Text(L10n.selectedCount(prompt.media.count, language)).font(.headline)
                Text(prompt.media.map { $0.url.path }.joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if prompt.step == .choosingMethod {
                    Text(L10n.trashExplanation(language))
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Text(L10n.deleteShortcutHint(language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(L10n.cancel(language)) { cancel() }
                            .keyboardShortcut(.cancelAction)
                        Spacer()
                        Button(L10n.permanentDelete(language)) { model.askForPermanentConfirmation() }
                        Button(L10n.moveToTrash(language)) {
                            Task {
                                await model.confirmPromptDeletion(mode: .trash)
                                if model.deletePrompt == nil { dismiss() }
                            }
                        }
                        .keyboardShortcut(.space, modifiers: [])
                    }
                } else {
                    Text(L10n.irreversible(language))
                        .foregroundStyle(.red)
                    HStack {
                        Spacer()
                        Text(L10n.confirmPermanentShortcutHint(language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(L10n.cancel(language)) { cancel() }
                            .keyboardShortcut(.cancelAction)
                        Spacer()
                        Button(L10n.back(language)) {
                            model.deletePrompt = DeletePrompt(media: prompt.media, step: .choosingMethod)
                        }
                        Button(L10n.confirmPermanent(language), role: .destructive, action: confirmPermanent)
                    }
                }
                if model.isDeleting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
        .disabled(model.isDeleting)
        // Return is handled here instead of as a button shortcut so the
        // permanent action is never drawn as the blue default button.
        .background(ReturnKeyMonitor(onReturn: handleReturn))
        .onChange(of: model.deletePrompt?.step) { _, _ in stepShownAt = Date() }
    }

    private func handleReturn(_ event: NSEvent) -> Bool {
        guard !model.isDeleting, let prompt = model.deletePrompt,
              let action = DeletePromptReturnKey.action(
                  keyCode: event.keyCode,
                  modifierFlags: event.modifierFlags,
                  isRepeat: event.isARepeat,
                  step: prompt.step,
                  timeInStep: Date().timeIntervalSince(stepShownAt)
              )
        else { return false }
        switch action {
        case .askForPermanentConfirmation:
            model.askForPermanentConfirmation()
        case .confirmPermanentDeletion:
            confirmPermanent()
        }
        return true
    }

    private func confirmPermanent() {
        Task {
            await model.confirmPromptDeletion(mode: .permanent)
            if model.deletePrompt == nil { dismiss() }
        }
    }

    private func cancel() {
        model.deletePrompt = nil
        dismiss()
    }
}

/// Delivers Return key presses in the sheet's own window to `onReturn`;
/// returning true swallows the event.
private struct ReturnKeyMonitor: NSViewRepresentable {
    let onReturn: (NSEvent) -> Bool

    func makeNSView(context: Context) -> MonitoringView {
        let view = MonitoringView()
        view.onReturn = onReturn
        return view
    }

    func updateNSView(_ view: MonitoringView, context: Context) {
        view.onReturn = onReturn
    }

    static func dismantleNSView(_ view: MonitoringView, coordinator: ()) {
        view.eventMonitorStore.stopMonitoring()
    }

    final class MonitoringView: NSView {
        var onReturn: ((NSEvent) -> Bool)?
        let eventMonitorStore = EventMonitorStore()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            eventMonitorStore.stopMonitoring()
            guard window != nil else { return }
            let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window,
                      DeletePromptReturnKey.returnKeyCodes.contains(event.keyCode),
                      self.onReturn?(event) == true
                else { return event }
                return nil
            }
            eventMonitorStore.startMonitoring(monitor)
        }
    }
}
