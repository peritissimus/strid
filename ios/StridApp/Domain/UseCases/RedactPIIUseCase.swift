import Foundation

protocol RedactPIIUseCase {
    func execute(document: Document) async -> RedactedDocument
}

final class RedactPIIUseCaseImpl: RedactPIIUseCase {
    private let detector: PIIDetectorPort

    init(detector: PIIDetectorPort) {
        self.detector = detector
    }

    func execute(document: Document) async -> RedactedDocument {
        let redactedContent = await detector.redact(document.content)
        return RedactedDocument(
            originalDocumentId: document.id,
            redactedContent: redactedContent
        )
    }
}
