import SwiftUI

struct ContentView: View {
    @State private var viewModel: DocumentListViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init() {
        let vm = DIContainer.shared.makeDocumentListViewModel()
        _viewModel = State(initialValue: vm)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            DocumentSidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        } detail: {
            DocumentDetailView(viewModel: viewModel)
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            await viewModel.loadDocuments()
        }
        .sheet(isPresented: $viewModel.showingSamplePicker) {
            SamplePickerSheet(viewModel: viewModel)
        }
    }
}
