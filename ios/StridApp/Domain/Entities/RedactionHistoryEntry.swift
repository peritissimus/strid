import Foundation
import StridKit

/// Represents a single redaction operation in history
struct RedactionHistoryEntry: Identifiable, Equatable {
    let id: UUID
    let documentId: UUID
    let timestamp: Date
    let originalContent: String
    let redactedContent: String
    let entitiesFound: Int
    let entityTypes: [PIIEntityType]

    init(
        id: UUID = UUID(),
        documentId: UUID,
        timestamp: Date = Date(),
        originalContent: String,
        redactedContent: String,
        entitiesFound: Int,
        entityTypes: [PIIEntityType]
    ) {
        self.id = id
        self.documentId = documentId
        self.timestamp = timestamp
        self.originalContent = originalContent
        self.redactedContent = redactedContent
        self.entitiesFound = entitiesFound
        self.entityTypes = entityTypes
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}
