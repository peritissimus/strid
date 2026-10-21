//
//  ScannedDocumentRepositoryPort.swift
//  StridApp
//
//  Hexagonal architecture role: **outbound port** (driven-side interface).
//
//  Persistence contract for `ScannedDocument` aggregates that back the
//  document sidebar. Used by the Get/Save/DeleteScannedDocument use cases and
//  implemented by `InMemoryScannedDocumentRepository` (which, despite its
//  name, also persists to disk).
//

import Foundation

/// Repository port for managing scanned documents with their full scan results
protocol ScannedDocumentRepositoryPort {
    /// Save a scanned document
    ///
    /// Inserts or replaces by `ScannedDocument.id`.
    ///
    /// - Parameter document: The aggregate to persist.
    /// - Throws: If the document cannot be encoded or written.
    func save(_ document: ScannedDocument) async throws

    /// Get all scanned documents, sorted by scan date (newest first)
    func getAllScannedDocuments() async -> [ScannedDocument]

    /// Get a specific scanned document by ID
    ///
    /// - Parameter id: The `ScannedDocument.id` to fetch.
    /// - Returns: The document, or `nil` if unknown.
    func getScannedDocument(id: UUID) async -> ScannedDocument?

    /// Delete a scanned document
    ///
    /// - Parameter id: The `ScannedDocument.id` to remove. Unknown ids are a no-op.
    /// - Throws: If the backing file cannot be removed.
    func delete(id: UUID) async throws

    /// Delete all scanned documents
    ///
    /// - Throws: If any backing file cannot be removed.
    func deleteAll() async throws

    /// Search scanned documents by content
    ///
    /// - Parameter query: Case-insensitive substring to look for in the
    ///   original text. An empty query returns every document.
    /// - Returns: Matches, newest first.
    func search(query: String) async -> [ScannedDocument]
}
