import Foundation

protocol GetScannedDocumentsUseCase {
    func execute() async -> [ScannedDocument]
}

final class GetScannedDocumentsUseCaseImpl: GetScannedDocumentsUseCase {
    private let repository: ScannedDocumentRepositoryPort

    init(repository: ScannedDocumentRepositoryPort) {
        self.repository = repository
    }

    func execute() async -> [ScannedDocument] {
        await repository.getAllScannedDocuments()
    }
}
