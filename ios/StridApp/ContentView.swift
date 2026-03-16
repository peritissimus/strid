import SwiftUI

struct ContentView: View {
    @State private var viewModel: DocumentListViewModel

    init() {
        let vm = DIContainer.shared.makeDocumentListViewModel()
        _viewModel = State(initialValue: vm)
    }

    var body: some View {
        NavigationSplitView(
            columnVisibility: .constant(.all),
            sidebar: {
                DocumentSidebarView(viewModel: viewModel)
            },
            detail: {
                DocumentDetailView(viewModel: viewModel)
            }
        )
        .task {
            await viewModel.loadDocuments()
        }
        .sheet(isPresented: $viewModel.showingSamplePicker) {
            SamplePickerSheet(viewModel: viewModel)
        }
    }
}
