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
            // Stats header
            statsHeaderView

            Divider()
                .background(Color.stridLightGray)

            contentForViewMode
        }
        .navigationTitle("Scan Results")
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .platformTopBarTrailing) {
                Button {
                    Task {
                        await exportDocument()
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
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

    private var statsHeaderView: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(document.scanResults.entityCount)")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.red)

                    Text("PII Items Found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showingSummary = true
                } label: {
                    Label("Details", systemImage: "list.bullet.rectangle.portrait")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Picker("View Mode", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
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
