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

enum DisplayThresholdEditing {
    static let allowedRange = 0.60...1.0
    static let recommendedThreshold = 0.88
    private static let magnetLowerBound = recommendedThreshold - 0.04

    static func sliderValue(for proposedValue: Double) -> Double {
        let value = clamped(proposedValue)
        if value >= magnetLowerBound && value < recommendedThreshold {
            return recommendedThreshold
        }
        return value
    }

    static func thresholdValue(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withoutPercent = trimmed
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let percent = Double(withoutPercent), percent.isFinite else { return nil }

        let value = percent > 1 ? percent / 100 : percent
        return clamped(value)
    }

    static func text(for value: Double) -> String {
        let percent = clamped(value) * 100
        let rounded = (percent * 100).rounded() / 100
        var text = String(format: "%.2f", rounded)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }

    private static func clamped(_ value: Double) -> Double {
        min(allowedRange.upperBound, max(allowedRange.lowerBound, value))
    }
}

struct DisplayThresholdTextEditState: Equatable {
    var threshold: Double
    var isEditing = false
    var editText: String

    init(threshold: Double) {
        self.threshold = threshold
        self.editText = DisplayThresholdEditing.text(for: threshold)
    }

    var displayText: String {
        DisplayThresholdEditing.text(for: threshold)
    }

    mutating func beginEditing() {
        editText = displayText
        isEditing = true
    }

    mutating func commit(_ text: String) {
        if let value = DisplayThresholdEditing.thresholdValue(from: text) {
            threshold = value
        }
        editText = displayText
        isEditing = false
    }

    mutating func commitCurrentText() {
        commit(editText)
    }

    mutating func cancelEditing() {
        editText = displayText
        isEditing = false
    }

    mutating func syncThreshold(_ value: Double) {
        threshold = value
        if !isEditing {
            editText = displayText
        }
    }
}
