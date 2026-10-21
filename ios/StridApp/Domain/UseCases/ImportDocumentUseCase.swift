//
//  ImportDocumentUseCase.swift
//  StridApp
//
//  Hexagonal architecture role: **use case** (application service).
//
//  Entry point of the text flow. Turns raw text (from a file, the clipboard
//  or a sample) into a `Document` and makes it the editor's current document.
//  Reading the bytes out of a file is the UI adapter's job; by the time this
//  use case runs the content is already a `String`.
//

import Foundation

/// Creates a `Document` from text and registers it as the current document.
protocol ImportDocumentUseCase {
    /// Wraps `content` in a new `Document` and stores it.
    ///
    /// - Parameter content: The imported plain text.
    /// - Returns: The newly created document (with a fresh id and timestamp).
    func execute(content: String) async -> Document
}

/// Default implementation that persists via `DocumentRepositoryPort`.
final class ImportDocumentUseCaseImpl: ImportDocumentUseCase {
    /// Store for documents and the "current document" slot.
    private let repository: DocumentRepositoryPort

    /// - Parameter repository: Injected by `DIContainer`.
    init(repository: DocumentRepositoryPort) {
        self.repository = repository
    }

    func execute(content: String) async -> Document {
        let document = Document(content: content)
        // saveCurrent both stores the document and marks it as current.
        await repository.saveCurrent(document)
        return document
    }
}
