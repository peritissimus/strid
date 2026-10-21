//
//  SaveScannedDocumentUseCase.swift
//  StridApp
//
//  Hexagonal architecture role: **use case** (application service).
//
//  Persists a `ScannedDocument` so it reappears in the sidebar on the next
//  launch. Called by the document-list view model after a scan completes.
//

import Foundation

/// Saves (inserts or replaces) a `ScannedDocument`.
protocol SaveScannedDocumentUseCase {
    /// Persists the given scanned document.
    ///
    /// - Parameter document: The aggregate to store.
    /// - Throws: Whatever the repository throws while encoding or writing.
    func execute(_ document: ScannedDocument) async throws
}

/// Default implementation that forwards to `ScannedDocumentRepositoryPort`.
final class SaveScannedDocumentUseCaseImpl: SaveScannedDocumentUseCase {
    /// Store that owns the scanned documents.
    private let repository: ScannedDocumentRepositoryPort

    /// - Parameter repository: Injected by `DIContainer`.
    init(repository: ScannedDocumentRepositoryPort) {
        self.repository = repository
    }

    func execute(_ document: ScannedDocument) async throws {
        try await repository.save(document)
    }
}
