import Foundation
import SwiftUI

@MainActor
@Observable
final class DocumentListViewModel {
    // MARK: - State

    var scannedDocuments: [ScannedDocument] = []
    var selectedDocumentId: UUID?
    var navigationState: AppNavigationState = .empty
    var searchQuery: String = ""

    // Sheets
    var showingSamplePicker = false

    // Use Cases
    private let getScannedDocumentsUseCase: GetScannedDocumentsUseCase
    private let saveScannedDocumentUseCase: SaveScannedDocumentUseCase
    private let deleteScannedDocumentUseCase: DeleteScannedDocumentUseCase
    private let importUseCase: ImportDocumentUseCase
    private let detectUseCase: DetectPIIUseCase
    private let redactUseCase: RedactPIIUseCase
    private let recordRedactionUseCase: RecordRedactionUseCase
    private let exportDocumentUseCase: ExportDocumentUseCase

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

    var isEmpty: Bool {
        scannedDocuments.isEmpty
    }

    var selectedDocument: ScannedDocument? {
        guard let id = selectedDocumentId else { return nil }
        return scannedDocuments.first { $0.id == id }
    }

    var filteredDocuments: [ScannedDocument] {
        if searchQuery.isEmpty {
            return scannedDocuments
        }
        return scannedDocuments.filter {
            $0.originalDocument.content.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    // MARK: - Actions

    func loadDocuments() async {
        scannedDocuments = await getScannedDocumentsUseCase.execute()
        updateNavigationState()
    }

    func selectDocument(_ id: UUID) {
        selectedDocumentId = id
        navigationState = .documentSelected(id)
    }

    func createNewDocument(content: String, source: DocumentSource = .clipboard, fileURL: URL? = nil) async {
        // Import and immediately start scanning
        let document = await importUseCase.execute(content: content)
        await scanDocument(document, source: source, fileURL: fileURL)
    }

    func scanDocument(_ document: Document, source: DocumentSource = .clipboard, fileURL: URL? = nil) async {
        navigationState = .scanning(document)

        async let detected = detectUseCase.execute(document: document)
        async let redacted = redactUseCase.execute(document: document)

        let detectedEntities = await detected
        let redactedDocument = await redacted

        let results = ScanResults(
            detectedEntities: detectedEntities,
            redactedDocument: redactedDocument
        )

        // Record in history
        await recordRedactionUseCase.execute(
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
            await loadDocuments()
            selectDocument(scannedDoc.id)
        } catch {
            // Handle error - for now just print
            print("Error saving scanned document: \(error)")
        }
    }

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

    func exportRedactedDocument(for documentId: UUID) async throws -> URL {
        guard let scannedDoc = scannedDocuments.first(where: { $0.id == documentId }) else {
            throw ExportError.documentNotFound
        }

        return try await exportDocumentUseCase.exportRedactedDocument(
            scannedDoc.scanResults.redactedDocument,
            originalFilename: "document"
        )
    }

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

    enum ExportError: LocalizedError {
        case documentNotFound

        var errorDescription: String? {
            switch self {
            case .documentNotFound:
                return "Document not found"
            }
        }
    }
}
