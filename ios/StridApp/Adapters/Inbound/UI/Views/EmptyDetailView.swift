//
//  EmptyDetailView.swift
//  StridApp
//
//  Welcome screen for the text-scanner flow. `DocumentDetailView` shows it in
//  the detail pane when `DocumentListViewModel.navigationState == .empty`,
//  i.e. nothing has been scanned yet. It offers the three ways to get text
//  into the app: bundled samples, a file picker, and the clipboard.
//

import SwiftUI

/// View shown when no documents have been scanned yet (welcome screen)
struct EmptyDetailView: View {
    /// Shared list view model. `@Bindable` so the sample-picker flag can be
    /// toggled directly and so async actions can be dispatched on it.
    @Bindable var viewModel: DocumentListViewModel

    /// Drives the `.fileImporter` sheet. Local to this view because the file
    /// picker is a transient UI concern, not app state.
    @State private var showingFilePicker = false

    var body: some View {
        // Spacers above and below centre the content vertically regardless
        // of window height.
        VStack(spacing: 40) {
            Spacer()

            // Hero: shield icon, app title, one-line pitch.
            VStack(spacing: 24) {
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    Text("PII Scanner")
                        .font(.largeTitle.bold())

                    Text("Detect and redact personal information\nfrom your documents")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Three equal-width call-to-action buttons. The sample browser is
            // prominent because it is the fastest way to see the app work.
            VStack(spacing: 14) {
                Button {
                    // The picker sheet itself is attached higher up the tree;
                    // this just flips the shared flag.
                    viewModel.showingSamplePicker = true
                } label: {
                    Label("Browse Sample Documents", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    showingFilePicker = true
                } label: {
                    Label("Import Document", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    // Read the pasteboard synchronously, then scan in a Task
                    // because `createNewDocument` is async. Empty clipboard
                    // is silently ignored.
                    Task {
                        if let clip = PasteboardHelper.getString(), !clip.isEmpty {
                            await viewModel.createNewDocument(content: clip, source: .clipboard)
                        }
                    }
                } label: {
                    Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        // Single-file picker. PDF is allowed in the type list but only files
        // that decode as UTF-8 text are actually imported (see below).
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
    /// Files outside the sandbox require a security-scoped access window, so
    /// the read happens synchronously inside `startAccessing...` /
    /// `stopAccessing...`. Only the text is captured by the `Task`; the URL
    /// is passed along for provenance but is not read again. Binary PDFs fail
    /// the UTF-8 decode and are dropped without feedback.
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
