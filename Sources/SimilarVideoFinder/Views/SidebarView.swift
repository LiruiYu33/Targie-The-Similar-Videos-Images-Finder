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

struct SidebarView: View {
    @ObservedObject var model: ScanViewModel
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            groupList
        }
        .navigationTitle(L10n.similarMedia(language))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { model.chooseFolder(language: language) }) {
                Label(L10n.addFolders(language), systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(model.isScanning)

            if model.selectedFolders.isEmpty {
                Text(L10n.dragFoldersHint(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.foldersSelected(model.selectedFolders.count, language))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(model.selectedFolders, id: \.self) { folder in
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(folder.path)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(folder.path)
                        Spacer(minLength: 0)
                        Button {
                            model.removeFolder(folder)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isScanning)
                        .foregroundStyle(.secondary)
                        .help(L10n.removeFolder(language))
                    }
                }
            }

            if model.isScanning {
                ProgressView(value: model.progress.fraction) {
                    Text(L10n.scanStage(model.progress.stage, language))
                } currentValueLabel: {
                    Text(model.progress.currentFile)
                        .lineLimit(1)
                }
                Button(L10n.cancelScan(language), role: .cancel, action: model.cancelScan)
            } else {
                Button(action: model.startScan) {
                    Label(L10n.startScan(language), systemImage: "sparkle.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedFolders.isEmpty)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(L10n.displayThreshold(language))
                    Spacer()
                    Text(DisplayFormatters.percent(model.threshold)).monospacedDigit()
                }
                .font(.caption)
                Slider(value: $model.threshold, in: ScanViewModel.displayThresholdRange, step: 0.01)
                    .help(L10n.displayThresholdHelp(language))
            }

            if !model.issues.isEmpty {
                Label(L10n.skippedFiles(model.issues.count, language), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(model.issues.map { "\($0.url.lastPathComponent): \($0.message(language: language))" }.joined(separator: "\n"))
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private var groupList: some View {
        if model.groups.isEmpty {
            ContentUnavailableView(
                model.progress.stage == .completed ? L10n.noSimilarMedia(language) : L10n.waitingToScan(language),
                systemImage: model.progress.stage == .completed ? "checkmark.circle" : "photo.stack",
                description: Text(model.progress.stage == .completed ? L10n.lowerThresholdHint(language) : L10n.chooseAndScanHint(language))
            )
        } else {
            List(selection: Binding(
                get: { model.selectedGroupID },
                set: { model.selectGroup($0) }
            )) {
                if model.scanMode == .all {
                    Section(L10n.videos(language)) { groupRows(model.groups.filter { $0.items.first?.kind == .video }) }
                    Section(L10n.images(language)) { groupRows(model.groups.filter { $0.items.first?.kind == .image }) }
                } else {
                    groupRows(model.groups)
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func groupRows(_ groups: [SimilarityGroup]) -> some View {
        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
            HStack(spacing: 10) {
                Image(systemName: group.items.first?.kind == .image ? "photo.stack" : "film.stack")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.similarGroup(index + 1, language))
                    Text(L10n.mediaCountAndScore(group.items.count, DisplayFormatters.percent(group.maximumScore), language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tag(group.id)
        }
    }
}
