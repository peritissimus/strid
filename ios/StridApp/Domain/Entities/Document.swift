//
//  Document.swift
//  StridApp
//
//  Hexagonal architecture role: **domain entity**.
//
//  `Document` is the simplest unit of work in the text-redaction pipeline: a
//  blob of plain text plus the identity and timestamp needed to track it
//  through import, detection, redaction and history recording. It has no
//  dependencies on UI, storage or StridKit, so every layer (use cases, ports,
//  adapters, view models) can pass it around freely.
//

import Foundation

/// A plain-text document that the user has brought into the app and wants
/// scanned or redacted.
///
/// Conformances:
/// - `Identifiable` lets SwiftUI lists and dictionaries key on `id`.
/// - `Equatable` lets view models detect "did the current document change?".
/// - `Codable` lets `ScannedDocument` (which embeds a `Document`) be persisted
///   to disk as JSON by the outbound storage adapters.
struct Document: Identifiable, Equatable, Codable {
    /// Stable unique identifier. Generated at import time and referenced by
    /// `RedactedDocument.originalDocumentId` and `RedactionHistoryEntry.documentId`.
    let id: UUID

    /// The full, unredacted text content exactly as it was imported.
    let content: String

    /// When the document was created in the app (import / paste / sample load),
    /// not when the underlying file was authored.
    let createdAt: Date

    /// Creates a document.
    ///
    /// - Parameters:
    ///   - id: Identifier; a fresh `UUID` by default. Pass an explicit value
    ///     only when reconstructing a document from persistence or tests.
    ///   - content: The raw text to be scanned.
    ///   - createdAt: Creation timestamp; defaults to now.
    init(id: UUID = UUID(), content: String, createdAt: Date = Date()) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
    }
}
