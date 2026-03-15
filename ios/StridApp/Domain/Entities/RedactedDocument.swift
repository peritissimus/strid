import Foundation

struct RedactedDocument: Identifiable, Equatable {
    let id: UUID
    let originalDocumentId: UUID
    let redactedContent: String
    let redactedAt: Date

    init(
        id: UUID = UUID(),
        originalDocumentId: UUID,
        redactedContent: String,
        redactedAt: Date = Date()
    ) {
        self.id = id
        self.originalDocumentId = originalDocumentId
        self.redactedContent = redactedContent
        self.redactedAt = redactedAt
    }
}
