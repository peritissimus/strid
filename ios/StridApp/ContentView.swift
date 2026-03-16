import SwiftUI

struct ContentView: View {
    @State private var viewModel: DocumentListViewModel
    @State private var visibility: NavigationSplitViewVisibility = .all

    init() {
        let vm = DIContainer.shared.makeDocumentListViewModel()
        _viewModel = State(initialValue: vm)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            DocumentSidebarView(viewModel: viewModel)
        } detail: {
            if let selectedId = viewModel.selectedDocumentId,
               let document = viewModel.scannedDocuments.first(where: { $0.id == selectedId }) {
                ScannedDocumentResultsView(document: document, viewModel: viewModel)
            } else {
                EmptyDetailView(viewModel: viewModel)
            }
        }
        .task {
            await viewModel.loadDocuments()
        }
        .sheet(isPresented: $viewModel.showingSamplePicker) {
            SamplePickerSheet(viewModel: viewModel)
        }
    }
}
