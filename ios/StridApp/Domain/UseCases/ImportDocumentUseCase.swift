import Foundation

protocol ImportDocumentUseCase {
    func execute(content: String) async -> Document
}

final class ImportDocumentUseCaseImpl: ImportDocumentUseCase {
    private let repository: DocumentRepositoryPort

    init(repository: DocumentRepositoryPort) {
        self.repository = repository
    }

    func execute(content: String) async -> Document {
        let document = Document(content: content)
        await repository.saveCurrent(document)
        return document
    }
}
