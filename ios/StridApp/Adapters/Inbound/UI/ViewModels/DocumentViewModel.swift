import Foundation
import SwiftUI
import StridKit

@MainActor
@Observable
final class DocumentViewModel {
    // State
    var state: DocumentState = .empty
    var viewMode: ViewMode = .original
    var showingSummary = false
    var showingHistory = false
    var showingSamplePicker = false
    var redactionHistory: [RedactionHistoryEntry] = []

    // Sample documents
    var sampleDocuments: [SampleDocument] {
        SampleDocument.samples
    }

    // Use Cases
    private let importUseCase: ImportDocumentUseCase
    private let detectUseCase: DetectPIIUseCase
    private let redactUseCase: RedactPIIUseCase
    private let recordRedactionUseCase: RecordRedactionUseCase
    private let getHistoryUseCase: GetRedactionHistoryUseCase
    private let exportDocumentUseCase: ExportDocumentUseCase

    init(
        importUseCase: ImportDocumentUseCase,
        detectUseCase: DetectPIIUseCase,
        redactUseCase: RedactPIIUseCase,
        recordRedactionUseCase: RecordRedactionUseCase,
        getHistoryUseCase: GetRedactionHistoryUseCase,
        exportDocumentUseCase: ExportDocumentUseCase
    ) {
        self.importUseCase = importUseCase
        self.detectUseCase = detectUseCase
        self.redactUseCase = redactUseCase
        self.recordRedactionUseCase = recordRedactionUseCase
        self.getHistoryUseCase = getHistoryUseCase
        self.exportDocumentUseCase = exportDocumentUseCase
    }

    // MARK: - State Computed Properties

    var isProcessing: Bool {
        if case .processing = state { return true }
        return false
    }

    var hasDocument: Bool {
        state.document != nil
    }

    var hasResults: Bool {
        if case .scanned = state { return true }
        return false
    }

    var currentDocument: Document? {
        state.document
    }

    var sourceText: String {
        currentDocument?.content ?? ""
    }

    var results: ScanResults? {
        if case .scanned(_, let results) = state {
            return results
        }
        return nil
    }

    var entityCount: Int {
        results?.entityCount ?? 0
    }

    var redactedText: String {
        results?.redactedDocument.redactedContent ?? ""
    }

    // MARK: - Actions

    func importDocument(content: String) async {
        let document = await importUseCase.execute(content: content)
        state = .loaded(document)
        viewMode = .original
    }

    func scanDocument() async {
        guard let document = currentDocument else { return }

        state = .processing(document)

        async let detected = detectUseCase.execute(document: document)
        async let redacted = redactUseCase.execute(document: document)

        let detectedEntities = await detected
        let redactedDocument = await redacted

        let results = ScanResults(
            detectedEntities: detectedEntities,
            redactedDocument: redactedDocument
        )

        // Record redaction in history
        _ = await recordRedactionUseCase.execute(
            document: document,
            detectedEntities: detectedEntities,
            redactedContent: redactedDocument.redactedContent
        )

        state = .scanned(document, results: results)
        viewMode = .highlighted
    }

    func clearDocument() {
        state = .empty
        viewMode = .original
        showingSummary = false
    }

    func toggleSummary() {
        showingSummary.toggle()
    }

    func goBackToDocument() {
        if case .scanned(let document, _) = state {
            state = .loaded(document)
            viewMode = .original
        }
    }

    func canGoBack() -> Bool {
        if case .scanned = state { return true }
        if case .loaded = state { return true }
        return false
    }

    func toggleHistory() {
        showingHistory.toggle()
        if showingHistory {
            Task {
                await loadHistory()
            }
        }
    }

    func loadHistory() async {
        redactionHistory = await getHistoryUseCase.execute()
    }

    var totalRedactionCount: Int {
        redactionHistory.count
    }

    func toggleSamplePicker() {
        showingSamplePicker.toggle()
    }

    func loadSampleDocument(_ sample: SampleDocument) async {
        await importDocument(content: sample.content)
        showingSamplePicker = false
    }

    func exportRedactedDocument() async throws -> URL {
        guard let results = results else {
            throw ExportError.noRedactedDocument
        }

        let filename = "document"
        return try await exportDocumentUseCase.exportRedactedDocument(
            results.redactedDocument,
            originalFilename: filename
        )
    }

    enum ExportError: LocalizedError {
        case noRedactedDocument

        var errorDescription: String? {
            switch self {
            case .noRedactedDocument:
                return "No redacted document available to export"
            }
        }
    }

    // MARK: - Helpers

    func colorForType(_ type: PIIEntityType) -> Color {
        switch type {
        // Critical PII - Error red
        case .person, .inDOB, .inPAN, .inAadhaar, .creditCard, .inBankAccount:
            .stridError

        // Contact information - Accent teal
        case .email, .url, .phone, .inPhone, .inUPIID:
            .stridAccent

        // Location information - Warning orange
        case .location, .inPINCode:
            .stridWarning

        // Financial/Banking codes - Info blue
        case .inIFSC, .inBranchCode, .inMICR, .inTxnRef:
            .stridInfo

        // Organizational/Generic - Dark gray
        case .organization, .inCustomerID, .ipAddress:
            .stridDarkGray
        }
    }
}
