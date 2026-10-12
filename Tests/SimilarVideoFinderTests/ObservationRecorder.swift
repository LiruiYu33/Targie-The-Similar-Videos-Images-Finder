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

import Foundation
import Observation

/// Records every change of an `@Observable` value, replacing the
/// `$property.sink` subscriptions tests used with ObservableObject.
///
/// `withObservationTracking` reports a change before the new value is
/// stored, so each callback records the value being replaced and re-arms
/// immediately; no change is coalesced or missed. `values` therefore holds
/// every value the property moved away from, in order, and `afterChange`
/// runs once the new value is in place.
@MainActor
final class ObservationRecorder<Value> {
    private let read: @MainActor () -> Value
    private let afterChange: (@MainActor () -> Void)?
    private var isCancelled = false
    private(set) var replacedValues: [Value] = []

    var changeCount: Int { replacedValues.count }

    /// Every value the property held, from the first observed one to the current one.
    var history: [Value] { replacedValues + [read()] }

    init(_ read: @escaping @MainActor () -> Value, afterChange: (@MainActor () -> Void)? = nil) {
        self.read = read
        self.afterChange = afterChange
        track()
    }

    func cancel() {
        isCancelled = true
    }

    private func track() {
        withObservationTracking {
            _ = read()
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isCancelled else { return }
                self.replacedValues.append(self.read())
                self.track()
                if let afterChange = self.afterChange {
                    Task { @MainActor in afterChange() }
                }
            }
        }
    }
}
