//
//  InMemoryScannedDocumentRepository.swift
//  StridApp
//
//  Hexagonal architecture role: **outbound adapter** implementing
//  `ScannedDocumentRepositoryPort`.
//
//  Despite the "InMemory" name this adapter is a write-through cache: every
//  `ScannedDocument` is held in a dictionary for fast reads *and* written to
//  disk as pretty-printed JSON so it survives relaunch.
//
//  On-disk layout:
//
//      <Application Support>/Strid/
//      ├── FileImports/<uuid>.json    ← DocumentSource.fileImport
//      ├── ClipboardDocs/<uuid>.json  ← DocumentSource.clipboard
//      └── SampleDocs/<uuid>.json     ← DocumentSource.sample
//
//  One file per document (rather than a single index) keeps each write
//  small and means a corrupt file only loses that one document. Splitting by
//  source makes it easy to, say, wipe only sample documents, and lets a
//  human browsing the container see where things came from.
//

import Foundation

/// File system-based repository for persisting scanned documents
/// Stores documents in Application Support directory with separate folders for different sources
/// Uses actor for thread-safe concurrent access
actor InMemoryScannedDocumentRepository: ScannedDocumentRepositoryPort {
    /// Authoritative in-memory copy, keyed by `ScannedDocument.id`. Reads
    /// never touch the disk after the initial load.
    private var scannedDocuments: [UUID: ScannedDocument] = [:]

    /// Shared file manager; safe inside the actor.
    private let fileManager = FileManager.default

    // MARK: - Storage Paths

    /// `…/Application Support/Strid`. Not created here; the per-source
    /// getters below create their own subfolders (and intermediates).
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

    /// Folder for documents imported via the file picker. Created on access.
    private var fileImportsDirectory: URL {
        get throws {
            let dir = try baseDirectory.appendingPathComponent("FileImports", isDirectory: true)
            try ensureDirectoryExists(at: dir)
            return dir
        }
    }

    /// Folder for documents pasted from the clipboard. Created on access.
    private var clipboardDocsDirectory: URL {
        get throws {
            let dir = try baseDirectory.appendingPathComponent("ClipboardDocs", isDirectory: true)
            try ensureDirectoryExists(at: dir)
            return dir
        }
    }

    /// Folder for scans of bundled sample documents. Created on access.
    private var sampleDocsDirectory: URL {
        get throws {
            let dir = try baseDirectory.appendingPathComponent("SampleDocs", isDirectory: true)
            try ensureDirectoryExists(at: dir)
            return dir
        }
    }

    // MARK: - Initialization

    /// Creates the repository and kicks off an asynchronous load of any
    /// documents already on disk.
    ///
    /// The load runs in a detached `Task` because an actor initialiser cannot
    /// `await`. Consequently there is a brief window after construction where
    /// `getAllScannedDocuments()` may return an empty list; the sidebar
    /// re-queries on appear so this is not user-visible in practice.
    init() {
        // Load existing documents on init
        Task {
            await loadFromDisk()
        }
    }

    /// Creates `url` (and intermediates) if it does not already exist.
    private func ensureDirectoryExists(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Reads every JSON file from all three source folders into memory.
    ///
    /// Errors are logged and swallowed: a failure to read the cache should
    /// degrade to "no history" rather than crash at launch.
    private func loadFromDisk() async {
        do {
            let fileImports = try await loadDocumentsFromDirectory(fileImportsDirectory)
            let clipboardDocs = try await loadDocumentsFromDirectory(clipboardDocsDirectory)
            let sampleDocs = try await loadDocumentsFromDirectory(sampleDocsDirectory)

            let allDocs = fileImports + clipboardDocs + sampleDocs
            // Ids are UUIDs written by this adapter, so uniqueness is assumed.
            scannedDocuments = Dictionary(uniqueKeysWithValues: allDocs.map { ($0.id, $0) })
        } catch {
            print("Error loading scanned documents: \(error)")
        }
    }

    /// Decodes every `*.json` file in `directory` as a `ScannedDocument`.
    ///
    /// Individual decode failures are logged and skipped so one corrupt file
    /// does not hide the rest. Dates are ISO-8601, matching `save(_:)`.
    ///
    /// - Parameter directory: One of the three source folders.
    /// - Returns: Successfully decoded documents, in directory-listing order.
    /// - Throws: If the directory itself cannot be listed.
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

    /// Stores the document in memory and writes it to
    /// `<sourceFolder>/<id>.json`.
    ///
    /// The JSON is pretty-printed with sorted keys so files diff cleanly and
    /// are readable when debugging the container. Dates are ISO-8601 for the
    /// same reason (and to be timezone-unambiguous). The write is atomic so a
    /// crash cannot leave a truncated file that would then fail to decode.
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

    /// All documents, newest scan first. Served from memory.
    func getAllScannedDocuments() async -> [ScannedDocument] {
        scannedDocuments.values.sorted { $0.scannedAt > $1.scannedAt }
    }

    /// Single lookup by id. Served from memory.
    func getScannedDocument(id: UUID) async -> ScannedDocument? {
        scannedDocuments[id]
    }

    /// Removes the document from memory and deletes its JSON file.
    ///
    /// The source folder is derived from the in-memory copy, so an id that
    /// is not in memory is a no-op even if a stray file exists on disk.
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

    /// Clears memory and deletes every `*.json` in all three source folders.
    /// The folders themselves are left in place.
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

    /// Case-insensitive substring search over the original text.
    ///
    /// An empty query short-circuits to the full list. The search is a
    /// linear scan over in-memory content, which is fine for the tens of
    /// documents a sidebar typically holds.
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

    /// Maps a `DocumentSource` to the folder its files live in.
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
