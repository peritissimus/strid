//
//  ExportDocumentUseCase.swift
//  StridApp
//
//  Hexagonal architecture role: **use case** (application service).
//
//  Writes text to a temporary file so it can be handed to the system share
//  sheet or a document exporter. This use case talks to `FileManager`
//  directly rather than through a port; the file system here is a
//  short-lived scratch area, not a domain repository.
//

import Foundation

/// Use case for exporting documents to files
protocol ExportDocumentUseCase {
    /// Writes arbitrary text to a `.txt` file in the temporary directory.
    ///
    /// - Parameters:
    ///   - content: Text to write (UTF-8).
    ///   - filename: Desired filename; it will be sanitised and given a
    ///     `.txt` extension if missing.
    /// - Returns: URL of the written file.
    /// - Throws: `String.write` errors if the file cannot be created.
    func exportAsText(content: String, filename: String) async throws -> URL

    /// Writes a redacted document to a timestamped `.txt` file.
    ///
    /// - Parameters:
    ///   - document: The redaction result whose `redactedContent` is exported.
    ///   - originalFilename: Base name used to build the output filename.
    /// - Returns: URL of the written file, named
    ///   `<base>_redacted_<yyyy-MM-dd_HHmmss>.txt`.
    /// - Throws: `String.write` errors if the file cannot be created.
    func exportRedactedDocument(_ document: RedactedDocument, originalFilename: String) async throws -> URL
}

/// Default implementation backed by `FileManager.default.temporaryDirectory`.
final class ExportDocumentUseCaseImpl: ExportDocumentUseCase {

    func exportAsText(content: String, filename: String) async throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let cleanFilename = sanitizeFilename(filename)
        let fileURL = tempDirectory.appendingPathComponent(cleanFilename)

        // Atomic write so a half-written file is never shared.
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func exportRedactedDocument(_ document: RedactedDocument, originalFilename: String) async throws -> URL {
        let timestamp = DateFormatter.filenameDateFormatter.string(from: Date())
        let baseFilename = sanitizeFilename(originalFilename)
        // `baseFilename` already ends in ".txt" (sanitizeFilename guarantees
        // it), so the resulting name looks like "report.txt_redacted_<ts>.txt".
        let filename = "\(baseFilename)_redacted_\(timestamp).txt"

        return try await exportAsText(content: document.redactedContent, filename: filename)
    }

    /// Makes a user-supplied name safe to use as a filename.
    ///
    /// Steps: spaces become underscores; anything outside `[A-Za-z0-9_-.]` is
    /// stripped; a single `.txt` suffix is enforced; an empty result falls
    /// back to `document.txt`.
    ///
    /// - Parameter filename: Raw name from the UI or the import source.
    /// - Returns: A non-empty filename ending in `.txt`.
    private func sanitizeFilename(_ filename: String) -> String {
        var clean = filename.replacingOccurrences(of: " ", with: "_")
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-."))
        clean = clean.components(separatedBy: allowedCharacters.inverted).joined()

        // Ensure it has .txt extension
        // (also removes any embedded ".txt" so "a.txt.b" -> "a.b.txt")
        if !clean.hasSuffix(".txt") {
            clean = clean.replacingOccurrences(of: ".txt", with: "") + ".txt"
        }

        return clean.isEmpty ? "document.txt" : clean
    }
}

extension DateFormatter {
    /// Shared formatter producing filesystem-safe timestamps such as
    /// `2024-03-15_143005`. Static so the (expensive) formatter is built once.
    static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter
    }()
}
