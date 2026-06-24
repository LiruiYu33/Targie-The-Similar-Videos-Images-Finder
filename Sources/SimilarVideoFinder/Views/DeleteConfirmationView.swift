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

struct DeleteConfirmationView: View {
    @ObservedObject var model: ScanViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

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
                        Text(L10n.trashShortcutHint(language))
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
                        Button(L10n.cancel(language)) { cancel() }
                            .keyboardShortcut(.cancelAction)
                        Spacer()
                        Button(L10n.back(language)) {
                            model.deletePrompt = DeletePrompt(media: prompt.media, step: .choosingMethod)
                        }
                        Button(L10n.confirmPermanent(language), role: .destructive) {
                            Task {
                                await model.confirmPromptDeletion(mode: .permanent)
                                if model.deletePrompt == nil { dismiss() }
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func cancel() {
        model.deletePrompt = nil
        dismiss()
    }
}
