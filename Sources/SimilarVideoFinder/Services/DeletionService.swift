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

@MainActor
protocol DeletionServicing: AnyObject {
    func delete(url: URL, mode: DeletionMode) async throws
    func reveal(_ url: URL)
    func open(_ url: URL)
}

@MainActor
final class DeletionService: DeletionServicing {
    func delete(url: URL, mode: DeletionMode) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw DeletionError.fileMissing }
        do {
            switch mode {
            case .trash:
                let resolved = url.standardizedFileURL
                var coordinatorError: NSError?
                var trashError: Error?
                NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: resolved, options: .forDeleting, error: &coordinatorError) { coordinatedURL in
                    do {
                        var resultingURL: NSURL?
                        try FileManager.default.trashItem(at: coordinatedURL, resultingItemURL: &resultingURL)
                    } catch {
                        trashError = error
                    }
                }
                if let error = coordinatorError {
                    throw DeletionError.operationFailed(error.localizedDescription)
                }
                if let error = trashError {
                    throw DeletionError.operationFailed(error.localizedDescription)
                }
            case .permanent:
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            throw DeletionError.operationFailed(error.localizedDescription)
        }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
