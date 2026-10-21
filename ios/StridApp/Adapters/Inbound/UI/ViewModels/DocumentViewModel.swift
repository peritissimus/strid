//
//  DocumentViewModel.swift
//  StridApp
//
//  View model for the single-document text-scanner flow: import one piece of
//  text, scan it for PII, and flip between original / highlighted / redacted
//  renderings. It also exposes redaction history and the sample-document
//  picker. Built by `DIContainer.makeDocumentViewModel()`.
//
//  All state is held as a `DocumentState` value so that "what is loaded" and
//  "where in the scan lifecycle are we" cannot drift apart.
//

import Foundation
import SwiftUI
import StridKit

/// Drives one document through import -> scan -> review.
///
/// `@MainActor` because every property is read by SwiftUI, and `@Observable`
/// so views re-render only for the properties they actually touch.
@MainActor
@Observable
final class DocumentViewModel {
    // MARK: - Observable State

    /// Current lifecycle state of the loaded document (see `DocumentState`).
    /// Every other "is something" property below is derived from this.
    var state: DocumentState = .empty

    /// Which rendering the user is looking at. Reset to `.original` on import
    /// and bumped to `.highlighted` when a scan completes.
    var viewMode: ViewMode = .original

    /// Whether the PII summary sheet is presented. Toggled by `toggleSummary()`.
    var showingSummary = false

    /// Whether the redaction history sheet is presented. Toggling it on also
    /// kicks off a `loadHistory()` refresh.
    var showingHistory = false

    /// Whether the sample-document picker is presented.
    var showingSamplePicker = false

    /// Past redactions loaded from the history repository. Populated lazily
    /// the first time the history UI is shown.
    var redactionHistory: [RedactionHistoryEntry] = []

    // MARK: - Sample Documents

    /// Bundled sample documents offered by the picker. Static data, so this is
    /// a pass-through rather than stored state.
    var sampleDocuments: [SampleDocument] {
        SampleDocument.samples
    }

    // MARK: - Use Cases

    /// Turns raw text into a `Document` entity.
    private let importUseCase: ImportDocumentUseCase
    /// Finds PII spans in a document.
    private let detectUseCase: DetectPIIUseCase
    /// Produces the redacted copy of a document.
    private let redactUseCase: RedactPIIUseCase
    /// Appends an entry to the redaction history after a scan.
    private let recordRedactionUseCase: RecordRedactionUseCase
    /// Reads the redaction history back for display.
    private let getHistoryUseCase: GetRedactionHistoryUseCase
    /// Writes the redacted document to a shareable file URL.
    private let exportDocumentUseCase: ExportDocumentUseCase

    /// Dependency-injected initialiser. All collaborators are protocols so the
    /// view model can be unit-tested with mocks.
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

    /// `true` while a scan is running. Views use this to show a spinner and
    /// disable the scan button.
    var isProcessing: Bool {
        if case .processing = state { return true }
        return false
    }

    /// `true` when any document is loaded, regardless of scan status.
    var hasDocument: Bool {
        state.document != nil
    }

    /// `true` once a scan has produced results.
    var hasResults: Bool {
        if case .scanned = state { return true }
        return false
    }

    /// The loaded document, or `nil` in the `.empty` state.
    var currentDocument: Document? {
        state.document
    }

    /// Original text for the `.original` view mode. Empty string when nothing
    /// is loaded so `Text` views never have to unwrap.
    var sourceText: String {
        currentDocument?.content ?? ""
    }

    /// Scan output, available only in the `.scanned` state.
    var results: ScanResults? {
        if case .scanned(_, let results) = state {
            return results
        }
        return nil
    }

    /// Number of detections from the last scan, or 0 before scanning.
    var entityCount: Int {
        results?.entityCount ?? 0
    }

    /// Redacted text for the `.redacted` view mode. Empty before scanning.
    var redactedText: String {
        results?.redactedDocument.redactedContent ?? ""
    }

    // MARK: - Actions

    /// Imports raw text as a new document and resets the view to the original
    /// rendering. Replaces any previously loaded document and its results.
    func importDocument(content: String) async {
        let document = await importUseCase.execute(content: content)
        state = .loaded(document)
        viewMode = .original
    }

    /// Runs detection and redaction on the current document.
    ///
    /// No-op if nothing is loaded. Moves the state to `.processing` first so
    /// the UI reflects the work, runs the two use cases concurrently via
    /// `async let`, records the result in history, then lands in `.scanned`
    /// and switches the view to `.highlighted` so the user immediately sees
    /// what was found.
    func scanDocument() async {
        guard let document = currentDocument else { return }

        state = .processing(document)

        // Detection and redaction are independent, so run them in parallel.
        async let detected = detectUseCase.execute(document: document)
        async let redacted = redactUseCase.execute(document: document)

        let detectedEntities = await detected
        let redactedDocument = await redacted

        let results = ScanResults(
            detectedEntities: detectedEntities,
            redactedDocument: redactedDocument
        )

        // Record redaction in history. The return value (the history entry)
        // is not needed here; the history sheet reloads from the repository.
        _ = await recordRedactionUseCase.execute(
            document: document,
            detectedEntities: detectedEntities,
            redactedContent: redactedDocument.redactedContent
        )

        state = .scanned(document, results: results)
        viewMode = .highlighted
    }

    /// Discards the current document and results and returns to the empty
    /// state. Also dismisses the summary sheet if it was open.
    func clearDocument() {
        state = .empty
        viewMode = .original
        showingSummary = false
    }

    /// Shows or hides the PII summary sheet.
    func toggleSummary() {
        showingSummary.toggle()
    }

    /// Steps back from `.scanned` to `.loaded`, dropping the results but
    /// keeping the document so it can be re-scanned. Does nothing in other
    /// states.
    func goBackToDocument() {
        if case .scanned(let document, _) = state {
            state = .loaded(document)
            viewMode = .original
        }
    }

    /// Whether a "back" affordance makes sense: there is a document to return
    /// to (loaded or scanned) rather than the empty welcome screen.
    func canGoBack() -> Bool {
        if case .scanned = state { return true }
        if case .loaded = state { return true }
        return false
    }

    /// Shows or hides the history sheet. When opening, refreshes the history
    /// list in a detached `Task` so the toggle itself stays synchronous for
    /// button handlers.
    func toggleHistory() {
        showingHistory.toggle()
        if showingHistory {
            Task {
                await loadHistory()
            }
        }
    }

    /// Reloads `redactionHistory` from the repository.
    func loadHistory() async {
        redactionHistory = await getHistoryUseCase.execute()
    }

    /// Number of past redactions. Only accurate after `loadHistory()`.
    var totalRedactionCount: Int {
        redactionHistory.count
    }

    /// Shows or hides the sample-document picker.
    func toggleSamplePicker() {
        showingSamplePicker.toggle()
    }

    /// Imports a bundled sample and dismisses the picker once it is loaded.
    func loadSampleDocument(_ sample: SampleDocument) async {
        await importDocument(content: sample.content)
        showingSamplePicker = false
    }

    /// Writes the redacted document to a temporary file and returns its URL
    /// for sharing or saving.
    ///
    /// - Throws: `ExportError.noRedactedDocument` if no scan has run yet, or
    ///   whatever the export use case throws.
    func exportRedactedDocument() async throws -> URL {
        guard let results = results else {
            throw ExportError.noRedactedDocument
        }

        // Text documents imported from the clipboard have no filename, so a
        // generic base name is used; the use case adds the extension.
        let filename = "document"
        return try await exportDocumentUseCase.exportRedactedDocument(
            results.redactedDocument,
            originalFilename: filename
        )
    }

    /// Errors specific to exporting from this view model.
    enum ExportError: LocalizedError {
        /// Export was requested before a scan produced a redacted document.
        case noRedactedDocument

        var errorDescription: String? {
            switch self {
            case .noRedactedDocument:
                return "No redacted document available to export"
            }
        }
    }

    // MARK: - Helpers

    /// Maps an entity type to one of the app's semantic colours.
    ///
    /// Types are grouped by how sensitive they are rather than one colour per
    /// type, so the palette stays readable: identity and financial-account
    /// data is red, contact details teal, location orange, bank routing codes
    /// blue, and everything else a neutral dark grey. The `.strid*` colours
    /// are defined in the asset catalog.
    func colorForType(_ type: PIIEntityType) -> Color {
        switch type {
        // Critical PII - Error red
        case .person, .inDOB, .inPAN, .inAadhaar, .creditCard, .inBankAccount, .inGSTIN,
             .inPassport, .inVoterID, .inDrivingLicence, .inUAN:
            .stridError

        // Contact information - Accent teal
        case .email, .url, .phone, .inPhone, .inUPIID:
            .stridAccent

        // Location information - Warning orange
        case .location, .inPINCode, .address, .barcode:
            .stridWarning

        // Financial/Banking codes - Info blue
        case .inIFSC, .inBranchCode, .inMICR, .inTxnRef, .orderID, .inVehicleReg:
            .stridInfo

        // Organizational/Generic - Dark gray
        case .organization, .inCustomerID, .ipAddress, .inTAN, .inCIN:
            .stridDarkGray
        }
    }
}
