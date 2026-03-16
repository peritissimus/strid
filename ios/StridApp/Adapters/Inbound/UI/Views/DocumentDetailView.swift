import SwiftUI

/// Router view that displays the appropriate detail view based on navigation state
struct DocumentDetailView: View {
    @Bindable var viewModel: DocumentListViewModel

    var body: some View {
        Group {
            switch viewModel.navigationState {
            case .empty:
                EmptyDetailView(viewModel: viewModel)

            case .documentList:
                NoSelectionView()

            case .documentSelected(let id):
                if let document = viewModel.scannedDocuments.first(where: { $0.id == id }) {
                    ScannedDocumentResultsView(
                        document: document,
                        viewModel: viewModel
                    )
                } else {
                    NoSelectionView()
                }

            case .scanning(let doc):
                ScanningProgressView(document: doc)
            }
        }
    }
}
