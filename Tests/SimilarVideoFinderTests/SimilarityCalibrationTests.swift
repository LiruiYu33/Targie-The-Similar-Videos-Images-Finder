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
import ImageIO
import XCTest
@testable import SimilarVideoFinder

/// Opt-in calibration dump. Set TARGIE_CALIBRATION_DIR to a folder with
/// `orig/<name>.jpg` and `var/<name>-<variant>.*`; writes raw signals to
/// TARGIE_CALIBRATION_OUT as TSV (kind, a, b, vision, phash, score).
final class SimilarityCalibrationTests: XCTestCase {
    func testDumpCalibrationSignals() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["TARGIE_CALIBRATION_DIR"], let out = env["TARGIE_CALIBRATION_OUT"] else {
            throw XCTSkip("Set TARGIE_CALIBRATION_DIR and TARGIE_CALIBRATION_OUT to run calibration.")
        }
        let root = URL(fileURLWithPath: dir)
        let fm = FileManager.default
        let originals = try fm.contentsOfDirectory(at: root.appendingPathComponent("orig"), includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let variants = try fm.contentsOfDirectory(at: root.appendingPathComponent("var"), includingPropertiesForKeys: nil)
        let extractor = ImageFeatureExtractor()

        struct Entry { let item: MediaItem; let hash: ImagePerceptualHash; let feature: ImageFeature }
        func entry(_ url: URL) async throws -> Entry? {
            guard let hash = try ImagePerceptualHasher.hash(for: url) else { return nil }
            let feature = try await extractor.feature(for: url)
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            let dims = CGImageSourceCreateWithURL(url as CFURL, nil)
                .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
            let item = MediaItem(kind: .image, url: url, fileSize: size, duration: nil,
                                 width: dims?[kCGImagePropertyPixelWidth] as? Int ?? 0,
                                 height: dims?[kCGImagePropertyPixelHeight] as? Int ?? 0,
                                 modifiedAt: nil, thumbnailData: nil)
            return Entry(item: item, hash: hash, feature: feature)
        }
        func row(_ kind: String, _ a: Entry, _ b: Entry) throws -> String {
            let vision = try extractor.similarity(between: a.feature, and: b.feature)
            let phash = a.hash.similarity(to: b.hash)
            let score = SimilarityScorer.score(a.item, b.item, hashesMatch: false, perceptualSimilarity: phash,
                                               frameSimilarity: vision, requiresVisualVerification: true).score
            return "\(kind)\t\(a.item.url.lastPathComponent)\t\(b.item.url.lastPathComponent)\t\(vision)\t\(phash)\t\(score)\t\(a.item.width)"
        }

        var entries: [String: Entry] = [:]
        for url in originals {
            entries[url.deletingPathExtension().lastPathComponent] = try await entry(url)
        }
        var lines = ["kind\ta\tb\tvision\tphash\tscore\twidth"]
        for url in variants {
            let base = String(url.deletingPathExtension().lastPathComponent.split(separator: "-").first ?? "")
            guard let original = entries[base], let variant = try await entry(url) else { continue }
            lines.append(try row("pos", original, variant))
        }
        let keys = entries.keys.sorted()
        for i in keys.indices {
            for j in keys.indices where j > i {
                lines.append(try row("neg", entries[keys[i]]!, entries[keys[j]]!))
            }
        }
        try lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
    }
}
