import Foundation

/// In-memory implementation of ScannedDocumentRepositoryPort
/// Uses actor for thread-safe concurrent access
actor InMemoryScannedDocumentRepository: ScannedDocumentRepositoryPort {
    private var scannedDocuments: [UUID: ScannedDocument] = [:]

    func save(_ document: ScannedDocument) async throws {
        scannedDocuments[document.id] = document
    }

    func getAllScannedDocuments() async -> [ScannedDocument] {
        // Sort by scan date, newest first
        scannedDocuments.values.sorted { $0.scannedAt > $1.scannedAt }
    }

    func getScannedDocument(id: UUID) async -> ScannedDocument? {
        scannedDocuments[id]
    }

    func delete(id: UUID) async throws {
        scannedDocuments.removeValue(forKey: id)
    }

    func deleteAll() async throws {
        scannedDocuments.removeAll()
    }

    func search(query: String) async -> [ScannedDocument] {
        guard !query.isEmpty else {
            return await getAllScannedDocuments()
        }

        let lowercasedQuery = query.lowercased()

        return scannedDocuments.values
            .filter { document in
                document.originalDocument.content.lowercased().contains(lowercasedQuery)
            }
            .sorted { $0.scannedAt > $1.scannedAt }
    }
}
