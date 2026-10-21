//
//  DIContainer.swift
//  StridApp
//
//  Hexagonal architecture role: **composition root**.
//
//  This is the single place where concrete outbound adapters are bound to
//  the ports the domain declares, use cases are wired to those ports, and
//  view models are assembled from use cases. Nothing else in the app should
//  instantiate an adapter or a use case directly; the inbound UI layer only
//  ever calls the `make*ViewModel()` factories.
//
//  Dependency graph (top depends on bottom):
//
//      HomeViewModel ─── RedactFileUseCaseImpl ─── FileRedactionRecordRepository
//
//      DocumentViewModel ─┬─ ImportDocumentUseCase ─── InMemoryDocumentRepository
//      DocumentListVM   ──┤  DetectPIIUseCase ──────┐
//                         │  RedactPIIUseCase ──────┴─ StridKitPIIDetectorAdapter
//                         │  RecordRedactionUseCase ─┐
//                         │  GetRedactionHistoryUC ──┴─ InMemoryRedactionHistoryRepository
//                         │  ExportDocumentUseCase   (no port)
//                         └─ Get/Save/DeleteScannedDocumentUC ─ InMemoryScannedDocumentRepository
//
//  Every dependency is a `lazy var`, so adapters are created on first use and
//  shared for the lifetime of the process (effectively singletons scoped to
//  the container). Swapping an implementation, e.g. a Core Data repository
//  for the in-memory one, is a one-line change here.
//

import Foundation

/// Process-wide dependency container and view-model factory.
final class DIContainer {
    /// The one container used by the running app. Tests build their own
    /// view models with mock dependencies instead of going through this.
    static let shared = DIContainer()

    // MARK: - Ports (outbound adapters)

    // Ports
    /// PII detection engine. Bound to StridKit via an adapter so the domain
    /// never imports StridKit for the text flow.
    private lazy var piiDetector: PIIDetectorPort = StridKitPIIDetectorAdapter()

    /// Plain-text document storage; volatile, lost on relaunch.
    private lazy var documentRepository: DocumentRepositoryPort = InMemoryDocumentRepository()

    /// Text-redaction audit trail; volatile, lost on relaunch.
    private lazy var historyRepository: RedactionHistoryRepositoryPort = InMemoryRedactionHistoryRepository()

    /// Sidebar document store. Despite the type name this adapter also
    /// persists JSON files under Application Support.
    private lazy var scannedDocumentRepository: ScannedDocumentRepositoryPort = InMemoryScannedDocumentRepository()

    // MARK: - Use Cases (text flow)

    // Use Cases
    /// Creates a `Document` from imported text.
    private lazy var importDocumentUseCase: ImportDocumentUseCase = {
        ImportDocumentUseCaseImpl(repository: documentRepository)
    }()

    /// Scans a document and returns the entities found.
    private lazy var detectPIIUseCase: DetectPIIUseCase = {
        DetectPIIUseCaseImpl(detector: piiDetector)
    }()

    /// Produces the masked version of a document.
    private lazy var redactPIIUseCase: RedactPIIUseCase = {
        RedactPIIUseCaseImpl(detector: piiDetector)
    }()

    /// Appends a history entry after a redaction.
    private lazy var recordRedactionUseCase: RecordRedactionUseCase = {
        RecordRedactionUseCaseImpl(repository: historyRepository)
    }()

    /// Reads the history list and total count.
    private lazy var getHistoryUseCase: GetRedactionHistoryUseCase = {
        GetRedactionHistoryUseCaseImpl(repository: historyRepository)
    }()

    /// Writes text to a temporary file for sharing. Has no port dependency.
    private lazy var exportDocumentUseCase: ExportDocumentUseCase = {
        ExportDocumentUseCaseImpl()
    }()

    /// Lists scanned documents for the sidebar.
    private lazy var getScannedDocumentsUseCase: GetScannedDocumentsUseCase = {
        GetScannedDocumentsUseCaseImpl(repository: scannedDocumentRepository)
    }()

    /// Persists a scanned document.
    private lazy var saveScannedDocumentUseCase: SaveScannedDocumentUseCase = {
        SaveScannedDocumentUseCaseImpl(repository: scannedDocumentRepository)
    }()

    /// Removes a scanned document.
    private lazy var deleteScannedDocumentUseCase: DeleteScannedDocumentUseCase = {
        DeleteScannedDocumentUseCaseImpl(repository: scannedDocumentRepository)
    }()

    // MARK: - File Pipeline (StridDocuments)

    // File pipeline (StridDocuments)
    /// Job folders + JSON index for file redactions, under Application Support.
    private lazy var recordRepository: RedactionRecordRepositoryPort = FileRedactionRecordRepository()

    /// Concrete type is kept (not erased to a protocol) because the same
    /// instance serves as both `RedactFileUseCase` and `RestoreFileUseCase`
    /// for `HomeViewModel`.
    private lazy var redactFileUseCase = RedactFileUseCaseImpl(repository: recordRepository)

    // MARK: - View Model Factories

    /// Builds the view model for the file-redaction home screen.
    ///
    /// `@MainActor` because view models are `ObservableObject`s that must be
    /// created and mutated on the main thread.
    @MainActor
    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(redactUseCase: redactFileUseCase, restoreUseCase: redactFileUseCase, repository: recordRepository)
    }

    // ViewModels
    /// Builds the view model for the single-document text editor/redactor.
    @MainActor
    func makeDocumentViewModel() -> DocumentViewModel {
        DocumentViewModel(
            importUseCase: importDocumentUseCase,
            detectUseCase: detectPIIUseCase,
            redactUseCase: redactPIIUseCase,
            recordRedactionUseCase: recordRedactionUseCase,
            getHistoryUseCase: getHistoryUseCase,
            exportDocumentUseCase: exportDocumentUseCase
        )
    }

    /// Builds the view model for the sidebar list of scanned documents. It
    /// receives the same text-flow use cases as `DocumentViewModel` so it can
    /// scan and redact newly added documents itself.
    @MainActor
    func makeDocumentListViewModel() -> DocumentListViewModel {
        DocumentListViewModel(
            getScannedDocumentsUseCase: getScannedDocumentsUseCase,
            saveScannedDocumentUseCase: saveScannedDocumentUseCase,
            deleteScannedDocumentUseCase: deleteScannedDocumentUseCase,
            importUseCase: importDocumentUseCase,
            detectUseCase: detectPIIUseCase,
            redactUseCase: redactPIIUseCase,
            recordRedactionUseCase: recordRedactionUseCase,
            exportDocumentUseCase: exportDocumentUseCase
        )
    }

    /// Private so `shared` is the only instance in production code.
    private init() {}
}
