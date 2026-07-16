// Targie - Find similar media on macOS.
// Copyright (C) 2026 Lirui Yu

import Vision

private final class VisionRequestBox: @unchecked Sendable {
    let request: VNRequest

    init(_ request: VNRequest) {
        self.request = request
    }
}

enum CancellableVisionRequest {
    static func perform(
        _ request: VNRequest,
        handler: VNImageRequestHandler
    ) async throws {
        let box = VisionRequestBox(request)
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try handler.perform([box.request])
            try Task.checkCancellation()
        } onCancel: {
            box.request.cancel()
        }
    }
}
