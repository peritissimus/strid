//
//  DocumentSidebarView.swift
//  StridApp
//
//  Sidebar column of the text-scanner flow: a searchable list of every
//  scanned document plus a "+" menu for bringing in new text (samples, file,
//  clipboard). Intended to sit in the sidebar slot of a split view alongside
//  `DocumentDetailView`. Selection is bound straight into
//  `DocumentListViewModel.selectedDocumentId`.
//

import SwiftUI

/// Sidebar view showing list of scanned documents (like Notes app)
struct DocumentSidebarView: View {
    /// Shared list view model. `@Bindable` because the list selection and the
    /// search field need two-way bindings into it.
    @Bindable var viewModel: DocumentListViewModel

    /// Drives the `.fileImporter` sheet opened from the "+" menu.
    @State private var showingFilePicker = false

    var body: some View {
        // Binding the selection to the view model means tapping a row updates
        // `selectedDocumentId` without an explicit action; the detail pane
        // reacts to the navigation state the view model derives from it.
        List(selection: $viewModel.selectedDocumentId) {
            ForEach(viewModel.filteredDocuments) { doc in
                DocumentSidebarRow(document: doc)
                    // The tag must match the selection type (UUID).
                    .tag(doc.id)
                    // Full-swipe to delete, as in Mail/Notes. Deletion is
                    // async because it goes through the repository.
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
        .listStyle(.sidebar)
        .navigationTitle("Scanned Documents")
        // Search filters by document body text (see `filteredDocuments`).
        .searchable(text: $viewModel.searchQuery, prompt: "Search documents")
        .toolbar {
            // Single "+" menu grouping the three intake paths. Same actions as
            // the welcome screen, so users can add documents after the first.
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
                        // Empty clipboard is silently ignored.
                        Task {
                            if let clip = PasteboardHelper.getString(), !clip.isEmpty {
                                await viewModel.createNewDocument(content: clip, source: .clipboard)
                            }
                        }
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
            }
        }
        // Single-file picker. PDF is listed but only UTF-8 text is imported.
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.plainText, .pdf, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    /// Reads the picked file as UTF-8 text and hands it to the view model.
    ///
    /// The read happens synchronously inside the security-scoped access
    /// window; only the decoded text crosses into the async `Task`. Files
    /// that are not valid UTF-8 (binary PDFs) are dropped silently.
    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        if let text = try? String(contentsOf: url, encoding: .utf8) {
            Task {
                await viewModel.createNewDocument(content: text, source: .fileImport, fileURL: url)
            }
        }
    }
}
