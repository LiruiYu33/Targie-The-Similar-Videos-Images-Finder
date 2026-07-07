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

import XCTest
@testable import SimilarVideoFinder

final class LocalizationTests: XCTestCase {
    func testDefaultLanguageIsEnglishAndRawValuesRoundTrip() {
        XCTAssertEqual(AppLanguage.defaultLanguage, .english)
        XCTAssertEqual(AppLanguage(rawValue: "zh-Hans"), .simplifiedChinese)
        XCTAssertEqual(AppLanguage(rawValue: "ja"), .japanese)
        XCTAssertEqual(AppLanguage(rawValue: "ko"), .korean)
        XCTAssertEqual(AppLanguage.allCases.map(\.rawValue), ["en", "zh-Hans", "zh-Hant", "es", "fr", "ja", "ko"])
    }

    func testRepresentativeStringsSwitchLanguage() {
        XCTAssertEqual(L10n.chooseFolder(.english), "Choose Folder")
        XCTAssertEqual(L10n.chooseFolder(.simplifiedChinese), "选择文件夹")
        XCTAssertEqual(L10n.chooseFolder(.japanese), "フォルダを選択")
        XCTAssertEqual(L10n.chooseFolder(.korean), "폴더 선택")
        XCTAssertEqual(L10n.skippedFiles(3, .english), "Skipped 3 unreadable files")
        XCTAssertEqual(L10n.skippedFiles(3, .simplifiedChinese), "跳过 3 个无法读取的文件")
        XCTAssertEqual(L10n.skippedFiles(3, .japanese), "読み取れないファイルを 3 件スキップしました")
        XCTAssertEqual(L10n.skippedFiles(3, .korean), "읽을 수 없는 파일 3개 건너뜀")
        XCTAssertEqual(L10n.similarMedia(.english), "Similar Media")
        XCTAssertEqual(L10n.similarMedia(.simplifiedChinese), "相似媒体")
        XCTAssertEqual(L10n.similarMedia(.traditionalChinese), "相似媒體")
        XCTAssertEqual(L10n.similarMedia(.spanish), "Medios similares")
        XCTAssertEqual(L10n.similarMedia(.french), "Médias similaires")
        XCTAssertEqual(L10n.similarMedia(.japanese), "類似メディア")
        XCTAssertEqual(L10n.similarMedia(.korean), "유사한 미디어")
        XCTAssertEqual(L10n.pictureInPicture(.english), "Picture in Picture")
        XCTAssertEqual(L10n.pictureInPicture(.simplifiedChinese), "画中画")
        XCTAssertEqual(L10n.pictureInPicture(.japanese), "ピクチャ・イン・ピクチャ")
        XCTAssertEqual(L10n.pictureInPicture(.korean), "화면 속 화면")
    }

    func testScanProgressDetailShowsCacheHitContext() {
        let fingerprint = ScanProgress(
            stage: .hashing,
            fraction: 1,
            currentFile: "",
            discoveredCount: 5,
            cacheHits: 3,
            cacheTotal: 5,
            cacheKind: .fingerprint
        )
        XCTAssertEqual(L10n.scanProgressDetail(fingerprint, .english), "Fingerprint cache hits: 3 of 5")
        XCTAssertEqual(L10n.scanProgressDetail(fingerprint, .simplifiedChinese), "指纹缓存命中：3 / 5")
        XCTAssertEqual(L10n.scanProgressDetail(fingerprint, .japanese), "フィンガープリントキャッシュ命中：3 / 5")
        XCTAssertEqual(L10n.scanProgressDetail(fingerprint, .korean), "지문 캐시 적중: 3 / 5")

        let metadata = ScanProgress(
            stage: .readingMetadata,
            fraction: 0.4,
            currentFile: "clip.mov",
            discoveredCount: 5,
            cacheHits: 2,
            cacheTotal: 5,
            cacheKind: .metadata
        )
        XCTAssertEqual(L10n.scanProgressDetail(metadata, .english), "Metadata cache hits: 2 of 5 - clip.mov")
    }

    func testScanProgressDetailHidesZeroCacheHitsOutsidePairCachePhase() {
        let fingerprint = ScanProgress(
            stage: .hashing,
            fraction: 0.25,
            currentFile: "1252.mp4",
            discoveredCount: 2_096,
            cacheHits: 0,
            cacheTotal: 2_096,
            cacheKind: .fingerprint
        )

        XCTAssertEqual(L10n.scanProgressDetail(fingerprint, .english), "1252.mp4")
        XCTAssertEqual(L10n.scanProgressDetail(fingerprint, .simplifiedChinese), "1252.mp4")
    }

    func testComparisonSubProgressDetails() {
        let finding = ScanProgress(
            stage: .comparing,
            fraction: 0.1,
            currentFile: "clip.mp4",
            comparisonPhase: .findingCandidates,
            comparisonCompleted: 42,
            comparisonTotal: 100
        )
        XCTAssertEqual(
            L10n.scanProgressDetail(finding, .english),
            "Checked files: 42 of 100 - clip.mp4"
        )
        XCTAssertEqual(
            L10n.scanProgressDetail(finding, .simplifiedChinese),
            "已检查文件：42 / 100 - clip.mp4"
        )

        let checking = ScanProgress(
            stage: .comparing,
            fraction: 0.2,
            cacheHits: 90,
            cacheTotal: 100,
            cacheKind: .relation,
            comparisonPhase: .checkingPairCache
        )
        XCTAssertEqual(
            L10n.scanProgressDetail(checking, .english),
            "Checking pair cache: hits 90 of 100"
        )

        let comparing = ScanProgress(
            stage: .comparing,
            fraction: 0.6,
            currentFile: "miss.mp4",
            comparisonPhase: .comparingUncached,
            comparisonCompleted: 3,
            comparisonTotal: 8
        )
        XCTAssertEqual(
            L10n.scanProgressDetail(comparing, .english),
            "Comparing uncached pairs: 3 of 8 - miss.mp4"
        )
    }

    func testComparisonSubProgressTitleUsesCurrentPhase() {
        let finding = ScanProgress(
            stage: .comparing,
            fraction: 0.1,
            comparisonPhase: .findingCandidates
        )
        XCTAssertEqual(L10n.scanProgressTitle(finding, .english), "Finding candidate pairs")
        XCTAssertEqual(L10n.scanProgressTitle(finding, .japanese), "候補ペアを検索中")
        XCTAssertEqual(L10n.scanProgressTitle(finding, .korean), "후보 쌍 찾는 중")

        let checking = ScanProgress(
            stage: .comparing,
            fraction: 0.2,
            comparisonPhase: .checkingPairCache
        )
        XCTAssertEqual(L10n.scanProgressTitle(checking, .english), "Checking pair cache")
        XCTAssertEqual(L10n.scanProgressTitle(checking, .japanese), "ペアキャッシュを確認中")
        XCTAssertEqual(L10n.scanProgressTitle(checking, .korean), "쌍 캐시 확인 중")

        let comparing = ScanProgress(
            stage: .comparing,
            fraction: 0.6,
            comparisonPhase: .comparingUncached
        )
        XCTAssertEqual(L10n.scanProgressTitle(comparing, .english), "Comparing uncached pairs")
        XCTAssertEqual(L10n.scanProgressTitle(comparing, .japanese), "未キャッシュのペアを比較中")
        XCTAssertEqual(L10n.scanProgressTitle(comparing, .korean), "캐시되지 않은 쌍 비교 중")
    }
}
