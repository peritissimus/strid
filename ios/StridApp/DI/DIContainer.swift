import Foundation

final class DIContainer {
    static let shared = DIContainer()

    // Ports
    private lazy var piiDetector: PIIDetectorPort = StridKitPIIDetectorAdapter()
    private lazy var documentRepository: DocumentRepositoryPort = InMemoryDocumentRepository()
    private lazy var historyRepository: RedactionHistoryRepositoryPort = InMemoryRedactionHistoryRepository()

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

    // ViewModels
    @MainActor
    func makeDocumentViewModel() -> DocumentViewModel {
        DocumentViewModel(
            importUseCase: importDocumentUseCase,
            detectUseCase: detectPIIUseCase,
            redactUseCase: redactPIIUseCase,
            recordRedactionUseCase: recordRedactionUseCase,
            getHistoryUseCase: getHistoryUseCase
        )
    }

    private init() {}
}
