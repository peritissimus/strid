import Foundation

/// Repository port for managing scanned documents with their full scan results
protocol ScannedDocumentRepositoryPort {
    /// Save a scanned document
    func save(_ document: ScannedDocument) async throws

    /// Get all scanned documents, sorted by scan date (newest first)
    func getAllScannedDocuments() async -> [ScannedDocument]

    /// Get a specific scanned document by ID
    func getScannedDocument(id: UUID) async -> ScannedDocument?

    /// Delete a scanned document
    func delete(id: UUID) async throws

    /// Delete all scanned documents
    func deleteAll() async throws

    /// Search scanned documents by content
    func search(query: String) async -> [ScannedDocument]
}
