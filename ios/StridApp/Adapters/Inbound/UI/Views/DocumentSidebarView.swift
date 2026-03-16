import SwiftUI

/// Sidebar view showing list of scanned documents (like Notes app)
struct DocumentSidebarView: View {
    @Bindable var viewModel: DocumentListViewModel
    @State private var showingFilePicker = false

    var body: some View {
        List(selection: $viewModel.selectedDocumentId) {
            if viewModel.isEmpty {
                ContentUnavailableView {
                    Label("No Scanned Documents", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("Scan your first document to get started")
                }
            } else {
                ForEach(viewModel.filteredDocuments) { doc in
                    DocumentSidebarRow(document: doc)
                        .tag(doc.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.deleteDocument(doc.id)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .navigationTitle("Scanned Documents")
        .searchable(text: $viewModel.searchQuery, prompt: "Search documents")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        viewModel.showingSamplePicker = true
                    } label: {
                        Label("Sample Documents", systemImage: "doc.text.magnifyingglass")
                    }

                    Button {
                        showingFilePicker = true
                    } label: {
                        Label("Import Document", systemImage: "doc.badge.plus")
                    }

                    Button {
                        Task {
                            if let clip = PasteboardHelper.getString(), !clip.isEmpty {
                                await viewModel.createNewDocument(content: clip)
                            }
                        }
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.stridAccent)
                        .font(.title2)
                }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.plainText, .pdf, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        if let text = try? String(contentsOf: url, encoding: .utf8) {
            Task {
                await viewModel.createNewDocument(content: text)
            }
        }
    }
}
