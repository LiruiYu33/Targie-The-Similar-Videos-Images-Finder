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

import AppKit
import Foundation

enum DeletionMode: Sendable {
    case trash
    case permanent
}

enum DeletionError: Error, Equatable {
    case fileMissing
    case operationFailed(String)

    func localizedDescription(_ language: AppLanguage) -> String {
        switch self {
        case .fileMissing: L10n.fileMissing(language)
        case .operationFailed(let message): L10n.deletionFailed(message, language)
        }
    }
}

protocol DeletionServicing: AnyObject, Sendable {
    func delete(url: URL, mode: DeletionMode) async throws
    @MainActor
    func reveal(_ url: URL)
    @MainActor
    func open(_ url: URL)
}

final class DeletionService: DeletionServicing {
    typealias DeleteOperation = @Sendable (URL, DeletionMode) throws -> Void

    private let worker: DeletionWorker

    init() {
        self.worker = DeletionWorker(operation: Self.deleteSynchronously)
    }

    init(operation: @escaping DeleteOperation) {
        self.worker = DeletionWorker(operation: operation)
    }

    func delete(url: URL, mode: DeletionMode) async throws {
        try Task.checkCancellation()
        try await worker.delete(url: url, mode: mode)
    }

    @MainActor
    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @MainActor
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private static func deleteSynchronously(url: URL, mode: DeletionMode) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw DeletionError.fileMissing }
        do {
            switch mode {
            case .trash:
                let resolved = url.standardizedFileURL
                var coordinatorError: NSError?
                let result = CoordinatedDeletionResult()
                NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: resolved, options: .forDeleting, error: &coordinatorError) { coordinatedURL in
                    do {
                        var resultingURL: NSURL?
                        try FileManager.default.trashItem(at: coordinatedURL, resultingItemURL: &resultingURL)
                    } catch {
                        result.error = error
                    }
                }
                if let error = coordinatorError {
                    throw DeletionError.operationFailed(error.localizedDescription)
                }
                if let error = result.error {
                    throw DeletionError.operationFailed(error.localizedDescription)
                }
            case .permanent:
                try FileManager.default.removeItem(at: url)
            }
        } catch let error as DeletionError {
            throw error
        } catch {
            throw DeletionError.operationFailed(error.localizedDescription)
        }
    }
}

private final class CoordinatedDeletionResult: @unchecked Sendable {
    var error: Error?
}

private final class DeletionWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.aaronyu.Targie.deletion", qos: .utility)
    private let operation: DeletionService.DeleteOperation

    init(operation: @escaping DeletionService.DeleteOperation) {
        self.operation = operation
    }

    func delete(url: URL, mode: DeletionMode) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [operation] in
                continuation.resume(with: Result {
                    try operation(url, mode)
                })
            }
        }
    }
}
