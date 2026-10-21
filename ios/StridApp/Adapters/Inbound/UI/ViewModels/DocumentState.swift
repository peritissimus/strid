//
//  DocumentState.swift
//  StridApp
//
//  UI-facing state types shared by the text-scanner flow (`DocumentViewModel`,
//  `DocumentListViewModel`, `ScannedDocumentResultsView`, `SummarySheet`).
//
//  Three small types live here:
//  - `DocumentState`: the lifecycle of a single in-memory document as it goes
//    from "nothing loaded" to "scanned with results".
//  - `ViewMode`: which rendering of a document the user is looking at
//    (original / highlighted / redacted). Drives the segmented picker.
//  - `ScanResults`: the pair of outputs produced by one scan (detected
//    entities + redacted text), persisted as part of `ScannedDocument`.
//

import Foundation
import StridKit

// MARK: - DocumentState

/// Lifecycle of the single document shown by `DocumentViewModel`.
///
/// The state machine is linear: `.empty` -> `.loaded` -> `.processing` -> `.scanned`,
/// with `goBackToDocument()` allowing `.scanned` -> `.loaded` and `clearDocument()`
/// returning to `.empty` from anywhere. Each non-empty case carries the `Document`
/// so views never have to keep a separate copy in sync.
enum DocumentState: Equatable {
    /// Nothing has been imported yet. Views show a welcome / picker UI.
    case empty

    /// A document has been imported but not scanned. The user can read the
    /// original text or trigger a scan.
    case loaded(Document)

    /// A scan is in flight. Views show a progress indicator and disable actions
    /// that would mutate the document.
    case processing(Document)

    /// Scanning finished. `results` holds the detected entities and the redacted
    /// text; views switch to the highlighted mode by default.
    case scanned(Document, results: ScanResults)

    /// The document associated with this state, if any.
    ///
    /// Collapses the three "has a document" cases so callers can ask for the
    /// current document without pattern matching every time.
    var document: Document? {
        switch self {
        case .empty: return nil
        case .loaded(let doc), .processing(let doc), .scanned(let doc, _): return doc
        }
    }
}

// MARK: - ViewMode

/// Which rendering of a document is currently displayed.
///
/// The raw value doubles as the user-facing segment title in the segmented
/// picker (see `ScannedDocumentResultsView`), and `CaseIterable` lets that
/// picker iterate the modes in declaration order.
enum ViewMode: String, CaseIterable {
    /// Plain, unmodified source text (`OriginalTextView`).
    case original = "Original"

    /// Source text with detected PII spans drawn in red (`HighlightedTextView`).
    /// Selected automatically once a scan finishes.
    case highlighted = "Highlighted"

    /// The redacted output with PII replaced by placeholders (`RedactedTextView`).
    case redacted = "Redacted"

    /// SF Symbol name for the mode, for toolbars or menus that want an icon
    /// alongside (or instead of) the text label.
    var icon: String {
        switch self {
        case .original: return "doc.text"
        case .highlighted: return "highlighter"
        case .redacted: return "eye.slash"
        }
    }
}

// MARK: - ScanResults

/// Everything a single scan produced for one document.
///
/// Built by the view models after running the detect and redact use cases
/// concurrently, then stored inside `ScannedDocument` so results survive
/// relaunches. `Codable` because the repository serialises it to disk.
struct ScanResults: Codable {
    /// Every PII span the detector found, in detector order.
    let detectedEntities: [DetectedPII]

    /// The document with each detected span replaced by a placeholder.
    let redactedDocument: RedactedDocument

    /// Total number of detections. Shown in stats bars and the summary sheet.
    var entityCount: Int { detectedEntities.count }

    /// Detections bucketed by entity type, e.g. `[.email: 3, .inPAN: 1]`.
    ///
    /// Used by `SummarySheet` to render the "By Category" section. Recomputed
    /// on each access; the entity list is small so this is cheap.
    var summary: [PIIEntityType: Int] {
        Dictionary(grouping: detectedEntities, by: \.type)
            .mapValues { $0.count }
    }
}

/// Cheap equality used by `DocumentState: Equatable` and SwiftUI diffing.
///
/// Compares the redacted document plus the number of detections rather than
/// every `DetectedPII` value. Two scans of the same text that yield the same
/// redacted output and the same count are treated as identical, which is all
/// the UI needs to decide whether to re-render.
extension ScanResults: Equatable {
    static func == (lhs: ScanResults, rhs: ScanResults) -> Bool {
        lhs.redactedDocument == rhs.redactedDocument &&
        lhs.detectedEntities.count == rhs.detectedEntities.count
    }
}
