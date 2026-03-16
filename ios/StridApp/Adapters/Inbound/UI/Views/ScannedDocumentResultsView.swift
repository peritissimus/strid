import SwiftUI

/// View displaying scan results for a selected scanned document
struct ScannedDocumentResultsView: View {
    let document: ScannedDocument
    @Bindable var viewModel: DocumentListViewModel

    @State private var viewMode: ViewMode = .highlighted
    @State private var showingSummary = false
    @State private var exportedFileURL: URL?
    @State private var showingShareSheet = false
    @State private var exportError: Error?
    @State private var showingExportError = false

    var body: some View {
        VStack(spacing: 0) {
            // Compact stats bar
            compactStatsBar

            contentForViewMode
        }
        .navigationTitle("")
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Button {
                    showingSummary = true
                } label: {
                    Label("Details", systemImage: "info.circle")
                }

                Button {
                    Task {
                        await exportDocument()
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showingSummary) {
            SummarySheet(results: document.scanResults)
        }
        .sheet(isPresented: $showingShareSheet, onDismiss: {
            exportedFileURL = nil
        }) {
            if let url = exportedFileURL {
                ShareSheet(activityItems: [url])
                    #if os(iOS)
                    .presentationDetents([.medium])
                    #endif
            }
        }
        .alert("Export Error", isPresented: $showingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = exportError {
                Text(error.localizedDescription)
            }
        }
    }

    private var compactStatsBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.red)
                .imageScale(.small)

            Text("\(document.scanResults.entityCount) PII items found")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var contentForViewMode: some View {
        switch viewMode {
        case .original:
            OriginalTextView(text: document.originalDocument.content)
        case .highlighted:
            HighlightedTextView(
                text: document.originalDocument.content,
                entities: document.scanResults.detectedEntities
            )
        case .redacted:
            RedactedTextView(text: document.scanResults.redactedDocument.redactedContent)
        }
    }

    private func exportDocument() async {
        do {
            let url = try await viewModel.exportRedactedDocument(for: document.id)
            exportedFileURL = url
            showingShareSheet = true
        } catch {
            exportError = error
            showingExportError = true
        }
    }
}
