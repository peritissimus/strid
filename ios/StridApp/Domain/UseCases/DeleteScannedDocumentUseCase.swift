import Foundation

protocol DeleteScannedDocumentUseCase {
    func execute(id: UUID) async throws
}

final class DeleteScannedDocumentUseCaseImpl: DeleteScannedDocumentUseCase {
    private let repository: ScannedDocumentRepositoryPort

    init(repository: ScannedDocumentRepositoryPort) {
        self.repository = repository
    }

    func execute(id: UUID) async throws {
        try await repository.delete(id: id)
    }
}
