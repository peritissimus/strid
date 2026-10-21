//
//  RedactedDocument.swift
//  StridApp
//
//  Hexagonal architecture role: **domain entity**.
//
//  The output half of the text-redaction flow. `RedactPIIUseCase` takes a
//  `Document` and produces a `RedactedDocument`, which the UI displays side by
//  side with the original and which `ExportDocumentUseCase` writes to disk.
//  Keeping the redacted text in its own value type (rather than mutating
//  `Document`) preserves the original for comparison and history.
//

import Foundation

/// The redacted counterpart of a `Document`.
///
/// Only the redacted text is stored here; the original content stays on the
/// source `Document`, which is linked by `originalDocumentId`.
struct RedactedDocument: Identifiable, Equatable, Codable {
    /// Identifier of this redaction result (distinct from the source document).
    let id: UUID

    /// `Document.id` of the text that was redacted. Lets callers pair a result
    /// back with its input without holding a reference to the whole document.
    let originalDocumentId: UUID

    /// The text after every detected PII span has been replaced by the
    /// detector's placeholder tokens.
    let redactedContent: String

    /// When the redaction was performed.
    let redactedAt: Date

    /// Creates a redaction result.
    ///
    /// - Parameters:
    ///   - id: Identifier; a fresh `UUID` by default.
    ///   - originalDocumentId: The `Document.id` this result was derived from.
    ///   - redactedContent: The placeholder-substituted text.
    ///   - redactedAt: Timestamp of the redaction; defaults to now.
    init(
        id: UUID = UUID(),
        originalDocumentId: UUID,
        redactedContent: String,
        redactedAt: Date = Date()
    ) {
        self.id = id
        self.originalDocumentId = originalDocumentId
        self.redactedContent = redactedContent
        self.redactedAt = redactedAt
    }
}
