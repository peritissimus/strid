//
//  DeleteScannedDocumentUseCase.swift
//  StridApp
//
//  Hexagonal architecture role: **use case** (application service).
//
//  Removes a scanned document from the sidebar's store. The use case is a
//  thin pass-through today, but keeping it as a separate seam means the view
//  model depends on an intention ("delete this scanned document") rather
//  than on a repository, and lets future rules (confirmation, cascading
//  deletes of history entries) be added without touching the UI.
//

import Foundation

/// Deletes a `ScannedDocument` by id.
protocol DeleteScannedDocumentUseCase {
    /// Removes the scanned document with the given id.
    ///
    /// - Parameter id: The `ScannedDocument.id` to delete.
    /// - Throws: Whatever the repository throws when removing the backing file.
    func execute(id: UUID) async throws
}

/// Default implementation that forwards to `ScannedDocumentRepositoryPort`.
final class DeleteScannedDocumentUseCaseImpl: DeleteScannedDocumentUseCase {
    /// Store that owns the scanned documents.
    private let repository: ScannedDocumentRepositoryPort

    /// - Parameter repository: Injected by `DIContainer`.
    init(repository: ScannedDocumentRepositoryPort) {
        self.repository = repository
    }

    func execute(id: UUID) async throws {
        try await repository.delete(id: id)
    }
}
