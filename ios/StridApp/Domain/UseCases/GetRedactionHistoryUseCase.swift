//
//  GetRedactionHistoryUseCase.swift
//  StridApp
//
//  Hexagonal architecture role: **use case** (application service).
//
//  Read-side of the text-redaction audit trail. Exposes the history list and
//  the running total that the UI shows as a badge.
//

import Foundation

/// Use case for retrieving redaction history
protocol GetRedactionHistoryUseCase {
    /// Returns every history entry, most recent first.
    func execute() async -> [RedactionHistoryEntry]

    /// Returns how many redactions have been recorded in total.
    func getTotalCount() async -> Int
}

/// Default implementation that reads from `RedactionHistoryRepositoryPort`.
final class GetRedactionHistoryUseCaseImpl: GetRedactionHistoryUseCase {
    /// Store holding the history entries.
    private let repository: RedactionHistoryRepositoryPort

    /// - Parameter repository: Injected by `DIContainer`.
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
