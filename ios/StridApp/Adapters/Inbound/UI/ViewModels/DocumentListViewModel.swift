//
//  DocumentListViewModel.swift
//  StridApp
//
//  View model for the sidebar + detail text-scanner flow (`DocumentSidebarView`,
//  `DocumentDetailView`, `EmptyDetailView`, `ScannedDocumentResultsView`,
//  `SamplePickerSheet`). It owns the list of persisted `ScannedDocument`s, the
//  current selection, the search query, and the derived `AppNavigationState`
//  that tells the detail pane what to render. Built by
//  `DIContainer.makeDocumentListViewModel()`.
//
//  Unlike `DocumentViewModel`, there is no "loaded but not scanned" state here:
//  any text that comes in is scanned immediately and saved as a record.
//

import Foundation
import SwiftUI

/// Manages the list of scanned documents and which one is selected.
///
/// `@MainActor` because SwiftUI reads every property, and `@Observable` so
/// views only re-render for the properties they depend on.
@MainActor
@Observable
final class DocumentListViewModel {
    // MARK: - State

    /// All persisted scanned documents, newest first as returned by the
    /// repository. Reloaded after every save and delete.
    var scannedDocuments: [ScannedDocument] = []

    /// Id of the document highlighted in the sidebar. Bound directly to the
    /// sidebar `List(selection:)`, so it can change without going through
    /// `selectDocument(_:)`.
    var selectedDocumentId: UUID?

    /// What the detail pane should show. Recomputed by
    /// `updateNavigationState()` and set explicitly to `.scanning` during a
    /// scan.
    var navigationState: AppNavigationState = .empty

    /// Live text from the sidebar search field. Filters `filteredDocuments`.
    var searchQuery: String = ""

    // Sheets

    /// Whether the sample-document picker sheet is presented. Set by the
    /// sidebar's "+" menu and by the welcome screen.
    var showingSamplePicker = false

    // MARK: - Use Cases

    /// Loads all saved scanned documents.
    private let getScannedDocumentsUseCase: GetScannedDocumentsUseCase
    /// Persists a new scanned document.
    private let saveScannedDocumentUseCase: SaveScannedDocumentUseCase
    /// Removes a scanned document by id.
    private let deleteScannedDocumentUseCase: DeleteScannedDocumentUseCase
    /// Turns raw text into a `Document` entity.
    private let importUseCase: ImportDocumentUseCase
    /// Finds PII spans in a document.
    private let detectUseCase: DetectPIIUseCase
    /// Produces the redacted copy of a document.
    private let redactUseCase: RedactPIIUseCase
    /// Appends an entry to the redaction history after a scan.
    private let recordRedactionUseCase: RecordRedactionUseCase
    /// Writes a redacted document to a shareable file URL.
    private let exportDocumentUseCase: ExportDocumentUseCase

    /// Dependency-injected initialiser. Every collaborator is a protocol so
    /// the tests in `DocumentListViewModelTests` can substitute mocks.
    init(
        getScannedDocumentsUseCase: GetScannedDocumentsUseCase,
        saveScannedDocumentUseCase: SaveScannedDocumentUseCase,
        deleteScannedDocumentUseCase: DeleteScannedDocumentUseCase,
        importUseCase: ImportDocumentUseCase,
        detectUseCase: DetectPIIUseCase,
        redactUseCase: RedactPIIUseCase,
        recordRedactionUseCase: RecordRedactionUseCase,
        exportDocumentUseCase: ExportDocumentUseCase
    ) {
        self.getScannedDocumentsUseCase = getScannedDocumentsUseCase
        self.saveScannedDocumentUseCase = saveScannedDocumentUseCase
        self.deleteScannedDocumentUseCase = deleteScannedDocumentUseCase
        self.importUseCase = importUseCase
        self.detectUseCase = detectUseCase
        self.redactUseCase = redactUseCase
        self.recordRedactionUseCase = recordRedactionUseCase
        self.exportDocumentUseCase = exportDocumentUseCase
    }

    // MARK: - Computed Properties

    /// `true` when nothing has been scanned yet.
    var isEmpty: Bool {
        scannedDocuments.isEmpty
    }

    /// The `ScannedDocument` matching `selectedDocumentId`, or `nil` if there
    /// is no selection or the id no longer exists (e.g. it was just deleted).
    var selectedDocument: ScannedDocument? {
        guard let id = selectedDocumentId else { return nil }
        return scannedDocuments.first { $0.id == id }
    }

    /// Documents whose original text contains the search query, case- and
    /// locale-insensitively. Returns everything when the query is empty so
    /// the sidebar never flashes empty while the search field is focused.
    var filteredDocuments: [ScannedDocument] {
        if searchQuery.isEmpty {
            return scannedDocuments
        }
        return scannedDocuments.filter {
            $0.originalDocument.content.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    // MARK: - Actions

    /// Refreshes `scannedDocuments` from the repository and re-derives the
    /// navigation state. Called on appear and after every mutation.
    func loadDocuments() async {
        scannedDocuments = await getScannedDocumentsUseCase.execute()
        updateNavigationState()
    }

    /// Selects a document and routes the detail pane to it.
    func selectDocument(_ id: UUID) {
        selectedDocumentId = id
        navigationState = .documentSelected(id)
    }

    /// Imports raw text and immediately scans it.
    ///
    /// This is the entry point used by the clipboard, file-import and sample
    /// buttons. `source` and `fileURL` are stored on the resulting
    /// `ScannedDocument` for display and provenance.
    func createNewDocument(content: String, source: DocumentSource = .clipboard, fileURL: URL? = nil) async {
        // Import and immediately start scanning
        let document = await importUseCase.execute(content: content)
        await scanDocument(document, source: source, fileURL: fileURL)
    }

    /// Scans a document, records it in history, persists it as a
    /// `ScannedDocument`, and selects it.
    ///
    /// The navigation state is set to `.scanning` up front so
    /// `DocumentDetailView` shows the progress view while detection and
    /// redaction run concurrently. On save failure the error is only logged;
    /// the navigation state is left as `.scanning` until the next
    /// `loadDocuments()` call recomputes it.
    func scanDocument(_ document: Document, source: DocumentSource = .clipboard, fileURL: URL? = nil) async {
        navigationState = .scanning(document)

        // Detection and redaction are independent, so run them in parallel.
        async let detected = detectUseCase.execute(document: document)
        async let redacted = redactUseCase.execute(document: document)

        let detectedEntities = await detected
        let redactedDocument = await redacted

        let results = ScanResults(
            detectedEntities: detectedEntities,
            redactedDocument: redactedDocument
        )

        // Record in history. The returned entry is not needed by this flow.
        _ = await recordRedactionUseCase.execute(
            document: document,
            detectedEntities: detectedEntities,
            redactedContent: redactedDocument.redactedContent
        )

        // Save as scanned document
        let scannedDoc = ScannedDocument(
            id: UUID(),
            originalDocument: document,
            scanResults: results,
            scannedAt: Date(),
            source: source,
            originalFileURL: fileURL
        )

        do {
            try await saveScannedDocumentUseCase.execute(scannedDoc)
            // Reload so the sidebar shows the new row, then select it so the
            // detail pane jumps straight to the results.
            await loadDocuments()
            selectDocument(scannedDoc.id)
        } catch {
            // Handle error - for now just print
            print("Error saving scanned document: \(error)")
        }
    }

    /// Deletes a scanned document and repairs the selection.
    ///
    /// If the deleted document was selected, selection falls back to the
    /// first remaining document (or `nil`), and the navigation state is
    /// recomputed so the detail pane never points at a missing record.
    func deleteDocument(_ id: UUID) async {
        do {
            try await deleteScannedDocumentUseCase.execute(id: id)
            await loadDocuments()

            // If we deleted the selected document, select another or show empty
            if selectedDocumentId == id {
                selectedDocumentId = scannedDocuments.first?.id
                updateNavigationState()
            }
        } catch {
            // Handle error
            print("Error deleting document: \(error)")
        }
    }

    /// Writes the redacted text of a scanned document to a file and returns
    /// its URL for the platform share / save UI.
    ///
    /// - Throws: `ExportError.documentNotFound` if the id is unknown, or
    ///   whatever the export use case throws.
    func exportRedactedDocument(for documentId: UUID) async throws -> URL {
        guard let scannedDoc = scannedDocuments.first(where: { $0.id == documentId }) else {
            throw ExportError.documentNotFound
        }

        // Scanned text has no reliable original filename, so a generic base
        // name is used; the use case appends the extension.
        return try await exportDocumentUseCase.exportRedactedDocument(
            scannedDoc.scanResults.redactedDocument,
            originalFilename: "document"
        )
    }

    /// Derives `navigationState` from the document list and selection.
    ///
    /// Priority: no documents -> `.empty`; a selection -> `.documentSelected`;
    /// otherwise `.documentList`. Never produces `.scanning`; that case is set
    /// directly by `scanDocument(_:source:fileURL:)`.
    private func updateNavigationState() {
        if scannedDocuments.isEmpty {
            navigationState = .empty
        } else if let id = selectedDocumentId {
            navigationState = .documentSelected(id)
        } else {
            navigationState = .documentList
        }
    }

    // MARK: - Errors

    /// Errors specific to exporting from this view model.
    enum ExportError: LocalizedError {
        /// The requested document id is not in `scannedDocuments`.
        case documentNotFound

        var errorDescription: String? {
            switch self {
            case .documentNotFound:
                return "Document not found"
            }
        }
    }
}
