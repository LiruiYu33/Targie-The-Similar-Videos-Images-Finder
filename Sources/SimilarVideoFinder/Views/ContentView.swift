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

struct ContentView: View {
    @ObservedObject var model: ScanViewModel
    @AppStorage("appLanguage") private var languageRawValue = AppLanguage.defaultLanguage.rawValue
    @AppStorage("scanMode") private var scanModeRawValue = ScanMode.all.rawValue

    @State private var appMode: AppMode = .scan
    @StateObject private var browseSession = BrowseSessionCoordinator()
    @State private var isClearCacheConfirmPresented = false
    @State private var cacheMB = (thumbnailMB: "0", hashMB: "0")

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .defaultLanguage
    }

    var body: some View {
        Group {
            switch appMode {
            case .scan:
                scanView
            case .browse:
                if let browseModel = browseSession.browseModel {
                    BrowseView(browseModel: browseModel, onBack: exitBrowseMode)
                        .sheet(item: $model.deletePrompt) { _ in
                            DeleteConfirmationView(model: model)
                        }
                }
            }
        }
        .alert(L10n.operationFailed(language), isPresented: Binding(
            get: { model.presentedError != nil },
            set: { if !$0 { model.presentedError = nil } }
        )) {
            Button(L10n.ok(language)) { model.presentedError = nil }
        } message: {
            Text(model.localizedError(language) ?? L10n.unknownError(language))
        }
        .alert(
            L10n.clearCacheConfirmTitle(language),
            isPresented: $isClearCacheConfirmPresented
        ) {
            Button(L10n.clearCache(language), role: .destructive) {
                Task { await model.clearAllCaches() }
            }
            Button(L10n.cancel(language), role: .cancel) {}
        } message: {
            Text(L10n.clearCacheConfirmMessage(cacheMB.thumbnailMB, cacheMB.hashMB, language))
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.addFolders(urls)
        }
        .environment(\.appLanguage, language)
        .onAppear {
            model.setScanMode(ScanMode(rawValue: scanModeRawValue) ?? .all)
            browseSession.prepareIfPossible(scanModel: model)
        }
        .onChange(of: model.items.count) { _, _ in
            browseSession.prepareIfPossible(scanModel: model)
        }
        .onChange(of: model.progress.stage) { _, stage in
            if stage == .completed {
                browseSession.prepareIfPossible(scanModel: model)
            }
        }
        .background(
            // In scan mode this owns the window title; browse mode installs
            // its own dynamic WindowTitleUpdater that reflects item count.
            Group {
                if appMode == .scan {
                    WindowTitleUpdater(title: L10n.appName(language))
                }
            }
        )
    }

    // MARK: - Scan Mode View

    private var scanView: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(
                    min: SplitColumnConfiguration.sidebar.minWidth,
                    ideal: SplitColumnConfiguration.sidebar.idealWidth,
                    max: SplitColumnConfiguration.sidebar.maxWidth ?? SplitColumnConfiguration.sidebar.idealWidth
                )
        } content: {
            GroupDetailView(model: model)
                .navigationSplitViewColumnWidth(
                    min: SplitColumnConfiguration.comparison.minWidth,
                    ideal: SplitColumnConfiguration.comparison.idealWidth
                )
        } detail: {
            InspectorView(model: model)
                .navigationSplitViewColumnWidth(
                    min: SplitColumnConfiguration.preview.minWidth,
                    ideal: SplitColumnConfiguration.preview.idealWidth
                )
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("", selection: Binding(
                    get: { ScanMode(rawValue: scanModeRawValue) ?? .all },
                    set: { mode in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            scanModeRawValue = mode.rawValue
                            model.setScanMode(mode)
                        }
                    }
                )) {
                    Text(L10n.videos(language)).tag(ScanMode.videos)
                    Text(L10n.images(language)).tag(ScanMode.images)
                    Text(L10n.allMedia(language)).tag(ScanMode.all)
                }
                .pickerStyle(.segmented)
                .fixedSize()

                ToolbarLabeledButton(
                    title: L10n.browse(language),
                    systemImage: "doc.text.image",
                    action: enterBrowseMode
                )
                .disabled(model.selectedFolders.isEmpty)

                ToolbarLabeledButton(
                    title: L10n.clearCache(language),
                    systemImage: "arrow.triangle.2.circlepath"
                ) {
                    Task {
                        cacheMB = await model.cacheStats()
                        isClearCacheConfirmPresented = true
                    }
                }
                .disabled(model.isScanning)

                ToolbarLabeledPopover(
                    title: L10n.language(language),
                    systemImage: "globe"
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(AppLanguage.allCases) { option in
                            Button {
                                languageRawValue = option.rawValue
                            } label: {
                                HStack {
                                    Text(option.menuLabel)
                                    Spacer(minLength: 16)
                                    if option == language {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .frame(minWidth: 140, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .sheet(item: $model.deletePrompt) { _ in
            DeleteConfirmationView(model: model)
        }
        .onDeleteCommand {
            if let video = model.selectedMedia { model.requestDeletion(of: video) }
        }
    }

    // MARK: - Mode Switching

    private func enterBrowseMode() {
        if !model.hasDiscoveredItems {
            model.discoverFiles()
        }
        _ = browseSession.model(for: model)
        appMode = .browse
    }

    private func exitBrowseMode() {
        appMode = .scan
        browseSession.leaveBrowseMode()
    }
}

// MARK: - App Mode

enum AppMode {
    case scan
    case browse
}

struct WindowTitleUpdater: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.title = title }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { view.window?.title = title }
    }
}
