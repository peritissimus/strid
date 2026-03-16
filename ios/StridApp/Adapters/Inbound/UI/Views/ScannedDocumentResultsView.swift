import SwiftUI
#if os(macOS)
import AppKit
#endif

/// View displaying scan results for a selected scanned document
struct ScannedDocumentResultsView: View {
    let document: ScannedDocument
    @Bindable var viewModel: DocumentListViewModel

    @State private var viewMode: ViewMode = .highlighted
    @State private var showingSummary = false
    @State private var showingDeleteConfirmation = false

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
                    exportDocument()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingSummary) {
            SummarySheet(results: document.scanResults)
        }
        .alert("Delete Document?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteDocument(document.id)
                }
            }
        } message: {
            Text("This document will be permanently deleted.")
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

    private func exportDocument() {
        Task {
            do {
                let url = try await viewModel.exportRedactedDocument(for: document.id)

                #if os(macOS)
                // Use native save panel on macOS
                await MainActor.run {
                    let savePanel = NSSavePanel()
                    savePanel.allowedContentTypes = [.plainText]
                    savePanel.nameFieldStringValue = url.lastPathComponent
                    savePanel.canCreateDirectories = true
                    savePanel.message = "Export redacted document"

                    if savePanel.runModal() == .OK {
                        if let destination = savePanel.url {
                            try? FileManager.default.copyItem(at: url, to: destination)
                        }
                    }
                }
                #elseif os(iOS)
                // Use share sheet on iOS
                await MainActor.run {
                    let activityVC = UIActivityViewController(
                        activityItems: [url],
                        applicationActivities: nil
                    )
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootVC = window.rootViewController {
                        rootVC.present(activityVC, animated: true)
                    }
                }
                #endif
            } catch {
                print("Export error: \(error)")
            }
        }
    }
}
