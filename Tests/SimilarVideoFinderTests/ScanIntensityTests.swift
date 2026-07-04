// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import Foundation
import XCTest
@testable import SimilarVideoFinder

final class ScanIntensityTests: XCTestCase {
    func testComparisonConcurrencyProfilesForLargeProcessorCounts() {
        XCTAssertEqual(
            ScanIntensity.cool.comparisonConcurrencyLimit(processorCount: 12, thermalState: .nominal),
            2
        )
        XCTAssertEqual(
            ScanIntensity.balanced.comparisonConcurrencyLimit(processorCount: 12, thermalState: .nominal),
            6
        )
        XCTAssertEqual(
            ScanIntensity.fast.comparisonConcurrencyLimit(processorCount: 12, thermalState: .nominal),
            8
        )
    }

    func testThermalStateStillCapsFastMode() {
        XCTAssertEqual(
            ScanIntensity.fast.comparisonConcurrencyLimit(processorCount: 12, thermalState: .fair),
            4
        )
        XCTAssertEqual(
            ScanIntensity.fast.comparisonConcurrencyLimit(processorCount: 12, thermalState: .serious),
            2
        )
        XCTAssertEqual(
            ScanIntensity.fast.comparisonConcurrencyLimit(processorCount: 12, thermalState: .critical),
            1
        )
    }

    func testMetadataAndHashConcurrencyAreProfiledSeparately() {
        XCTAssertEqual(
            ScanIntensity.cool.metadataConcurrencyLimit(processorCount: 12, thermalState: .nominal),
            2
        )
        XCTAssertEqual(
            ScanIntensity.balanced.metadataConcurrencyLimit(processorCount: 12, thermalState: .nominal),
            4
        )
        XCTAssertEqual(
            ScanIntensity.fast.metadataConcurrencyLimit(processorCount: 12, thermalState: .nominal),
            8
        )

        XCTAssertEqual(
            ScanIntensity.cool.hashConcurrencyLimit(processorCount: 12, thermalState: .nominal),
            2
        )
        XCTAssertEqual(
            ScanIntensity.balanced.hashConcurrencyLimit(processorCount: 12, thermalState: .nominal),
            4
        )
        XCTAssertEqual(
            ScanIntensity.fast.hashConcurrencyLimit(processorCount: 12, thermalState: .nominal),
            6
        )
    }
}
