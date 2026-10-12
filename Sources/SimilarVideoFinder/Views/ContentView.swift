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
    @Bindable var model: ScanViewModel
    @AppStorage("appLanguage") private var languageRawValue = AppLanguage.defaultLanguage.rawValue
    @AppStorage("scanMode") private var scanModeRawValue = ScanMode.all.rawValue
    @AppStorage("scanIntensity") private var scanIntensityRawValue = ScanIntensity.defaultIntensity.rawValue
    @AppStorage("excludeSubfolders") private var excludeSubfolders = false
    @AppStorage("deepVerification") private var deepVerification = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appMode: AppMode = .scan
    /// Fades the whole window content after a mode switch; see `switchMode`.
    @State private var isModeContentVisible = true
    @State private var browseSession = BrowseSessionCoordinator()
    @State private var isClearCacheConfirmPresented = false
    @State private var isSettingsPresented = false
    @State private var isInspectorPresented = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var inspectorWidth: CGFloat = 320
    @State private var inspectorDragStartWidth: CGFloat?
    @State private var isInspectorResizeCursorPushed = false
    @State private var cacheMB = (thumbnailMB: "0", hashMB: "0")

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .defaultLanguage
    }

    private var scanIntensity: ScanIntensity {
        ScanIntensity(rawValue: scanIntensityRawValue) ?? .defaultIntensity
    }

    var body: some View {
        Group {
            switch appMode {
            case .scan:
                scanView
            case .browse:
                if let browseModel = browseSession.browseModel {
                    BrowseView(
                        browseModel: browseModel,
                        excludeSubfolders: $excludeSubfolders,
                        onBack: exitBrowseMode
                    )
                        .sheet(item: $model.deletePrompt) { _ in
                            DeleteConfirmationView(model: model)
                        }
                }
            }
        }
        .opacity(isModeContentVisible ? 1 : 0)
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
                Task { _ = await model.clearAllCaches() }
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
            model.setScanIntensity(scanIntensity)
            model.setDeepVerification(deepVerification)
            model.excludeSubfolders = excludeSubfolders
            browseSession.prepareIfPossible(scanModel: model)
            columnVisibility = model.selectedFolders.isEmpty ? .detailOnly : .all
        }
        .onChange(of: model.selectedFolders.isEmpty) { _, isEmpty in
            withAnimation(Motion.standard) {
                columnVisibility = isEmpty ? .detailOnly : .all
                if isEmpty { isInspectorPresented = false }
            }
        }
        .onChange(of: scanIntensityRawValue) { _, _ in
            model.setScanIntensity(scanIntensity)
        }
        .onChange(of: deepVerification) { _, value in
            model.setDeepVerification(value)
        }
        .onChange(of: excludeSubfolders) { _, value in
            model.excludeSubfolders = value
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
            WindowTitleUpdater(title: appMode == .scan
                ? AppIdentity.displayName
                : L10n.browseItemCount(browseSession.browseModel?.displayedItems.count ?? 0, language))
        )
    }

    private func updateInspectorResizeCursor(hovering: Bool) {
        if hovering && !isInspectorResizeCursorPushed {
            NSCursor.resizeLeftRight.push()
            isInspectorResizeCursorPushed = true
        } else if !hovering && isInspectorResizeCursorPushed {
            NSCursor.pop()
            isInspectorResizeCursorPushed = false
        }
    }

    // MARK: - Scan Mode View

    private var scanView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(model: model, excludeSubfolders: $excludeSubfolders)
                .navigationSplitViewColumnWidth(
                    min: SplitColumnConfiguration.sidebar.minWidth,
                    ideal: SplitColumnConfiguration.sidebar.idealWidth,
                    max: SplitColumnConfiguration.sidebar.maxWidth ?? SplitColumnConfiguration.sidebar.idealWidth
                )
        } detail: {
            GeometryReader { geometry in
                let dividerWidth: CGFloat = 8
                let maximumPreviewWidth = max(0, min(380, geometry.size.width - 280 - dividerWidth))
                // The panel keeps its width while hidden so it slides out intact
                // instead of collapsing; only the comparison area resizes.
                let previewWidth = min(max(280, inspectorWidth), maximumPreviewWidth)
                let comparisonWidth = isInspectorPresented
                    ? max(0, geometry.size.width - previewWidth - dividerWidth)
                    : geometry.size.width

                HStack(spacing: 0) {
                    GroupDetailView(model: model) {
                        guard !isInspectorPresented else { return }
                        withAnimation(Motion.standard) { isInspectorPresented = true }
                    }
                        .frame(width: comparisonWidth, height: geometry.size.height)
                    if isInspectorPresented {
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(.quaternary)
                                .frame(width: 1)
                                .frame(width: dividerWidth)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 1)
                                        .onChanged { value in
                                            let start = inspectorDragStartWidth ?? previewWidth
                                            if inspectorDragStartWidth == nil { inspectorDragStartWidth = start }
                                            inspectorWidth = min(max(280, start - value.translation.width), maximumPreviewWidth)
                                        }
                                        .onEnded { _ in inspectorDragStartWidth = nil }
                                )
                                .onHover { updateInspectorResizeCursor(hovering: $0) }
                                .onDisappear { updateInspectorResizeCursor(hovering: false) }
                            InspectorView(model: model)
                                .frame(width: previewWidth, height: geometry.size.height)
                        }
                        .transition(Motion.slide(from: .trailing, reduceMotion: reduceMotion))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
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
                .disabled(model.selectedFolders.isEmpty || model.isBusy)

                ToolbarLabeledButton(
                    title: L10n.details(language),
                    systemImage: "sidebar.right",
                    action: { withAnimation(Motion.standard) { isInspectorPresented.toggle() } }
                )
                .disabled(model.selectedFolders.isEmpty)
                .help(L10n.previewAndDetails(language))
                .accessibilityValue(isInspectorPresented ? "Visible" : "Hidden")

                ToolbarLabeledButton(
                    title: L10n.settings(language),
                    systemImage: "gearshape",
                    action: { isSettingsPresented.toggle() }
                )
                .popover(isPresented: $isSettingsPresented, arrowEdge: .bottom) {
                    SettingsPopover(
                        model: model,
                        scanIntensityRawValue: $scanIntensityRawValue,
                        languageRawValue: $languageRawValue,
                        deepVerification: $deepVerification,
                        onClearCache: {
                            isSettingsPresented = false
                            Task {
                                let stats = await model.cacheStats()
                                guard !model.isBusy else { return }
                                cacheMB = stats
                                isClearCacheConfirmPresented = true
                            }
                        }
                    )
                }
            }
        }
        .sheet(item: $model.deletePrompt) { _ in
            DeleteConfirmationView(model: model)
        }
        .onDeleteCommand(perform: deleteCurrentSelection)
        .background(FinderShortcutMonitor(onMoveToTrash: deleteCurrentSelection))
    }

    private func deleteCurrentSelection() {
        guard !model.isBusy else { return }
        if !model.checkedMediaIDs.isEmpty {
            model.requestCheckedDeletion()
        } else if let video = model.selectedMedia {
            model.requestDeletion(of: video)
        }
    }

    // MARK: - Mode Switching

    private func enterBrowseMode() {
        guard !model.isBusy else { return }
        if !model.hasDiscoveredItems {
            model.discoverFiles()
        }
        _ = browseSession.model(for: model)
        switchMode(to: .browse)
    }

    private func exitBrowseMode() {
        switchMode(to: .scan)
        browseSession.leaveBrowseMode()
    }
}

extension ContentView {
    /// Swaps screens without animating their layout, then fades the new one in.
    /// Animating the swap itself rebuilt the split view inside an animated
    /// transaction, so sidebar, columns and toolbar all sprang into place.
    fileprivate func switchMode(to mode: AppMode) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isModeContentVisible = false
            appMode = mode
        }
        DispatchQueue.main.async {
            withAnimation(Motion.fade) { isModeContentVisible = true }
        }
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
