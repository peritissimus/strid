import Testing
@testable import StridApp

/// Comprehensive tests for DocumentListViewModel
@Suite("DocumentListViewModel Tests")
@MainActor
struct DocumentListViewModelTests {

    // MARK: - Initialization & Loading

    @Test("ViewModel starts with empty state")
    func viewModelStartsEmpty() {
        let container = MockDIContainer()
        let viewModel = container.makeDocumentListViewModel()

        #expect(viewModel.isEmpty)
        #expect(viewModel.scannedDocuments.count == 0)
        #expect(viewModel.selectedDocumentId == nil)
    }

    @Test("Load documents retrieves from repository")
    func loadDocumentsRetrievesFromRepository() async throws {
        // Given
        let container = MockDIContainer()
        try await container.populateWithTestDocuments(count: 3)
        let viewModel = container.makeDocumentListViewModel()

        // When
        await viewModel.loadDocuments()

        // Then
        #expect(!viewModel.isEmpty)
        #expect(viewModel.scannedDocuments.count == 3)
        #expect(viewModel.navigationState == .documentList)
    }

    // MARK: - Document Creation

    @Test("Create new document from clipboard triggers scan")
    func createNewDocumentFromClipboard() async throws {
        // Given
        let container = MockDIContainer()
        container.configureForEmailDetection()
        let viewModel = container.makeDocumentListViewModel()

        // When
        await viewModel.createNewDocument(
            content: "Email: test@example.com",
            source: .clipboard
        )

        // Then
        await viewModel.loadDocuments()
        #expect(viewModel.scannedDocuments.count == 1)

        let doc = try #require(viewModel.scannedDocuments.first)
        #expect(doc.source == .clipboard)
        #expect(doc.scanResults.entityCount == 1)
    }

    @Test("Create document from file import preserves source")
    func createDocumentFromFileImport() async throws {
        // Given
        let container = MockDIContainer()
        container.configureForMultiPIIDetection()
        let viewModel = container.makeDocumentListViewModel()
        let fileURL = URL(fileURLWithPath: "/tmp/test-document.txt")

        // When
        await viewModel.createNewDocument(
            content: "Email: test@example.com, Phone: 555-123-4567",
            source: .fileImport,
            fileURL: fileURL
        )

        // Then
        await viewModel.loadDocuments()
        let doc = try #require(viewModel.scannedDocuments.first)
        #expect(doc.source == .fileImport)
        #expect(doc.originalFileURL == fileURL)
        #expect(doc.scanResults.entityCount == 2)
    }

    @Test("Create document from sample sets correct source")
    func createDocumentFromSample() async throws {
        // Given
        let container = MockDIContainer()
        container.configureForEmailDetection()
        let viewModel = container.makeDocumentListViewModel()

        // When
        await viewModel.createNewDocument(
            content: TestFactories.sampleEmailDocument,
            source: .sample
        )

        // Then
        await viewModel.loadDocuments()
        let doc = try #require(viewModel.scannedDocuments.first)
        #expect(doc.source == .sample)
    }

    // MARK: - Document Selection

    @Test("Select document updates navigation state")
    func selectDocumentUpdatesState() async throws {
        // Given
        let container = MockDIContainer()
        try await container.populateWithTestDocuments(count: 2)
        let viewModel = container.makeDocumentListViewModel()
        await viewModel.loadDocuments()

        let firstDocId = try #require(viewModel.scannedDocuments.first?.id)

        // When
        viewModel.selectDocument(firstDocId)

        // Then
        #expect(viewModel.selectedDocumentId == firstDocId)
        #expect(viewModel.navigationState == .documentSelected(firstDocId))
    }

    // MARK: - Document Deletion

    @Test("Delete document removes from repository")
    func deleteDocumentRemovesFromRepository() async throws {
        // Given
        let container = MockDIContainer()
        try await container.populateWithTestDocuments(count: 3)
        let viewModel = container.makeDocumentListViewModel()
        await viewModel.loadDocuments()

        let docToDelete = try #require(viewModel.scannedDocuments.first)
        let initialCount = viewModel.scannedDocuments.count

        // When
        await viewModel.deleteDocument(docToDelete.id)

        // Then
        #expect(viewModel.scannedDocuments.count == initialCount - 1)
        #expect(!viewModel.scannedDocuments.contains(where: { $0.id == docToDelete.id }))
        #expect(await container.mockScannedDocumentRepository.deleteCallCount == 1)
    }

    @Test("Delete selected document updates selection")
    func deleteSelectedDocumentUpdatesSelection() async throws {
        // Given
        let container = MockDIContainer()
        try await container.populateWithTestDocuments(count: 3)
        let viewModel = container.makeDocumentListViewModel()
        await viewModel.loadDocuments()

        let firstDoc = try #require(viewModel.scannedDocuments.first)
        viewModel.selectDocument(firstDoc.id)

        // When - Delete the selected document
        await viewModel.deleteDocument(firstDoc.id)

        // Then - Selection updated (should auto-select first remaining, or nil)
        #expect(viewModel.selectedDocumentId != firstDoc.id)
    }

    @Test("Delete last document shows empty state")
    func deleteLastDocumentShowsEmpty() async throws {
        // Given
        let container = MockDIContainer()
        try await container.populateWithTestDocuments(count: 1)
        let viewModel = container.makeDocumentListViewModel()
        await viewModel.loadDocuments()

        let onlyDoc = try #require(viewModel.scannedDocuments.first)

        // When
        await viewModel.deleteDocument(onlyDoc.id)

        // Then
        #expect(viewModel.isEmpty)
        #expect(viewModel.navigationState == .empty)
    }

    // MARK: - Search/Filter

    @Test("Search filters documents correctly")
    func searchFiltersDocuments() async throws {
        // Given
        let container = MockDIContainer()
        let doc1 = TestFactories.makeScannedDocument(content: "Email: alice@example.com")
        let doc2 = TestFactories.makeScannedDocument(content: "Phone: 555-123-4567")
        let doc3 = TestFactories.makeScannedDocument(content: "Contact: bob@example.com")

        try await container.mockScannedDocumentRepository.save(doc1)
        try await container.mockScannedDocumentRepository.save(doc2)
        try await container.mockScannedDocumentRepository.save(doc3)

        let viewModel = container.makeDocumentListViewModel()
        await viewModel.loadDocuments()

        // When
        viewModel.searchQuery = "email"

        // Then
        let filtered = viewModel.filteredDocuments
        #expect(filtered.count == 2)
        #expect(filtered.allSatisfy { $0.originalDocument.content.contains("@example.com") })
    }

    @Test("Empty search query shows all documents")
    func emptySearchShowsAll() async throws {
        // Given
        let container = MockDIContainer()
        try await container.populateWithTestDocuments(count: 5)
        let viewModel = container.makeDocumentListViewModel()
        await viewModel.loadDocuments()

        // When
        viewModel.searchQuery = ""

        // Then
        #expect(viewModel.filteredDocuments.count == 5)
        #expect(viewModel.filteredDocuments.count == viewModel.scannedDocuments.count)
    }

    // MARK: - Export

    @Test("Export redacted document creates file")
    func exportRedactedDocumentCreatesFile() async throws {
        // Given
        let container = MockDIContainer()
        container.configureForEmailDetection()

        let doc = TestFactories.makeScannedDocument(
            content: "Email: test@example.com"
        )
        try await container.mockScannedDocumentRepository.save(doc)

        let viewModel = container.makeDocumentListViewModel()
        await viewModel.loadDocuments()

        // When
        let exportURL = try await viewModel.exportRedactedDocument(for: doc.id)

        // Then
        #expect(FileManager.default.fileExists(atPath: exportURL.path))
        #expect(exportURL.lastPathComponent.contains("redacted"))
        #expect(exportURL.pathExtension == "txt")

        // Cleanup
        try? FileManager.default.removeItem(at: exportURL)
    }

    @Test("Export non-existent document throws error")
    func exportNonExistentDocumentThrows() async {
        // Given
        let container = MockDIContainer()
        let viewModel = container.makeDocumentListViewModel()
        let fakeId = UUID()

        // When/Then
        await #expect(throws: DocumentListViewModel.ExportError.documentNotFound) {
            _ = try await viewModel.exportRedactedDocument(for: fakeId)
        }
    }

    // MARK: - Navigation State

    @Test("Navigation state changes with document lifecycle")
    func navigationStateChanges() async throws {
        // Given
        let container = MockDIContainer()
        container.configureForEmailDetection()
        let viewModel = container.makeDocumentListViewModel()

        // Empty state
        #expect(viewModel.navigationState == .empty)

        // After creating document (scanning)
        await viewModel.createNewDocument(
            content: "Email: test@example.com",
            source: .clipboard
        )

        // After scan completes and document is saved
        await viewModel.loadDocuments()
        let doc = try #require(viewModel.scannedDocuments.first)

        // Selected state
        viewModel.selectDocument(doc.id)
        #expect(viewModel.navigationState == .documentSelected(doc.id))

        // Back to list
        viewModel.selectedDocumentId = nil
        #expect(viewModel.navigationState == .documentList)
    }

    // MARK: - Edge Cases

    @Test("Concurrent operations maintain data integrity")
    func concurrentOperationsMaintainIntegrity() async throws {
        // Given
        let container = MockDIContainer()
        container.configureForEmailDetection()
        let viewModel = container.makeDocumentListViewModel()

        // When - Create multiple documents concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    await viewModel.createNewDocument(
                        content: "Document \(i) with test\(i)@example.com",
                        source: .clipboard
                    )
                }
            }
        }

        // Then
        await viewModel.loadDocuments()
        #expect(viewModel.scannedDocuments.count == 5)
    }

    @Test("Documents sorted by date descending")
    func documentsSortedByDate() async throws {
        // Given
        let container = MockDIContainer()
        let older = TestFactories.makeScannedDocument(
            scannedAt: Date().addingTimeInterval(-3600)
        )
        let newer = TestFactories.makeScannedDocument(
            scannedAt: Date()
        )
        let oldest = TestFactories.makeScannedDocument(
            scannedAt: Date().addingTimeInterval(-7200)
        )

        try await container.mockScannedDocumentRepository.save(older)
        try await container.mockScannedDocumentRepository.save(newer)
        try await container.mockScannedDocumentRepository.save(oldest)

        let viewModel = container.makeDocumentListViewModel()

        // When
        await viewModel.loadDocuments()

        // Then
        let docs = viewModel.scannedDocuments
        #expect(docs.count == 3)
        #expect(docs[0].id == newer.id)
        #expect(docs[1].id == older.id)
        #expect(docs[2].id == oldest.id)
    }
}
