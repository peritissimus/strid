//
//  InMemoryDocumentRepository.swift
//  StridApp
//
//  Hexagonal architecture role: **outbound adapter** implementing
//  `DocumentRepositoryPort`.
//
//  Volatile storage for plain-text `Document`s. Everything lives in the
//  actor's memory and is lost when the process exits; durable persistence of
//  the text flow is handled at the `ScannedDocument` level instead.
//
//  Implemented as an `actor` so concurrent calls from different tasks (e.g.
//  an import racing a redaction) serialise safely without manual locking.
//

import Foundation

/// Actor-backed, non-persistent `DocumentRepositoryPort`.
actor InMemoryDocumentRepository: DocumentRepositoryPort {
    /// All documents ever saved, keyed by `Document.id`.
    private var documents: [UUID: Document] = [:]

    /// The document the editor is currently showing, if any.
    private var currentDocument: Document?

    /// Stores `document`, replacing any existing entry with the same id.
    func save(document: Document) async throws {
        documents[document.id] = document
    }

    /// Looks up a document by id.
    func load(id: UUID) async throws -> Document? {
        documents[id]
    }

    /// Returns the current editor document.
    func loadCurrent() async -> Document? {
        currentDocument
    }

    /// Sets `document` as current and also records it in `documents`, so a
    /// later `load(id:)` finds it.
    func saveCurrent(_ document: Document) async {
        currentDocument = document
        documents[document.id] = document
    }

    /// Clears the current slot. The document stays in `documents`.
    func clearCurrent() async {
        currentDocument = nil
    }
}
