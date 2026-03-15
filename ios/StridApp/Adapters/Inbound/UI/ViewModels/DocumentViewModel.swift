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
    var redactionHistory: [RedactionHistoryEntry] = []

    // Use Cases
    private let importUseCase: ImportDocumentUseCase
    private let detectUseCase: DetectPIIUseCase
    private let redactUseCase: RedactPIIUseCase
    private let recordRedactionUseCase: RecordRedactionUseCase
    private let getHistoryUseCase: GetRedactionHistoryUseCase

    init(
        importUseCase: ImportDocumentUseCase,
        detectUseCase: DetectPIIUseCase,
        redactUseCase: RedactPIIUseCase,
        recordRedactionUseCase: RecordRedactionUseCase,
        getHistoryUseCase: GetRedactionHistoryUseCase
    ) {
        self.importUseCase = importUseCase
        self.detectUseCase = detectUseCase
        self.redactUseCase = redactUseCase
        self.recordRedactionUseCase = recordRedactionUseCase
        self.getHistoryUseCase = getHistoryUseCase
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
        await recordRedactionUseCase.execute(
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

    // MARK: - Helpers

    func iconForType(_ type: PIIEntityType) -> String {
        switch type {
        case .person: "person"
        case .email: "envelope"
        case .phone, .inPhone: "phone"
        case .url: "link"
        case .location: "mappin"
        case .organization: "building.2"
        case .creditCard: "creditcard"
        case .ipAddress: "network"
        case .inBankAccount: "banknote"
        case .inIFSC: "building.columns"
        case .inPAN: "doc.text"
        case .inAadhaar: "person.text.rectangle"
        case .inUPIID: "indianrupeesign.circle"
        case .inMICR: "barcode"
        case .inPINCode: "mappin.and.ellipse"
        case .inCustomerID: "person.badge.key"
        case .inBranchCode: "number"
        case .inTxnRef: "number.circle"
        case .inDOB: "calendar"
        }
    }

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
