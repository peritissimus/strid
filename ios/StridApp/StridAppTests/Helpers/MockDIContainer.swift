import Foundation
@testable import StridApp

/// Test-friendly DI container with configurable mock dependencies
final class MockDIContainer {

    // MARK: - Mock Dependencies

    let mockPIIDetector: MockPIIDetector
    let mockDocumentRepository: MockDocumentRepository
    let mockScannedDocumentRepository: MockScannedDocumentRepository
    let mockHistoryRepository: MockRedactionHistoryRepository

    // MARK: - Initialization

    init(
        piiDetector: MockPIIDetector = MockPIIDetector(),
        documentRepository: MockDocumentRepository = MockDocumentRepository(),
        scannedDocumentRepository: MockScannedDocumentRepository = MockScannedDocumentRepository(),
        historyRepository: MockRedactionHistoryRepository = MockRedactionHistoryRepository()
    ) {
        self.mockPIIDetector = piiDetector
        self.mockDocumentRepository = documentRepository
        self.mockScannedDocumentRepository = scannedDocumentRepository
        self.mockHistoryRepository = historyRepository
    }

    // MARK: - Use Case Factories

    func makeImportDocumentUseCase() -> ImportDocumentUseCase {
        ImportDocumentUseCaseImpl(repository: mockDocumentRepository)
    }

    func makeDetectPIIUseCase() -> DetectPIIUseCase {
        DetectPIIUseCaseImpl(detector: mockPIIDetector)
    }

    func makeRedactPIIUseCase() -> RedactPIIUseCase {
        RedactPIIUseCaseImpl(detector: mockPIIDetector)
    }

    func makeRecordRedactionUseCase() -> RecordRedactionUseCase {
        RecordRedactionUseCaseImpl(repository: mockHistoryRepository)
    }

    func makeGetHistoryUseCase() -> GetRedactionHistoryUseCase {
        GetRedactionHistoryUseCaseImpl(repository: mockHistoryRepository)
    }

    func makeExportDocumentUseCase() -> ExportDocumentUseCase {
        ExportDocumentUseCaseImpl()
    }

    func makeGetScannedDocumentsUseCase() -> GetScannedDocumentsUseCase {
        GetScannedDocumentsUseCaseImpl(repository: mockScannedDocumentRepository)
    }

    func makeSaveScannedDocumentUseCase() -> SaveScannedDocumentUseCase {
        SaveScannedDocumentUseCaseImpl(repository: mockScannedDocumentRepository)
    }

    func makeDeleteScannedDocumentUseCase() -> DeleteScannedDocumentUseCase {
        DeleteScannedDocumentUseCaseImpl(repository: mockScannedDocumentRepository)
    }

    // MARK: - ViewModel Factories

    @MainActor
    func makeDocumentViewModel() -> DocumentViewModel {
        DocumentViewModel(
            importUseCase: makeImportDocumentUseCase(),
            detectUseCase: makeDetectPIIUseCase(),
            redactUseCase: makeRedactPIIUseCase(),
            recordRedactionUseCase: makeRecordRedactionUseCase(),
            getHistoryUseCase: makeGetHistoryUseCase(),
            exportDocumentUseCase: makeExportDocumentUseCase()
        )
    }

    @MainActor
    func makeDocumentListViewModel() -> DocumentListViewModel {
        DocumentListViewModel(
            getScannedDocumentsUseCase: makeGetScannedDocumentsUseCase(),
            saveScannedDocumentUseCase: makeSaveScannedDocumentUseCase(),
            deleteScannedDocumentUseCase: makeDeleteScannedDocumentUseCase(),
            importUseCase: makeImportDocumentUseCase(),
            detectUseCase: makeDetectPIIUseCase(),
            redactUseCase: makeRedactPIIUseCase(),
            recordRedactionUseCase: makeRecordRedactionUseCase(),
            exportDocumentUseCase: makeExportDocumentUseCase()
        )
    }

    // MARK: - Test Utilities

    /// Reset all mocks to clean state
    func resetAll() async {
        mockPIIDetector.reset()
        await mockDocumentRepository.reset()
        await mockScannedDocumentRepository.reset()
        await mockHistoryRepository.reset()
    }

    /// Configure detector with common test scenario
    func configureForEmailDetection() {
        mockPIIDetector.configureToDetectEmail("test@example.com")
    }

    /// Configure detector with multiple PII types
    func configureForMultiPIIDetection() {
        mockPIIDetector.configureToDetectMultiplePII()
    }

    /// Pre-populate repository with test documents
    func populateWithTestDocuments(count: Int = 3) async throws {
        for i in 0..<count {
            let doc = TestFactories.makeScannedDocument(
                content: "Test document \(i) with test\(i)@example.com",
                scannedAt: Date().addingTimeInterval(Double(-i * 3600))
            )
            try await mockScannedDocumentRepository.save(doc)
        }
    }
}
