//
//  GetScannedDocumentsUseCase.swift
//  StridApp
//
//  Hexagonal architecture role: **use case** (application service).
//
//  Supplies the sidebar with the list of previously scanned documents.
//

import Foundation

/// Lists all `ScannedDocument`s.
protocol GetScannedDocumentsUseCase {
    /// Returns every scanned document, newest scan first.
    func execute() async -> [ScannedDocument]
}

/// Default implementation that reads from `ScannedDocumentRepositoryPort`.
final class GetScannedDocumentsUseCaseImpl: GetScannedDocumentsUseCase {
    /// Store holding the scanned documents.
    private let repository: ScannedDocumentRepositoryPort

    /// - Parameter repository: Injected by `DIContainer`.
    init(repository: ScannedDocumentRepositoryPort) {
        self.repository = repository
    }

    func execute() async -> [ScannedDocument] {
        await repository.getAllScannedDocuments()
    }
}
