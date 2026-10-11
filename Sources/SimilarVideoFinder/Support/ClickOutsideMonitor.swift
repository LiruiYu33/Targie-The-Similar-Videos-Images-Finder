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

enum ClickOutsideDetector {
    static func isOutside(point: CGPoint, bounds: CGRect) -> Bool {
        !bounds.contains(point)
    }
}

struct ClickOutsideMonitor: NSViewRepresentable {
    let isActive: Bool
    let onClickOutside: () -> Void

    func makeNSView(context: Context) -> MonitoringView {
        let view = MonitoringView()
        view.update(isActive: isActive, onClickOutside: onClickOutside)
        return view
    }

    func updateNSView(_ nsView: MonitoringView, context: Context) {
        nsView.update(isActive: isActive, onClickOutside: onClickOutside)
    }

    static func dismantleNSView(_ nsView: MonitoringView, coordinator: ()) {
        nsView.stopMonitoring()
    }

    final class MonitoringView: NSView {
        private let eventMonitorStore = EventMonitorStore()
        private var isActive = false
        private var onClickOutside: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            refreshMonitor()
        }

        func update(isActive: Bool, onClickOutside: @escaping () -> Void) {
            self.isActive = isActive
            self.onClickOutside = onClickOutside
            refreshMonitor()
        }

        func stopMonitoring() {
            eventMonitorStore.stopMonitoring()
        }

        private func refreshMonitor() {
            stopMonitoring()
            guard isActive, window != nil else { return }

            let eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, self.isActive, event.window === self.window else { return event }
                let localPoint = self.convert(event.locationInWindow, from: nil)
                if ClickOutsideDetector.isOutside(point: localPoint, bounds: self.bounds) {
                    DispatchQueue.main.async { [weak self] in
                        guard self?.isActive == true else { return }
                        self?.onClickOutside?()
                    }
                }
                return event
            }
            eventMonitorStore.startMonitoring(eventMonitor)
        }
    }

}

/// Owns an `NSEvent` monitor and removes it when replaced or deallocated.
final class EventMonitorStore {
    private var eventMonitor: Any?

    deinit {
        stopMonitoring()
    }

    func startMonitoring(_ eventMonitor: Any?) {
        stopMonitoring()
        self.eventMonitor = eventMonitor
    }

    func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}
