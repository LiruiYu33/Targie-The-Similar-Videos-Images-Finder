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
@preconcurrency import Vision

/// Revision 2 feature prints are normalised vectors. Their Euclidean distance
/// gives cosine similarity as 1 - distance² / 2; negative cosine values provide
/// no similarity evidence. This is a visual score, not a match probability.
/// Regression fixtures cover compression/resizing as well as different content.
enum VisionFeatureSimilarity {
    static let requestRevision = VNGenerateImageFeaturePrintRequestRevision2

    enum ValidationError: Error {
        case incompatibleRevision
        case invalidDistance
    }

    static func score(distance: Double) throws -> Double {
        guard distance.isFinite, distance >= 0 else {
            throw ValidationError.invalidDistance
        }
        // Avoid overflow for invalid but finite distances outside the useful range.
        guard distance < 2 else { return 0 }
        return max(0, min(1, 1 - distance * distance / 2))
    }

    static func similarity(
        between first: VNFeaturePrintObservation,
        and second: VNFeaturePrintObservation
    ) throws -> Double {
        guard first.requestRevision == requestRevision,
              second.requestRevision == requestRevision else {
            throw ValidationError.incompatibleRevision
        }
        var distance: Float = 0
        try first.computeDistance(&distance, to: second)
        return try score(distance: Double(distance))
    }
}
