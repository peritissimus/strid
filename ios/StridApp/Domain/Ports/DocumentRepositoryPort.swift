//
//  DocumentRepositoryPort.swift
//  StridApp
//
//  Hexagonal architecture role: **outbound port** (driven-side interface).
//
//  Declares how the domain stores and retrieves plain-text `Document`s
//  without committing to a storage technology. Use cases depend on this
//  protocol; `InMemoryDocumentRepository` (an outbound adapter) implements it,
//  and tests can substitute a mock.
//

import Foundation

/// Storage abstraction for `Document`s, plus a notion of the single
/// "current" document the editor is working on.
protocol DocumentRepositoryPort {
    /// Stores a document by id, overwriting any previous version.
    ///
    /// - Parameter document: The document to persist.
    /// - Throws: Adapter-specific errors (the in-memory adapter never throws).
    func save(document: Document) async throws

    /// Fetches a previously saved document.
    ///
    /// - Parameter id: The `Document.id` to look up.
    /// - Returns: The document, or `nil` if none was saved under that id.
    /// - Throws: Adapter-specific errors.
    func load(id: UUID) async throws -> Document?

    /// Returns the document currently open in the editor, if any.
    func loadCurrent() async -> Document?

    /// Marks `document` as the current editor document (and stores it).
    ///
    /// - Parameter document: The document the user is now working on.
    func saveCurrent(_ document: Document) async

    /// Forgets the current editor document without deleting stored copies.
    func clearCurrent() async
}
