import Foundation
import StridKit
@testable import StridApp

// MARK: - MockPIIDetector

/// Mock PII detector that returns configurable results for testing
final class MockPIIDetector: PIIDetectorPort {
    var detectResult: [DetectedPII] = []
    var redactResult: String = ""
    var detectCallCount = 0
    var redactCallCount = 0

    func detect(in text: String) async -> [DetectedPII] {
        detectCallCount += 1
        return detectResult
    }

    func redact(_ text: String) async -> String {
        redactCallCount += 1
        return redactResult
    }

    func reset() {
        detectResult = []
        redactResult = ""
        detectCallCount = 0
        redactCallCount = 0
    }
}

// MARK: - MockDocumentRepository

/// Mock document repository for testing
actor MockDocumentRepository: DocumentRepositoryPort {
    var documents: [UUID: Document] = [:]
    var saveCallCount = 0
    var getCallCount = 0

    func save(_ document: Document) async {
        saveCallCount += 1
        documents[document.id] = document
    }

    func getDocument(id: UUID) async -> Document? {
        getCallCount += 1
        return documents[id]
    }

    func getAllDocuments() async -> [Document] {
        documents.values.sorted { $0.createdAt > $1.createdAt }
    }

    func delete(id: UUID) async {
        documents.removeValue(forKey: id)
    }

    func reset() async {
        documents.removeAll()
        saveCallCount = 0
        getCallCount = 0
    }
}

// MARK: - MockScannedDocumentRepository

/// Mock scanned document repository for testing
actor MockScannedDocumentRepository: ScannedDocumentRepositoryPort {
    var documents: [UUID: ScannedDocument] = [:]
    var saveCallCount = 0
    var deleteCallCount = 0
    var searchCallCount = 0

    func save(_ document: ScannedDocument) async throws {
        saveCallCount += 1
        documents[document.id] = document
    }

    func getAllScannedDocuments() async -> [ScannedDocument] {
        documents.values.sorted { $0.scannedAt > $1.scannedAt }
    }

    func getScannedDocument(id: UUID) async -> ScannedDocument? {
        documents[id]
    }

    func delete(id: UUID) async throws {
        deleteCallCount += 1
        documents.removeValue(forKey: id)
    }

    func deleteAll() async throws {
        documents.removeAll()
    }

    func search(query: String) async -> [ScannedDocument] {
        searchCallCount += 1

        guard !query.isEmpty else {
            return await getAllScannedDocuments()
        }

        let lowercasedQuery = query.lowercased()

        return documents.values
            .filter { document in
                document.originalDocument.content.lowercased().contains(lowercasedQuery)
            }
            .sorted { $0.scannedAt > $1.scannedAt }
    }

    func reset() async {
        documents.removeAll()
        saveCallCount = 0
        deleteCallCount = 0
        searchCallCount = 0
    }
}

// MARK: - MockRedactionHistoryRepository

/// Mock redaction history repository for testing
actor MockRedactionHistoryRepository: RedactionHistoryRepositoryPort {
    var entries: [RedactionHistoryEntry] = []
    var saveCallCount = 0

    func saveRedactionEntry(_ entry: RedactionHistoryEntry) async {
        saveCallCount += 1
        entries.append(entry)
    }

    func getRedactionHistory() async -> [RedactionHistoryEntry] {
        entries.sorted { $0.timestamp > $1.timestamp }
    }

    func clearHistory() async {
        entries.removeAll()
    }

    func reset() async {
        entries.removeAll()
        saveCallCount = 0
    }
}

// MARK: - Test Helpers

extension MockPIIDetector {
    /// Configure detector to return specific PII entities
    func configureTo(detect entities: [DetectedPII], redact: String) {
        self.detectResult = entities
        self.redactResult = redact
    }

    /// Configure detector to find email in text
    func configureToDetectEmail(_ email: String) {
        let entity = TestFactories.makeDetectedPII(type: .email, text: email)
        self.detectResult = [entity]
        self.redactResult = "Redacted: <EMAIL>"
    }

    /// Configure detector to find multiple PII types
    func configureToDetectMultiplePII() {
        let email = TestFactories.makeDetectedPII(type: .email, text: "test@example.com")
        let phone = TestFactories.makeDetectedPII(type: .phone, text: "555-123-4567")
        self.detectResult = [email, phone]
        self.redactResult = "Redacted: <EMAIL>, <PHONE>"
    }
}
