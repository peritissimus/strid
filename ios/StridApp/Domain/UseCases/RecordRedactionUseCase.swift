import Foundation
import StridKit

/// Use case for recording a redaction operation in history
protocol RecordRedactionUseCase {
    func execute(
        document: Document,
        detectedEntities: [DetectedPII],
        redactedContent: String
    ) async -> RedactionHistoryEntry
}

final class RecordRedactionUseCaseImpl: RecordRedactionUseCase {
    private let repository: RedactionHistoryRepositoryPort

    init(repository: RedactionHistoryRepositoryPort) {
        self.repository = repository
    }

    func execute(
        document: Document,
        detectedEntities: [DetectedPII],
        redactedContent: String
    ) async -> RedactionHistoryEntry {
        let entityTypes = detectedEntities.map { $0.type }
        let uniqueTypes = Array(Set(entityTypes))

        let entry = RedactionHistoryEntry(
            documentId: document.id,
            originalContent: document.content,
            redactedContent: redactedContent,
            entitiesFound: detectedEntities.count,
            entityTypes: uniqueTypes
        )

        await repository.addEntry(entry)
        return entry
    }
}
