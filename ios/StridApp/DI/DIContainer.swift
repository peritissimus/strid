import Foundation

final class DIContainer {
    static let shared = DIContainer()

    // Ports
    private lazy var piiDetector: PIIDetectorPort = StridKitPIIDetectorAdapter()
    private lazy var documentRepository: DocumentRepositoryPort = InMemoryDocumentRepository()

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

    // ViewModels
    @MainActor
    func makeDocumentViewModel() -> DocumentViewModel {
        DocumentViewModel(
            importUseCase: importDocumentUseCase,
            detectUseCase: detectPIIUseCase,
            redactUseCase: redactPIIUseCase
        )
    }

    private init() {}
}
