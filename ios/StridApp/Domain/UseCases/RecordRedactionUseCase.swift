//
//  RecordRedactionUseCase.swift
//  StridApp
//
//  Hexagonal architecture role: **use case** (application service).
//
//  Write-side of the text-redaction audit trail. After the UI has detected
//  and redacted a document it calls this use case to summarise the operation
//  into a `RedactionHistoryEntry` and persist it.
//

import Foundation
import StridKit

/// Use case for recording a redaction operation in history
protocol RecordRedactionUseCase {
    /// Builds and stores a history entry for one redaction.
    ///
    /// - Parameters:
    ///   - document: The original document that was redacted.
    ///   - detectedEntities: The entities found by `DetectPIIUseCase`.
    ///   - redactedContent: The masked text produced by `RedactPIIUseCase`.
    /// - Returns: The entry that was stored, so the UI can show it immediately.
    func execute(
        document: Document,
        detectedEntities: [DetectedPII],
        redactedContent: String
    ) async -> RedactionHistoryEntry
}

/// Default implementation that writes to `RedactionHistoryRepositoryPort`.
final class RecordRedactionUseCaseImpl: RecordRedactionUseCase {
    /// Store for history entries.
    private let repository: RedactionHistoryRepositoryPort

    /// - Parameter repository: Injected by `DIContainer`.
    init(repository: RedactionHistoryRepositoryPort) {
        self.repository = repository
    }

    func execute(
        document: Document,
        detectedEntities: [DetectedPII],
        redactedContent: String
    ) async -> RedactionHistoryEntry {
        // Collapse the per-span list down to the distinct categories found.
        // Going through a Set means the resulting order is arbitrary.
        let entityTypes = detectedEntities.map { $0.type }
        let uniqueTypes = Array(Set(entityTypes))

        let entry = RedactionHistoryEntry(
            documentId: document.id,
            originalContent: document.content,
            redactedContent: redactedContent,
            entitiesFound: detectedEntities.count,   // total spans, not unique types
            entityTypes: uniqueTypes
        )

        await repository.addEntry(entry)
        return entry
    }
}
