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
import XCTest

/// Resolve the media fixture dependency without assuming a Homebrew architecture.
enum TestMediaTools {
    static func ffmpeg() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin"]
        let candidates = directories.map { URL(fileURLWithPath: $0).appendingPathComponent("ffmpeg") }
        if let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return executable
        }
        if environment["CI"] == "true" {
            throw NSError(domain: "TargieTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "FFmpeg is required in CI; video regression tests must not be skipped."
            ])
        }
        throw XCTSkip("ffmpeg is unavailable")
    }
}
