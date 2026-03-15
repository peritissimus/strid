import Foundation

/// Use case for retrieving redaction history
protocol GetRedactionHistoryUseCase {
    func execute() async -> [RedactionHistoryEntry]
    func getTotalCount() async -> Int
}

final class GetRedactionHistoryUseCaseImpl: GetRedactionHistoryUseCase {
    private let repository: RedactionHistoryRepositoryPort

    init(repository: RedactionHistoryRepositoryPort) {
        self.repository = repository
    }

    func execute() async -> [RedactionHistoryEntry] {
        await repository.getAllEntries()
    }

    func getTotalCount() async -> Int {
        await repository.getTotalRedactionCount()
    }
}
