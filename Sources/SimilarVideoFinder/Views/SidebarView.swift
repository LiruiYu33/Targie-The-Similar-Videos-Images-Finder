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
    @Binding var excludeSubfolders: Bool
    @Environment(\.appLanguage) private var language
    @State private var showSkippedFiles = false
    @State private var areSourcesExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.similarGroups(language)).font(.headline)
                    Spacer()
                    Text("\(model.groups.count)").monospacedDigit().foregroundStyle(.secondary)
                }
                if model.hasDiscoveredItems || model.progress.stage == .completed {
                    DisplayThresholdControl(threshold: $model.threshold, language: language)
                }
            }
            .padding(14)
            groupList
        }
        .navigationTitle(L10n.similarMedia(language))
        .onChange(of: model.progress.stage) { _, stage in
            if stage == .completed { areSourcesExpanded = false }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L10n.workspaceFolders(language), systemImage: "folder")
                    .font(.headline)
                Spacer()
                Button(action: { model.chooseFolder(language: language) }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(L10n.addFolders(language))
                .accessibilityLabel(L10n.addFolders(language))
                Menu {
                    Button(L10n.clearFolders(language)) { model.clearFolders() }
                        .disabled(model.selectedFolders.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel(L10n.workspaceFolders(language))
            }
            .disabled(model.isBusy)

            DisclosureGroup(isExpanded: $areSourcesExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    selectedFolderList
                    Toggle(isOn: $excludeSubfolders) {
                        Text(L10n.excludeSubfolders(language)).font(.caption)
                    }
                    .toggleStyle(.checkbox)
                    .disabled(model.isBusy)
                }
                .padding(.top, 8)
            } label: {
                Text(model.selectedFolders.count == 1 ? model.selectedFolders[0].lastPathComponent : L10n.foldersSelected(model.selectedFolders.count, language))
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(model.selectedFolders.map(\.path).joined(separator: "\n"))
            }
            scanAction
            skippedFilesButton
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
    }

    @ViewBuilder
    private var scanAction: some View {
        if model.isScanning {
            ProgressView(value: model.progress.fraction) {
                Text(L10n.scanProgressTitle(model.progress, language))
            } currentValueLabel: {
                Text(L10n.scanProgressDetail(model.progress, language))
                    .lineLimit(1)
            }
            Button(role: .cancel, action: model.cancelScan) {
                sidebarActionLabel(L10n.cancelScan(language), systemImage: "xmark")
            }
            .sidebarActionButtonShape()
        } else {
            Button(action: model.startScan) {
                sidebarActionLabel(L10n.startScan(language), systemImage: "sparkle.magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .sidebarActionButtonShape()
            .disabled(model.selectedFolders.isEmpty || model.isBusy)
        }
    }

    private func sidebarActionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var selectedFolderList: some View {
        if !model.selectedFolders.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.selectedFolders, id: \.self) { folder in
                    selectedFolderRow(folder)
                }
            }
        }
    }

    private func selectedFolderRow(_ folder: URL) -> some View {
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
            .disabled(model.isBusy)
            .foregroundStyle(.secondary)
            .help(L10n.removeFolder(language))
        }
    }

    @ViewBuilder
    private var skippedFilesButton: some View {
        if !model.issues.isEmpty {
            Button { showSkippedFiles.toggle() } label: {
                Label(L10n.skippedFiles(model.issues.count, language), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSkippedFiles) {
                SkippedFilesList(issues: model.issues, language: language) { issue in
                    model.revealIssue(issue)
                }
            }
        }
    }

    @ViewBuilder
    private var groupList: some View {
        if model.groups.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.progress.stage == .completed ? L10n.noSimilarMedia(language) : L10n.scanResultsHint(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            List(selection: Binding(
                get: { model.selectedGroupID },
                set: { model.selectGroup($0) }
            )) {
                if model.scanMode == .all {
                    let videoGroups = model.groups.filter { $0.items.first?.kind == .video }
                    let imageGroups = model.groups.filter { $0.items.first?.kind == .image }
                    if !videoGroups.isEmpty {
                        Section(L10n.videos(language)) { groupRows(videoGroups) }
                    }
                    if !imageGroups.isEmpty {
                        Section(L10n.images(language)) { groupRows(imageGroups) }
                    }
                } else {
                    let kind: MediaKind = model.scanMode == .videos ? .video : .image
                    groupRows(model.groups.filter { $0.items.first?.kind == kind })
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func groupRows(_ groups: [SimilarityGroup]) -> some View {
        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
            HStack(spacing: 10) {
                if let item = group.items.first {
                    MediaThumbnailView(item: item, placeholderSystemImage: item.kind == .image ? "photo" : "film")
                        .frame(width: 38, height: 38)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
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

private extension View {
    func sidebarActionButtonShape() -> some View {
        controlSize(.large)
    }
}

// MARK: - Display Threshold

private struct DisplayThresholdControl: View {
    @Binding var threshold: Double
    let language: AppLanguage

    @State private var editState = DisplayThresholdTextEditState(threshold: DisplayThresholdEditing.recommendedThreshold)
    @FocusState private var isThresholdTextFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(L10n.displayThreshold(language))
                Spacer()
                HStack(spacing: 2) {
                    if editState.isEditing {
                        TextField(
                            L10n.displayThreshold(language),
                            text: Binding(
                                get: { editState.editText },
                                set: { editState.editText = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 54)
                        .focused($isThresholdTextFocused)
                        .onSubmit(commitThresholdText)
                    } else {
                        Button {
                            beginThresholdTextEditing()
                        } label: {
                            Text(editState.displayText)
                                .monospacedDigit()
                                .frame(width: 42, alignment: .trailing)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Text("%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .background(
                    ClickOutsideMonitor(
                        isActive: editState.isEditing,
                        onClickOutside: commitThresholdText
                    )
                )
            }
            .font(.caption)

            Slider(
                value: Binding(
                    get: { threshold },
                    set: { threshold = DisplayThresholdEditing.sliderValue(for: $0) }
                ),
                in: ScanViewModel.displayThresholdRange,
                step: 0.01
            ) {
                EmptyView()
            } minimumValueLabel: {
                Text("60%").font(.system(size: 9)).foregroundStyle(.tertiary)
            } maximumValueLabel: {
                Text("100%").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            .help(L10n.displayThresholdHelp(language))

            if threshold < DisplayThresholdEditing.recommendedThreshold {
                Text(L10n.displayThresholdHelp(language))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .onAppear { editState.syncThreshold(threshold) }
        .onChange(of: threshold) { _, _ in
            editState.syncThreshold(threshold)
        }
        .onChange(of: isThresholdTextFocused) { _, isFocused in
            if !isFocused && editState.isEditing {
                commitThresholdText()
            }
        }
    }

    private func beginThresholdTextEditing() {
        editState.syncThreshold(threshold)
        editState.beginEditing()
        DispatchQueue.main.async {
            isThresholdTextFocused = true
        }
    }

    private func commitThresholdText() {
        editState.commitCurrentText()
        threshold = editState.threshold
        isThresholdTextFocused = false
    }
}

// MARK: - Skipped Files Popover

struct SkippedFilesList: View {
    let issues: [ScanIssue]
    let language: AppLanguage
    let onRevealIssue: (ScanIssue) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.skippedFiles(issues.count, language))
                .font(.headline)
                .padding(.horizontal, SkippedFilesPopoverLayout.headerPadding)
                .padding(.top, SkippedFilesPopoverLayout.headerPadding)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(issues) { issue in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.url.lastPathComponent)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(issue.message(language: language))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button { onRevealIssue(issue) } label: {
                                Text(issue.url.deletingLastPathComponent().path)
                                    .font(.caption2)
                                    .foregroundStyle(Color.accentColor)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .buttonStyle(.plain)
                            .help(L10n.showInFinder(language))
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 8)
                .padding(.leading, SkippedFilesPopoverLayout.contentLeadingPadding)
                .padding(.trailing, SkippedFilesPopoverLayout.contentTrailingPadding)
            }
        }
        .frame(
            width: SkippedFilesPopoverLayout.width,
            height: SkippedFilesPopoverLayout.height(issueCount: issues.count)
        )
    }
}
