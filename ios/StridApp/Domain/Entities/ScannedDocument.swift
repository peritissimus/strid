import Foundation

/// Represents a document that has been scanned for PII, bundling the original document,
/// scan results, and metadata for persistence and display in the sidebar
struct ScannedDocument: Identifiable, Equatable, Codable {
    let id: UUID
    let originalDocument: Document
    let scanResults: ScanResults
    let scannedAt: Date

    init(
        id: UUID = UUID(),
        originalDocument: Document,
        scanResults: ScanResults,
        scannedAt: Date = Date()
    ) {
        self.id = id
        self.originalDocument = originalDocument
        self.scanResults = scanResults
        self.scannedAt = scannedAt
    }

    // MARK: - Display Properties

    /// Title for display in sidebar (first line or first 50 chars)
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
    var preview: String {
        let content = originalDocument.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove newlines and collapse whitespace for preview
        let normalized = content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")

        return String(normalized.prefix(150))
    }

    /// Entity count summary for sidebar
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
