//
//  ScannedDocument.swift
//  StridApp
//
//  Hexagonal architecture role: **domain entity** (aggregate).
//
//  `ScannedDocument` bundles a `Document` with the `ScanResults` produced for
//  it and the provenance metadata the sidebar needs. It is the unit that
//  `ScannedDocumentRepositoryPort` persists, so it is `Codable`; the storage
//  adapter writes one JSON file per scanned document, grouped by `source`.
//

import Foundation

/// Source of the document content
///
/// Persisted as a string so the on-disk JSON stays readable, and used by the
/// storage adapter to decide which sub-folder a document lives in.
enum DocumentSource: String, Codable {
    /// Imported from the system file picker.
    case fileImport      // Imported from file picker
    /// Pasted from the clipboard.
    case clipboard       // Pasted from clipboard
    /// Loaded from one of the bundled `SampleDocument`s.
    case sample          // Loaded from sample documents
}

/// Represents a document that has been scanned for PII, bundling the original document,
/// scan results, and metadata for persistence and display in the sidebar
struct ScannedDocument: Identifiable, Equatable, Codable {
    /// Identifier of the scanned-document record (independent of
    /// `originalDocument.id`). Also used as the JSON filename on disk.
    let id: UUID

    /// The text that was scanned.
    let originalDocument: Document

    /// Detection output for `originalDocument`. `ScanResults` is defined
    /// alongside the inbound UI layer and carries the detected entities plus
    /// aggregate counts.
    let scanResults: ScanResults

    /// When the scan ran. Repositories sort by this, newest first.
    let scannedAt: Date

    /// Where the content came from.
    let source: DocumentSource

    /// For file imports, the URL the user originally picked. Informational
    /// only: the app does not retain security-scoped access to it.
    let originalFileURL: URL?  // For file imports, reference to original file

    /// Creates a scanned-document record.
    ///
    /// - Parameters:
    ///   - id: Identifier; a fresh `UUID` by default.
    ///   - originalDocument: The scanned text.
    ///   - scanResults: Detection results for that text.
    ///   - scannedAt: Scan timestamp; defaults to now.
    ///   - source: Provenance of the content.
    ///   - originalFileURL: Original file location for imports; `nil` otherwise.
    init(
        id: UUID = UUID(),
        originalDocument: Document,
        scanResults: ScanResults,
        scannedAt: Date = Date(),
        source: DocumentSource,
        originalFileURL: URL? = nil
    ) {
        self.id = id
        self.originalDocument = originalDocument
        self.scanResults = scanResults
        self.scannedAt = scannedAt
        self.source = source
        self.originalFileURL = originalFileURL
    }

    // MARK: - Display Properties

    /// Title for display in sidebar (first line or first 50 chars)
    ///
    /// Leading/trailing whitespace is trimmed first so a document that starts
    /// with blank lines still gets a meaningful title.
    var title: String {
        let content = originalDocument.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to get first line
        if let firstLine = content.split(separator: "\n", maxSplits: 1).first {
            let line = String(firstLine)
            if !line.isEmpty {
                return String(line.prefix(50))
            }
        }

        // Fallback to first 50 chars
        return String(content.prefix(50))
    }

    /// Preview text for sidebar (first 150 chars)
    ///
    /// Newlines are flattened to spaces so the preview renders as a single
    /// paragraph. Only one pass of double-space collapsing is done, so runs of
    /// three or more spaces may still contain doubles; this is good enough for
    /// a truncated preview.
    var preview: String {
        let content = originalDocument.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove newlines and collapse whitespace for preview
        let normalized = content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")

        return String(normalized.prefix(150))
    }

    /// Entity count summary for sidebar
    ///
    /// Produces a correctly pluralised phrase: "No PII found", "1 PII item",
    /// or "N PII items".
    var entityCountSummary: String {
        let count = scanResults.entityCount
        if count == 0 {
            return "No PII found"
        } else if count == 1 {
            return "1 PII item"
        } else {
            return "\(count) PII items"
        }
    }
}
