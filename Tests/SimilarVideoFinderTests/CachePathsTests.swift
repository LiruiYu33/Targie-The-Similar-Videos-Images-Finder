// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import XCTest
@testable import SimilarVideoFinder

final class CachePathsTests: XCTestCase {
    func testOverridePlacesHashAndThumbnailCachesUnderSameRoot() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TargieCacheOverride-\(UUID().uuidString)", isDirectory: true)
        let environment = [CachePaths.overrideEnvironmentKey: root.path]

        let resolvedRoot = CachePaths.rootDirectory(environment: environment)

        XCTAssertEqual(resolvedRoot, root.standardizedFileURL)
        XCTAssertEqual(
            CachePaths.hashDatabaseURL(environment: environment),
            root.standardizedFileURL.appendingPathComponent("hash_cache.sqlite")
        )
        XCTAssertEqual(
            CachePaths.thumbnailDirectoryURL(environment: environment),
            root.standardizedFileURL.appendingPathComponent("thumbnails", isDirectory: true)
        )
    }

    func testDefaultPathsUseTargieCachesDirectory() {
        let root = CachePaths.rootDirectory(environment: [:])

        XCTAssertEqual(root.lastPathComponent, "Targie")
        XCTAssertEqual(
            CachePaths.hashDatabaseURL(environment: [:]).deletingLastPathComponent(),
            root
        )
        XCTAssertEqual(
            CachePaths.thumbnailDirectoryURL(environment: [:]).deletingLastPathComponent(),
            root
        )
    }

    func testEmptyOrRelativeOverrideFallsBackToDefaultRoot() {
        let defaultRoot = CachePaths.rootDirectory(environment: [:])

        XCTAssertEqual(
            CachePaths.rootDirectory(environment: [CachePaths.overrideEnvironmentKey: "   "]),
            defaultRoot
        )
        XCTAssertEqual(
            CachePaths.rootDirectory(environment: [CachePaths.overrideEnvironmentKey: "relative/cache/path"]),
            defaultRoot
        )
    }
}
