import Foundation

enum AppNavigationState: Equatable {
    /// No documents scanned yet - show empty state
    case empty

    /// Showing sidebar with documents but no selection
    case documentList

    /// Showing sidebar with a selected document
    case documentSelected(UUID)

    /// Actively scanning a document
    case scanning(Document)
}
