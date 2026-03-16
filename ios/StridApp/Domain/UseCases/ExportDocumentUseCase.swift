import Foundation

/// Use case for exporting documents to files
protocol ExportDocumentUseCase {
    func exportAsText(content: String, filename: String) async throws -> URL
    func exportRedactedDocument(_ document: RedactedDocument, originalFilename: String) async throws -> URL
}

final class ExportDocumentUseCaseImpl: ExportDocumentUseCase {

    func exportAsText(content: String, filename: String) async throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let cleanFilename = sanitizeFilename(filename)
        let fileURL = tempDirectory.appendingPathComponent(cleanFilename)

        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func exportRedactedDocument(_ document: RedactedDocument, originalFilename: String) async throws -> URL {
        let timestamp = DateFormatter.filenameDateFormatter.string(from: Date())
        let baseFilename = sanitizeFilename(originalFilename)
        let filename = "\(baseFilename)_redacted_\(timestamp).txt"

        return try await exportAsText(content: document.redactedContent, filename: filename)
    }

    private func sanitizeFilename(_ filename: String) -> String {
        var clean = filename.replacingOccurrences(of: " ", with: "_")
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-."))
        clean = clean.components(separatedBy: allowedCharacters.inverted).joined()

        // Ensure it has .txt extension
        if !clean.hasSuffix(".txt") {
            clean = clean.replacingOccurrences(of: ".txt", with: "") + ".txt"
        }

        return clean.isEmpty ? "document.txt" : clean
    }
}

extension DateFormatter {
    static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter
    }()
}
