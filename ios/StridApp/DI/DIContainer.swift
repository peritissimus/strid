import Foundation

final class DIContainer {
    static let shared = DIContainer()

    // Ports
    private lazy var piiDetector: PIIDetectorPort = StridKitPIIDetectorAdapter()
    private lazy var documentRepository: DocumentRepositoryPort = InMemoryDocumentRepository()
    private lazy var historyRepository: RedactionHistoryRepositoryPort = InMemoryRedactionHistoryRepository()
    private lazy var scannedDocumentRepository: ScannedDocumentRepositoryPort = InMemoryScannedDocumentRepository()

    // Use Cases
    private lazy var importDocumentUseCase: ImportDocumentUseCase = {
        ImportDocumentUseCaseImpl(repository: documentRepository)
    }()

    private lazy var detectPIIUseCase: DetectPIIUseCase = {
        DetectPIIUseCaseImpl(detector: piiDetector)
    }()

    private lazy var redactPIIUseCase: RedactPIIUseCase = {
        RedactPIIUseCaseImpl(detector: piiDetector)
    }()

    private lazy var recordRedactionUseCase: RecordRedactionUseCase = {
        RecordRedactionUseCaseImpl(repository: historyRepository)
    }()

    private lazy var getHistoryUseCase: GetRedactionHistoryUseCase = {
        GetRedactionHistoryUseCaseImpl(repository: historyRepository)
    }()

    private lazy var exportDocumentUseCase: ExportDocumentUseCase = {
        ExportDocumentUseCaseImpl()
    }()

    private lazy var getScannedDocumentsUseCase: GetScannedDocumentsUseCase = {
        GetScannedDocumentsUseCaseImpl(repository: scannedDocumentRepository)
    }()

    private lazy var saveScannedDocumentUseCase: SaveScannedDocumentUseCase = {
        SaveScannedDocumentUseCaseImpl(repository: scannedDocumentRepository)
    }()

    private lazy var deleteScannedDocumentUseCase: DeleteScannedDocumentUseCase = {
        DeleteScannedDocumentUseCaseImpl(repository: scannedDocumentRepository)
    }()

    // ViewModels
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

    private init() {}
}
