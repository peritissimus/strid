import SwiftUI

/// View shown when documents exist but none is selected (common on macOS)
struct NoSelectionView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Select a Document", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("Choose a scanned document from the sidebar to view its results")
        }
        .background(Color.stridBackground)
    }
}
