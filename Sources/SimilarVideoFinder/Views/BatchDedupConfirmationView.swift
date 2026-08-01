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

/// A pre-computed plan describing which files would be deleted across all
/// groups when batch-deduplicating with a given retention strategy.
struct DedupPlan {
    let strategy: RetentionStrategy
    let groupsAffected: Int
    let totalFilesToDelete: Int
    let totalBytesToReclaim: Int64
    let targets: [(groupID: UUID, keeper: MediaItem, toDelete: [MediaItem])]

    /// Empty plan — shown when there are no groups to deduplicate or the
    /// currently selected strategy deletes nothing.
    static func empty(strategy: RetentionStrategy) -> DedupPlan {
        DedupPlan(
            strategy: strategy,
            groupsAffected: 0,
            totalFilesToDelete: 0,
            totalBytesToReclaim: 0,
            targets: []
        )
    }
}

/// Confirmation sheet shown before executing a batch deduplication.
/// Users pick a retention strategy, review the summary, and confirm.
struct BatchDedupConfirmationView: View {
    let computedPlan: (RetentionStrategy) -> DedupPlan
    let onExecute: (RetentionStrategy) async -> Void
    let onDismiss: () -> Void

    @Environment(\.appLanguage) private var language
    @State private var strategy: RetentionStrategy = .keepSmallest
    @State private var isExecuting = false

    private var plan: DedupPlan {
        computedPlan(strategy)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.cleanDuplicates(language))
                .font(.headline)

            // Strategy picker
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.keepStrategy(language))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("", selection: $strategy) {
                    ForEach(RetentionStrategy.allCases) { s in
                        Text(s.label(language)).tag(s)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            // Summary
            VStack(alignment: .leading, spacing: 6) {
                summaryRow(L10n.groupsAffected(language), value: "\(plan.groupsAffected)")
                summaryRow(L10n.filesToDelete(language), value: "\(plan.totalFilesToDelete)")
                summaryRow(L10n.spaceToReclaim(language),
                           value: DisplayFormatters.fileSize(plan.totalBytesToReclaim))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.06))
            )

            if plan.totalFilesToDelete == 0 {
                Text(L10n.noDuplicatesToRemove(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Action buttons
            HStack {
                Spacer()
                if isExecuting {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 8)
                }
                Button(L10n.cancel(language), role: .cancel) {
                    onDismiss()
                }
                .disabled(isExecuting)
                Button {
                    isExecuting = true
                    Task {
                        await onExecute(strategy)
                        await MainActor.run {
                            isExecuting = false
                            onDismiss()
                        }
                    }
                } label: {
                    Text(L10n.trashCount(plan.totalFilesToDelete, language))
                }
                .disabled(plan.totalFilesToDelete == 0 || isExecuting)
            }
        }
        .frame(width: 340)
        .padding()
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
    }
}