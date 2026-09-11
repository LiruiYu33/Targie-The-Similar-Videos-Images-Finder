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

struct BrowseFilterPopover: View {
    @ObservedObject var browseModel: BrowseViewModel
    @Binding var excludeSubfolders: Bool
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $excludeSubfolders) {
                Text(L10n.excludeSubfolders(language))
            }
            .toggleStyle(.checkbox)
            .disabled(browseModel.scanModel.isBusy)
            .help(L10n.excludeSubfolders(language))

            Divider()

            // Media type filter
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.mediaType(language))
                    .font(.headline)
                Picker("", selection: $browseModel.mediaFilter) {
                    Text(L10n.allMedia(language)).tag(BrowseViewModel.MediaFilter.all)
                    Text(L10n.images(language)).tag(BrowseViewModel.MediaFilter.images)
                    Text(L10n.videos(language)).tag(BrowseViewModel.MediaFilter.videos)
                }
                .pickerStyle(.segmented)
            }

            Divider()

            // Resolution filter
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.resolution(language))
                    .font(.headline)

                // Comparison toggle (< or >)
                HStack {
                    Text(L10n.resolution(language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $browseModel.resolutionComparator) {
                        Text("<").tag(BrowseViewModel.ResolutionComparator.lessThan)
                        Text(">").tag(BrowseViewModel.ResolutionComparator.greaterThan)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                }

                // Preset buttons
                HStack(spacing: 6) {
                    presetButton("320p", shortEdge: 320)
                    presetButton("480p", shortEdge: 480)
                    presetButton("720p", shortEdge: 720)
                    presetButton("1080p", shortEdge: 1080)
                    presetButton("2K", shortEdge: 1440)
                }

                // Manual input
                HStack(spacing: 4) {
                    TextField(L10n.width(language), text: Binding(
                        get: { browseModel.manualWidth },
                        set: { browseModel.setManualWidth($0) }
                    ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text("×")
                        .foregroundStyle(.secondary)
                    TextField(L10n.height(language), text: Binding(
                        get: { browseModel.manualHeight },
                        set: { browseModel.setManualHeight($0) }
                    ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }
                .controlSize(.small)

                // Clear filter
                if browseModel.selectedResolutionPreset != nil
                    || validManualWidth != nil
                    || validManualHeight != nil {
                    Button(L10n.clearFilter(language), action: browseModel.clearResolutionFilter)
                        .controlSize(.small)
                }
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private var validManualWidth: Int? {
        guard let v = Int(browseModel.manualWidth), v > 0 else { return nil }
        return v
    }

    private var validManualHeight: Int? {
        guard let v = Int(browseModel.manualHeight), v > 0 else { return nil }
        return v
    }

    @ViewBuilder
    private func presetButton(_ label: String, shortEdge: Int) -> some View {
        let isActive = browseModel.selectedResolutionPreset?.shortEdge == shortEdge
        if isActive {
            Button {
                browseModel.clearResolutionFilter()
            } label: {
                Text(label)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button {
                browseModel.setResolutionPreset(BrowseViewModel.ResolutionPreset(
                    id: label, label: label, shortEdge: shortEdge
                ))
            } label: {
                Text(label)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
