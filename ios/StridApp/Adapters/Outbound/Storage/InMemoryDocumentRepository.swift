import Foundation

actor InMemoryDocumentRepository: DocumentRepositoryPort {
    private var documents: [UUID: Document] = [:]
    private var currentDocument: Document?

    func save(document: Document) async throws {
        documents[document.id] = document
    }

    func load(id: UUID) async throws -> Document? {
        documents[id]
    }

    func loadCurrent() async -> Document? {
        currentDocument
    }

    func saveCurrent(_ document: Document) async {
        currentDocument = document
        documents[document.id] = document
    }

    func clearCurrent() async {
        currentDocument = nil
    }
}
