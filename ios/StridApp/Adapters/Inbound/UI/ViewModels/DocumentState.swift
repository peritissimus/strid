import Foundation
import StridKit

enum DocumentState: Equatable {
    case empty
    case loaded(Document)
    case processing(Document)
    case scanned(Document, results: ScanResults)

    var document: Document? {
        switch self {
        case .empty: return nil
        case .loaded(let doc), .processing(let doc), .scanned(let doc, _): return doc
        }
    }
}

enum ViewMode: String, CaseIterable {
    case original = "Original"
    case highlighted = "Highlighted"
    case redacted = "Redacted"

    var icon: String {
        switch self {
        case .original: return "doc.text"
        case .highlighted: return "highlighter"
        case .redacted: return "eye.slash"
        }
    }
}

struct ScanResults {
    let detectedEntities: [DetectedPII]
    let redactedDocument: RedactedDocument

    var entityCount: Int { detectedEntities.count }

    var summary: [PIIEntityType: Int] {
        Dictionary(grouping: detectedEntities, by: \.type)
            .mapValues { $0.count }
    }
}

extension ScanResults: Equatable {
    static func == (lhs: ScanResults, rhs: ScanResults) -> Bool {
        lhs.redactedDocument == rhs.redactedDocument &&
        lhs.detectedEntities.count == rhs.detectedEntities.count
    }
}
