// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import Foundation

enum CachePaths {
    static let overrideEnvironmentKey = "TARGIE_CACHE_ROOT"

    /// The environment override keeps diagnostics and UI stress tests isolated
    /// from the user's production cache. Normal app launches use Caches/Targie.
    static func rootDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let overridePath = normalizedOverridePath(environment[overrideEnvironmentKey]) {
            return URL(fileURLWithPath: overridePath, isDirectory: true).standardizedFileURL
        }

        let cachesDirectory = (try? fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return cachesDirectory.appendingPathComponent("Targie", isDirectory: true)
    }

    static func hashDatabaseURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        rootDirectory(environment: environment, fileManager: fileManager)
            .appendingPathComponent("hash_cache.sqlite")
    }

    static func thumbnailDirectoryURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        rootDirectory(environment: environment, fileManager: fileManager)
            .appendingPathComponent("thumbnails", isDirectory: true)
    }

    private static func normalizedOverridePath(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        return expanded
    }
}
