//
//  DetectPIIUseCase.swift
//  StridApp
//
//  Hexagonal architecture role: **use case** (application service).
//
//  Scans a `Document` for PII without modifying it. This is the "preview"
//  step of the text flow: the UI highlights the returned entities so the user
//  can review what will be redacted before committing.
//

import Foundation

/// Finds PII in a document.
protocol DetectPIIUseCase {
    /// Runs detection over `document.content`.
    ///
    /// - Parameter document: The document to scan.
    /// - Returns: Every detected entity, in engine order.
    func execute(document: Document) async -> [DetectedPII]
}

/// Default implementation that delegates to `PIIDetectorPort`.
final class DetectPIIUseCaseImpl: DetectPIIUseCase {
    /// The detection engine abstraction (StridKit in production).
    private let detector: PIIDetectorPort

    /// - Parameter detector: Injected by `DIContainer`.
    init(detector: PIIDetectorPort) {
        self.detector = detector
    }

    func execute(document: Document) async -> [DetectedPII] {
        await detector.detect(in: document.content)
    }
}
