//
//  RedactionHistoryEntry.swift
//  StridApp
//
//  Hexagonal architecture role: **domain entity**.
//
//  An audit-trail record for the text-redaction flow. Each time the user
//  redacts a `Document`, `RecordRedactionUseCase` builds one of these and
//  hands it to `RedactionHistoryRepositoryPort`. The history screen reads them
//  back via `GetRedactionHistoryUseCase`.
//
//  Note: unlike `RedactionRecord` (the file-pipeline job record) this entry is
//  *not* `Codable`; the only shipping repository for it is in-memory.
//

import Foundation
import StridKit

/// Represents a single redaction operation in history.
///
/// Stores both the before and after text so the history UI can show a diff
/// without needing to re-run detection.
struct RedactionHistoryEntry: Identifiable, Equatable {
    /// Identifier of this history entry.
    let id: UUID

    /// `Document.id` of the document that was redacted.
    let documentId: UUID

    /// When the redaction happened.
    let timestamp: Date

    /// Full original text, kept for side-by-side comparison.
    let originalContent: String

    /// Full redacted text produced by the detector.
    let redactedContent: String

    /// Total number of PII spans that were detected (including duplicates of
    /// the same type).
    let entitiesFound: Int

    /// The distinct PII categories that appeared in this document. Order is
    /// unspecified because it is derived from a `Set` in the use case.
    let entityTypes: [PIIEntityType]

    /// Creates a history entry.
    ///
    /// - Parameters:
    ///   - id: Identifier; a fresh `UUID` by default.
    ///   - documentId: The redacted document's identifier.
    ///   - timestamp: When the redaction happened; defaults to now.
    ///   - originalContent: Text before redaction.
    ///   - redactedContent: Text after redaction.
    ///   - entitiesFound: Count of detected spans.
    ///   - entityTypes: Unique PII categories found.
    init(
        id: UUID = UUID(),
        documentId: UUID,
        timestamp: Date = Date(),
        originalContent: String,
        redactedContent: String,
        entitiesFound: Int,
        entityTypes: [PIIEntityType]
    ) {
        self.id = id
        self.documentId = documentId
        self.timestamp = timestamp
        self.originalContent = originalContent
        self.redactedContent = redactedContent
        self.entitiesFound = entitiesFound
        self.entityTypes = entityTypes
    }

    // MARK: - Display Helpers

    /// `timestamp` rendered for the history list using the user's locale,
    /// e.g. "Mar 15, 2024 at 2:30 PM".
    ///
    /// A new `DateFormatter` is built on every access; this is acceptable for
    /// the small number of rows shown in the history view.
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}
