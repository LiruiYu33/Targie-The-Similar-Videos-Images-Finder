// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import Foundation

enum ScanIntensity: String, CaseIterable, Identifiable, Sendable {
    case cool
    case balanced
    case fast

    static let defaultIntensity = ScanIntensity.balanced

    var id: String { rawValue }

    func metadataConcurrencyLimit(
        processorCount: Int,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    ) -> Int {
        thermallyAdjusted(base: metadataBase(processorCount: processorCount), thermalState: thermalState)
    }

    func hashConcurrencyLimit(
        processorCount: Int,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    ) -> Int {
        thermallyAdjusted(base: hashBase(processorCount: processorCount), thermalState: thermalState)
    }

    func comparisonConcurrencyLimit(
        processorCount: Int,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    ) -> Int {
        thermallyAdjusted(base: comparisonBase(processorCount: processorCount), thermalState: thermalState)
    }

    private func metadataBase(processorCount: Int) -> Int {
        switch self {
        case .cool:
            return min(2, max(1, processorCount / 4))
        case .balanced:
            return min(4, max(2, processorCount / 2))
        case .fast:
            return min(8, max(4, processorCount))
        }
    }

    private func hashBase(processorCount: Int) -> Int {
        switch self {
        case .cool:
            return min(2, max(1, processorCount / 4))
        case .balanced:
            return min(4, max(2, processorCount))
        case .fast:
            return min(6, max(3, processorCount))
        }
    }

    private func comparisonBase(processorCount: Int) -> Int {
        switch self {
        case .cool:
            return min(2, max(1, processorCount / 4))
        case .balanced:
            return min(6, max(2, processorCount / 2))
        case .fast:
            return min(8, max(4, processorCount))
        }
    }

    private func thermallyAdjusted(base: Int, thermalState: ProcessInfo.ThermalState) -> Int {
        switch thermalState {
        case .nominal:
            return max(1, base)
        case .fair:
            return max(1, min(base, base / 2))
        case .serious:
            return max(1, min(base, 2))
        case .critical:
            return 1
        @unknown default:
            return max(1, min(base, 2))
        }
    }
}
