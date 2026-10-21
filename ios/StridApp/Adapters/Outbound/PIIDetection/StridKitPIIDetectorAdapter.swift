//
//  StridKitPIIDetectorAdapter.swift
//  StridApp
//
//  Hexagonal architecture role: **outbound adapter** implementing
//  `PIIDetectorPort`.
//
//  This is the only place in the text flow that knows about StridKit's
//  `StridEngine`. It converts the engine's `PIIEntity` values into the app's
//  `DetectedPII` wrapper so the rest of the app can stay engine-agnostic and
//  tests can swap in a fake detector.
//

import Foundation
import StridKit

/// Bridges `PIIDetectorPort` to the StridKit detection engine.
final class StridKitPIIDetectorAdapter: PIIDetectorPort {
    /// A single engine instance reused for every call. Engine construction
    /// loads recognizer tables, so it is deliberately not per-request.
    private let engine = StridEngine()

    /// Runs the engine and wraps each result in `DetectedPII` (assigning a
    /// fresh `UUID` to each).
    ///
    /// The engine call itself is synchronous; the `async` signature exists to
    /// satisfy the port and to let callers hop off the main actor.
    func detect(in text: String) async -> [DetectedPII] {
        let entities = engine.detect(in: text)
        return entities.map { DetectedPII(entity: $0) }
    }

    /// Returns the engine's placeholder-substituted text.
    func redact(_ text: String) async -> String {
        engine.redact(text)
    }
}
