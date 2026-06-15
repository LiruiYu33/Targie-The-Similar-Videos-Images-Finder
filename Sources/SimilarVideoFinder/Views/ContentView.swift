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
    @StateObject private var model = ScanViewModel()
    @AppStorage("appLanguage") private var languageRawValue = AppLanguage.defaultLanguage.rawValue
    @AppStorage("scanMode") private var scanModeRawValue = ScanMode.all.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .defaultLanguage
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } content: {
            GroupDetailView(model: model)
                .navigationSplitViewColumnWidth(min: 440, ideal: 590)
        } detail: {
            InspectorView(model: model)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 390)
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("", selection: Binding(
                    get: { ScanMode(rawValue: scanModeRawValue) ?? .all },
                    set: { mode in scanModeRawValue = mode.rawValue; model.setScanMode(mode) }
                )) {
                    Text(L10n.videos(language)).tag(ScanMode.videos)
                    Text(L10n.images(language)).tag(ScanMode.images)
                    Text(L10n.allMedia(language)).tag(ScanMode.all)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                Button(action: { model.chooseFolder(language: language) }) {
                    Label(L10n.chooseFolder(language), systemImage: "folder.badge.plus")
                }
                Button(action: model.startScan) {
                    Label(L10n.startScan(language), systemImage: "sparkle.magnifyingglass")
                }
                .disabled(model.selectedFolders.isEmpty || model.isScanning)
                Menu {
                    ForEach(AppLanguage.allCases) { option in
                        Button {
                            languageRawValue = option.rawValue
                        } label: {
                            if option == language {
                                Label(option.menuLabel, systemImage: "checkmark")
                            } else {
                                Text(option.menuLabel)
                            }
                        }
                    }
                } label: {
                    Label(L10n.language(language), systemImage: "globe")
                }
            }
        }
        .sheet(item: $model.deletePrompt) { _ in
            DeleteConfirmationView(model: model)
        }
        .alert(L10n.operationFailed(language), isPresented: Binding(
            get: { model.presentedError != nil },
            set: { if !$0 { model.presentedError = nil } }
        )) {
            Button(L10n.ok(language)) { model.presentedError = nil }
        } message: {
            Text(model.localizedError(language) ?? L10n.unknownError(language))
        }
        .onDeleteCommand {
            if let video = model.selectedMedia { model.requestDeletion(of: video) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.addFolders(urls)
        }
        .environment(\.appLanguage, language)
        .onAppear { model.setScanMode(ScanMode(rawValue: scanModeRawValue) ?? .all) }
        .background(WindowTitleUpdater(title: L10n.appName(language)))
    }
}

private struct WindowTitleUpdater: NSViewRepresentable {
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
