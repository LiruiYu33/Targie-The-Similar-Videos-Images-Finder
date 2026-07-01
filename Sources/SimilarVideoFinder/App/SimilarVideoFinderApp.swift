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

enum AppIdentity {
    static let displayName = "Targie"
    static let bundleIdentifier = "local.aaronyu.SimilarVideoFinder"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let application = notification.object as? NSApplication ?? NSApplication.shared
        application.setActivationPolicy(.regular)
        application.activate(ignoringOtherApps: true)
    }
}

@main
struct SimilarVideoFinderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Owned at the App level so state survives window close (Cmd+W).
    @StateObject private var scanModel: ScanViewModel

    init() {
        _scanModel = StateObject(wrappedValue: ScanViewModel())
    }

    var body: some Scene {
        WindowGroup(AppIdentity.displayName) {
            ContentView(model: scanModel)
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1180, height: 720)
    }
}
