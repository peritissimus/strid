import Foundation

protocol SaveScannedDocumentUseCase {
    func execute(_ document: ScannedDocument) async throws
}

final class SaveScannedDocumentUseCaseImpl: SaveScannedDocumentUseCase {
    private let repository: ScannedDocumentRepositoryPort

    init(repository: ScannedDocumentRepositoryPort) {
        self.repository = repository
    }

    func execute(_ document: ScannedDocument) async throws {
        try await repository.save(document)
    }
}
