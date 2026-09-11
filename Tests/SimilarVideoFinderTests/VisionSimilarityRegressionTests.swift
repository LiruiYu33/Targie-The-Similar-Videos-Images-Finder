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

import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import Vision
import XCTest
@testable import SimilarVideoFinder

final class VisionSimilarityRegressionTests: XCTestCase {
    func testDistanceScoreHasUsefulRangeAndRejectsInvalidMeasurements() throws {
        XCTAssertEqual(try VisionFeatureSimilarity.score(distance: 0), 1)
        XCTAssertGreaterThan(try VisionFeatureSimilarity.score(distance: 0.5), 0.85)
        XCTAssertLessThan(try VisionFeatureSimilarity.score(distance: 1), 0.6)
        XCTAssertEqual(try VisionFeatureSimilarity.score(distance: 2), 0)
        XCTAssertEqual(try VisionFeatureSimilarity.score(distance: .greatestFiniteMagnitude), 0)
        for invalid in [Double.nan, .infinity, -.infinity, -0.01] {
            XCTAssertThrowsError(try VisionFeatureSimilarity.score(distance: invalid))
        }
        let scores = try stride(from: 0.0, through: 2.0, by: 0.1).map {
            try VisionFeatureSimilarity.score(distance: $0)
        }
        XCTAssertTrue(zip(scores, scores.dropFirst()).allSatisfy { $0 >= $1 })
    }

    func testDifferentImageContentDoesNotRegainInflatedScoresFromOldCaches() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("sample-1.bmp")
        let second = root.appendingPathComponent("sample-2.bmp")
        try write(fixture(.letterL), to: first, type: .bmp)
        try write(fixture(.letterU), to: second, type: .bmp)
        let items = try [first, second].map { try mediaItem($0) }
        let firstHash = try XCTUnwrap(ImagePerceptualHasher.hash(for: first))
        let secondHash = try XCTUnwrap(ImagePerceptualHasher.hash(for: second))
        XCTAssertLessThanOrEqual(firstHash.hammingDistance(to: secondHash), 18, "The negative fixture must reach Vision verification.")
        let cache = InMemoryHashCache()
        let oldVersion = "image-pair-relation-v3"
        await seedOldRelation(
            cache: cache, items: items, version: oldVersion,
            hashes: [items[0].id: Data(firstHash.hashBits), items[1].id: Data(secondHash.hashBits)]
        )

        let result = try await ImageSimilarityPipeline(cache: cache).process(images: items, threshold: DisplayThresholdEditing.recommendedThreshold) { _ in }
        XCTAssertTrue(result.relations.isEmpty, "This measured mismatch must fall below even the 60% storage floor.")
        let repeated = try await ImageSimilarityPipeline(cache: cache).process(images: items, threshold: DisplayThresholdEditing.recommendedThreshold) { _ in }
        XCTAssertEqual(repeated.relations, result.relations, "The new relation index must retain the corrected score.")
    }

    func testCompressionAndResizingRemainImageMatches() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for (index, content) in [Fixture.house, .letterL, .letterU].enumerated() {
            let original = root.appendingPathComponent("original-\(index).bmp")
            let compressed = root.appendingPathComponent("compressed-\(index).jpg")
            let resized = root.appendingPathComponent("resized-\(index).bmp")
            try write(fixture(content), to: original, type: .bmp)
            try write(fixture(content), to: compressed, type: .jpeg, quality: 0.6)
            try write(fixture(content, size: 256), to: resized, type: .bmp)
            let originalItem = try mediaItem(original)
            for (url, size) in [(compressed, 512), (resized, 256)] {
                let variant = try mediaItem(url, size: size)
                let items = [originalItem, variant]
                let result = try await ImageSimilarityPipeline().process(images: items, threshold: DisplayThresholdEditing.recommendedThreshold) { _ in }
                let relation = try XCTUnwrap(result.relations.first)
                print("CALIBRATION image positive \(index) \(url.pathExtension) \(size): \(relation.score)")
                XCTAssertGreaterThanOrEqual(relation.score, DisplayThresholdEditing.recommendedThreshold)
                XCTAssertTrue(relation.evidence.contains(.similarFrames))
                XCTAssertFalse(relation.evidence.contains(.identicalContentHash))
                XCTAssertEqual(SimilarityGrouper.groups(items: items, relations: result.relations, threshold: DisplayThresholdEditing.recommendedThreshold).count, 1)
            }
        }
    }

    func testExtractionPinsRevisionAndRejectsIncompatibleObservations() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("sample.bmp")
        try write(fixture(.house), to: url, type: .bmp)
        let current = try await ImageFeatureExtractor().feature(for: url)
        XCTAssertEqual(current.observation.requestRevision, VNGenerateImageFeaturePrintRequestRevision2)
        XCTAssertEqual(try ImageFeatureExtractor().similarity(between: current, and: current), 1, accuracy: 0.001)
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision1
        try await CancellableVisionRequest.perform(request, handler: VNImageRequestHandler(cgImage: fixture(.house)))
        let legacy = try XCTUnwrap(request.results?.first)
        XCTAssertThrowsError(try VisionFeatureSimilarity.similarity(between: current.observation, and: legacy))
        XCTAssertThrowsError(try VisionFeatureSimilarity.similarity(between: legacy, and: legacy))
    }

    func testDifferentImageContentsStayBelowTheRecommendedThreshold() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let urls = ["sample-1.bmp", "sample-2.bmp", "sample-3.bmp"].map { root.appendingPathComponent($0) }
        for (content, url) in zip([Fixture.letterL, .letterU, .house], urls) {
            try write(fixture(content), to: url, type: .bmp)
        }
        let items = try urls.map { try mediaItem($0) }
        let extractor = ImageFeatureExtractor()
        for firstIndex in 0..<items.count {
            for secondIndex in (firstIndex + 1)..<items.count {
                let first = items[firstIndex], second = items[secondIndex]
                let firstHash = try XCTUnwrap(ImagePerceptualHasher.hash(for: first.url))
                let secondHash = try XCTUnwrap(ImagePerceptualHasher.hash(for: second.url))
                let firstFeature = try await extractor.feature(for: first.url)
                let secondFeature = try await extractor.feature(for: second.url)
                let visual = try extractor.similarity(between: firstFeature, and: secondFeature)
                let score = SimilarityScorer.score(first, second, hashesMatch: false,
                    perceptualSimilarity: firstHash.similarity(to: secondHash), frameSimilarity: visual,
                    requiresVisualVerification: true)
                print("CALIBRATION image negative \(firstIndex)-\(secondIndex): visual=\(visual) final=\(score.score)")
                XCTAssertLessThan(score.score, DisplayThresholdEditing.recommendedThreshold)
                XCTAssertLessThanOrEqual(score.score, visual + 0.05)
            }
        }
        let result = try await ImageSimilarityPipeline().process(images: items, threshold: DisplayThresholdEditing.recommendedThreshold) { _ in }
        XCTAssertTrue(SimilarityGrouper.groups(items: items, relations: result.relations, threshold: DisplayThresholdEditing.recommendedThreshold).isEmpty)
    }

    func testImageFeatureCacheReextractsPreviousAlgorithmVersion() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("sample.bmp")
        try write(fixture(.house), to: url, type: .bmp)
        let item = try mediaItem(url)
        let feature = try await ImageFeatureExtractor().feature(for: url)
        let cache = InMemoryHashCache()
        await cache.upsertImageFeature(
            filePath: url.path, fileSize: item.fileSize, modifiedAt: item.modifiedAt,
            algorithmVersion: "vision-image-feature-v2",
            featureData: try ImageFeatureSerializer.serialize(feature.observation)
        )
        let extractor = CountingFixedImageExtractor(feature: feature)
        let firstCache = ImageFeatureCache(extractor: extractor, persistentCache: cache)
        let secondCache = ImageFeatureCache(extractor: extractor, persistentCache: cache)
        _ = try await firstCache.feature(for: url)
        _ = try await secondCache.feature(for: url)
        let count = await extractor.extractionCount
        XCTAssertEqual(count, 1, "Legacy features must be re-extracted once, then reused under the explicit revision.")
    }

    func testVideoFrameVerificationRejectsDifferentContentAndOldRelations() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstImage = root.appendingPathComponent("sample-1.bmp")
        let secondImage = root.appendingPathComponent("sample-2.bmp")
        let first = root.appendingPathComponent("sample-1.mp4")
        let second = root.appendingPathComponent("sample-2.mp4")
        try write(fixture(.letterL), to: firstImage, type: .bmp)
        try write(fixture(.letterU), to: secondImage, type: .bmp)
        for (image, video) in [(firstImage, first), (secondImage, second)] {
            try runFFmpeg(["-loop", "1", "-i", image.path, "-t", "2", "-r", "12", "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", "-y", video.path])
        }
        let items = try [first, second].map { try mediaItem($0, kind: .video) }
        let maybeFirstHash = try await PerceptualHasher.hash(for: first)
        let maybeSecondHash = try await PerceptualHasher.hash(for: second)
        let firstHash = try XCTUnwrap(maybeFirstHash), secondHash = try XCTUnwrap(maybeSecondHash)
        XCTAssertLessThanOrEqual(firstHash.hammingDistance(to: secondHash), SimilarityPipeline.perceptualMaxDistance)
        XCTAssertLessThan(firstHash.similarity(to: secondHash), 0.92, "The negative fixture must reach frame verification.")
        let cache = InMemoryHashCache()
        await seedOldRelation(
            cache: cache, items: items, version: "video-pair-relation-v3-frame",
            hashes: [items[0].id: Data(firstHash.hashBits), items[1].id: Data(secondHash.hashBits)]
        )
        let result = try await SimilarityPipeline(cache: cache, usesFrameVerification: true).process(videos: items, threshold: DisplayThresholdEditing.recommendedThreshold) { _ in }
        let visual = try await FrameFeatureExtractor().similarity(between: first, and: second)
        let measuredScore = SimilarityScorer.score(items[0], items[1], hashesMatch: false,
            perceptualSimilarity: firstHash.similarity(to: secondHash), frameSimilarity: visual,
            requiresVisualVerification: true)
        print("CALIBRATION video negative: visual=\(String(describing: visual)) final=\(measuredScore.score)")
        XCTAssertLessThan(measuredScore.score, 0.72)
        XCTAssertTrue(SimilarityGrouper.groups(items: items, relations: result.relations, threshold: 0.72).isEmpty)

        // Even a colliding fingerprint must reach real frame verification in
        // deep mode. Injecting pHash isolates the formerly skipped >= .92 path.
        let colliding = SimilarityPipeline(usesFrameVerification: true, perceptualHashProvider: { _, id in
            VideoPerceptualHash(videoID: id, hashBits: [UInt8](repeating: 0, count: 8))
        })
        let collisionResult = try await colliding.process(videos: items, threshold: DisplayThresholdEditing.recommendedThreshold) { _ in }
        XCTAssertTrue(SimilarityGrouper.groups(items: items, relations: collisionResult.relations, threshold: 0.72).isEmpty, "A pHash collision cannot override visibly different frames.")
    }

    func testReencodedVideoRetainsFrameSimilarityAndPipelineMatch() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("sample-1.mp4")
        let reencoded = root.appendingPathComponent("sample-2.mp4")
        try runFFmpeg(["-f", "lavfi", "-i", "testsrc=size=512x512:rate=12", "-t", "2", "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", "-y", original.path])
        try runFFmpeg(["-i", original.path, "-c:v", "libx264", "-crf", "28", "-pix_fmt", "yuv420p", "-y", reencoded.path])
        let extractor = FrameFeatureExtractor()
        let first = try await extractor.features(for: original)
        let second = try await extractor.features(for: reencoded)
        XCTAssertEqual(first.observations.compactMap { $0 }.count, FrameFeatureExtractor.samplePositions.count)
        XCTAssertTrue((first.observations + second.observations).compactMap { $0 }.allSatisfy {
            $0.requestRevision == VNGenerateImageFeaturePrintRequestRevision2
        })
        let maybeSimilarity = try await extractor.similarity(between: first, and: second)
        XCTAssertGreaterThan(try XCTUnwrap(maybeSimilarity), 0.95)
        let items = try [original, reencoded].map { try mediaItem($0, kind: .video) }
        let result = try await SimilarityPipeline(usesFrameVerification: true).process(videos: items, threshold: DisplayThresholdEditing.recommendedThreshold) { _ in }
        let relation = try XCTUnwrap(result.relations.first)
        print("CALIBRATION video reencoded: \(relation.score)")
        XCTAssertTrue(relation.evidence.contains(.similarFrames), "A high pHash must no longer skip deep verification.")
        XCTAssertFalse(relation.evidence.contains(.identicalContentHash))
        XCTAssertEqual(SimilarityGrouper.groups(items: items, relations: result.relations, threshold: DisplayThresholdEditing.recommendedThreshold).count, 1)

        let resized = root.appendingPathComponent("different-name.mp4")
        try runFFmpeg(["-i", original.path, "-vf", "scale=256:256", "-c:v", "libx264", "-crf", "28", "-pix_fmt", "yuv420p", "-y", resized.path])
        let resizedItems = [items[0], try mediaItem(resized, kind: .video, size: 256)]
        let originalPHash = try await PerceptualHasher.hash(for: original)
        let resizedPHash = try await PerceptualHasher.hash(for: resized)
        let resizedFeatures = try await extractor.features(for: resized)
        let resizedVision = try await extractor.similarity(between: first, and: resizedFeatures)
        print("CALIBRATION video resized inputs: sizes=\(resizedItems.map(\.fileSize)) pHash=\(try XCTUnwrap(originalPHash).hammingDistance(to: XCTUnwrap(resizedPHash))) vision=\(String(describing: resizedVision))")
        let resizedResult = try await SimilarityPipeline(usesFrameVerification: true).process(videos: resizedItems, threshold: DisplayThresholdEditing.recommendedThreshold) { _ in }
        let resizedRelation = try XCTUnwrap(resizedResult.relations.first)
        print("CALIBRATION video resized and renamed: \(resizedRelation.score)")
        XCTAssertTrue(resizedRelation.evidence.contains(.similarFrames))
        XCTAssertEqual(SimilarityGrouper.groups(items: resizedItems, relations: resizedResult.relations, threshold: DisplayThresholdEditing.recommendedThreshold).count, 1)
    }

    private func seedOldRelation(cache: InMemoryHashCache, items: [MediaItem], version: String, hashes: [UUID: Data]) async {
        await cache.upsertPairRelation(
            first: items[0], second: items[1], algorithmVersion: version,
            relation: SimilarityRelation(firstID: items[0].id, secondID: items[1].id, score: 0.99, evidence: [.similarFrames])
        )
        await cache.upsertScanRelationIndex(
            signature: ScanRelationSignatureBuilder.signature(items: items, hashes: hashes, algorithmVersion: version),
            mediaKind: items[0].kind, algorithmVersion: version, fileCount: 2, candidateCount: 1,
            relations: [CachedScanRelation(firstPath: items[0].url.path, secondPath: items[1].url.path, score: 0.99, evidence: [.similarFrames])]
        )
    }

    private func makeDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VisionRegression-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func mediaItem(_ url: URL, kind: MediaKind = .image, size: Int = 512) throws -> MediaItem {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return MediaItem(kind: kind, url: url, fileSize: Int64(try XCTUnwrap(values.fileSize)), duration: kind == .video ? 2 : nil, width: size, height: size, modifiedAt: values.contentModificationDate, thumbnailData: nil)
    }

    private func write(_ image: CGImage, to url: URL, type: UTType, quality: Double = 0.8) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func runFFmpeg(_ arguments: [String]) throws {
        let executable = try TestMediaTools.ffmpeg()
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-loglevel", "error"] + arguments
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private enum Fixture { case letterL, letterU, house }

    private func fixture(_ fixture: Fixture, size: Int = 512) -> CGImage {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: Double(size) / 512, y: Double(size) / 512)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        if fixture != .house {
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 400, nil)
            let text = NSAttributedString(string: fixture == .letterL ? "L" : "U", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            context.textPosition = CGPoint(x: 110, y: 110)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
        } else {
            context.setFillColor(CGColor(red: 0.35, green: 0.65, blue: 0.9, alpha: 1))
            context.fill(CGRect(x: 0, y: 200, width: 512, height: 312))
            context.setFillColor(CGColor(red: 0.15, green: 0.5, blue: 0.22, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 200))
            context.setFillColor(CGColor(red: 1, green: 0.8, blue: 0.1, alpha: 1))
            context.fillEllipse(in: CGRect(x: 340, y: 350, width: 95, height: 95))
            context.setFillColor(CGColor(red: 0.7, green: 0.25, blue: 0.15, alpha: 1))
            context.fill(CGRect(x: 100, y: 110, width: 180, height: 180))
            context.setFillColor(CGColor(gray: 0.12, alpha: 1))
            context.move(to: CGPoint(x: 60, y: 290))
            context.addLine(to: CGPoint(x: 190, y: 420))
            context.addLine(to: CGPoint(x: 320, y: 290))
            context.closePath()
            context.fillPath()
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 120, y: 210, width: 50, height: 50))
            context.fill(CGRect(x: 210, y: 210, width: 50, height: 50))
        }
        return context.makeImage()!
    }
}

private actor CountingFixedImageExtractor: ImageFeatureExtracting {
    let feature: ImageFeature
    private(set) var extractionCount = 0

    init(feature: ImageFeature) { self.feature = feature }

    func feature(for url: URL) async throws -> ImageFeature {
        extractionCount += 1
        return feature
    }

    nonisolated func similarity(between first: ImageFeature, and second: ImageFeature) throws -> Double {
        try ImageFeatureExtractor().similarity(between: first, and: second)
    }
}
