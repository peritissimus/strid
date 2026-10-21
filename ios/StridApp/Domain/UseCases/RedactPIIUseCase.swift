//
//  RedactPIIUseCase.swift
//  StridApp
//
//  Hexagonal architecture role: **use case** (application service).
//
//  Produces the masked version of a `Document`. Detection and redaction are
//  separate use cases so the UI can show a highlighted preview
//  (`DetectPIIUseCase`) before the user commits to redacting.
//

import Foundation

/// Redacts all PII in a document.
protocol RedactPIIUseCase {
    /// Masks every PII span in `document.content`.
    ///
    /// - Parameter document: The document to redact.
    /// - Returns: A `RedactedDocument` linked to `document.id`.
    func execute(document: Document) async -> RedactedDocument
}

/// Default implementation that delegates to `PIIDetectorPort.redact(_:)`.
final class RedactPIIUseCaseImpl: RedactPIIUseCase {
    /// The detection/redaction engine abstraction.
    private let detector: PIIDetectorPort

    /// - Parameter detector: Injected by `DIContainer`.
    init(detector: PIIDetectorPort) {
        self.detector = detector
    }

    func execute(document: Document) async -> RedactedDocument {
        let redactedContent = await detector.redact(document.content)
        return RedactedDocument(
            originalDocumentId: document.id,
            redactedContent: redactedContent
        )
    }
}
