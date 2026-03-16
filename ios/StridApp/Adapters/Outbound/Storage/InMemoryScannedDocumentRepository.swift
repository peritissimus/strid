import Foundation

/// File system-based repository for persisting scanned documents
/// Stores documents in Application Support directory with separate folders for different sources
/// Uses actor for thread-safe concurrent access
actor InMemoryScannedDocumentRepository: ScannedDocumentRepositoryPort {
    private var scannedDocuments: [UUID: ScannedDocument] = [:]
    private let fileManager = FileManager.default

    // MARK: - Storage Paths

    private var baseDirectory: URL {
        get throws {
            try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appendingPathComponent("Strid", isDirectory: true)
        }
    }

    private var fileImportsDirectory: URL {
        get throws {
            let dir = try baseDirectory.appendingPathComponent("FileImports", isDirectory: true)
            try ensureDirectoryExists(at: dir)
            return dir
        }
    }

    private var clipboardDocsDirectory: URL {
        get throws {
            let dir = try baseDirectory.appendingPathComponent("ClipboardDocs", isDirectory: true)
            try ensureDirectoryExists(at: dir)
            return dir
        }
    }

    private var sampleDocsDirectory: URL {
        get throws {
            let dir = try baseDirectory.appendingPathComponent("SampleDocs", isDirectory: true)
            try ensureDirectoryExists(at: dir)
            return dir
        }
    }

    // MARK: - Initialization

    init() {
        // Load existing documents on init
        Task {
            await loadFromDisk()
        }
    }

    private func ensureDirectoryExists(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func loadFromDisk() async {
        do {
            let fileImports = try await loadDocumentsFromDirectory(fileImportsDirectory)
            let clipboardDocs = try await loadDocumentsFromDirectory(clipboardDocsDirectory)
            let sampleDocs = try await loadDocumentsFromDirectory(sampleDocsDirectory)

            let allDocs = fileImports + clipboardDocs + sampleDocs
            scannedDocuments = Dictionary(uniqueKeysWithValues: allDocs.map { ($0.id, $0) })
        } catch {
            print("Error loading scanned documents: \(error)")
        }
    }

    private func loadDocumentsFromDirectory(_ directory: URL) async throws -> [ScannedDocument] {
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let jsonFiles = contents.filter { $0.pathExtension == "json" }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var documents: [ScannedDocument] = []

        for fileURL in jsonFiles {
            do {
                let data = try Data(contentsOf: fileURL)
                let document = try decoder.decode(ScannedDocument.self, from: data)
                documents.append(document)
            } catch {
                print("Error decoding document at \(fileURL): \(error)")
            }
        }

        return documents
    }

    // MARK: - Repository Protocol

    func save(_ document: ScannedDocument) async throws {
        // Save to memory
        scannedDocuments[document.id] = document

        // Persist to disk
        let directory = try directoryForSource(document.source)
        let fileURL = directory.appendingPathComponent("\(document.id.uuidString).json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: .atomic)
    }

    func getAllScannedDocuments() async -> [ScannedDocument] {
        scannedDocuments.values.sorted { $0.scannedAt > $1.scannedAt }
    }

    func getScannedDocument(id: UUID) async -> ScannedDocument? {
        scannedDocuments[id]
    }

    func delete(id: UUID) async throws {
        // Remove from memory
        guard let document = scannedDocuments.removeValue(forKey: id) else {
            return
        }

        // Delete from disk
        let directory = try directoryForSource(document.source)
        let fileURL = directory.appendingPathComponent("\(id.uuidString).json")
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    func deleteAll() async throws {
        // Clear memory
        scannedDocuments.removeAll()

        // Delete all files from disk
        let directories = [
            try fileImportsDirectory,
            try clipboardDocsDirectory,
            try sampleDocsDirectory
        ]

        for directory in directories {
            let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in contents where file.pathExtension == "json" {
                try fileManager.removeItem(at: file)
            }
        }
    }

    func search(query: String) async -> [ScannedDocument] {
        guard !query.isEmpty else {
            return await getAllScannedDocuments()
        }

        let lowercasedQuery = query.lowercased()

        return scannedDocuments.values
            .filter { document in
                document.originalDocument.content.lowercased().contains(lowercasedQuery)
            }
            .sorted { $0.scannedAt > $1.scannedAt }
    }

    // MARK: - Private Helpers

    private func directoryForSource(_ source: DocumentSource) throws -> URL {
        switch source {
        case .fileImport:
            return try fileImportsDirectory
        case .clipboard:
            return try clipboardDocsDirectory
        case .sample:
            return try sampleDocsDirectory
        }
    }
}
