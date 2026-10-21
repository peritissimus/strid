//
//  ScannedDocumentResultsView.swift
//  StridApp
//
//  Results screen for one `ScannedDocument` in the text-scanner flow. Shown by
//  `DocumentDetailView` when a document is selected. It offers a segmented
//  switch between original / highlighted / redacted text, a stats strip with
//  the detection count, and toolbar actions for details (summary sheet),
//  export (save panel on macOS, share sheet on iOS) and delete (with
//  confirmation).
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// View displaying scan results for a selected scanned document
struct ScannedDocumentResultsView: View {
    /// The record being shown. Passed by value; the parent re-resolves it
    /// from the list on every render.
    let document: ScannedDocument

    /// Shared list view model, used for export and delete.
    @Bindable var viewModel: DocumentListViewModel

    /// Which rendering is displayed. Starts on `.highlighted` because the
    /// user has just scanned and wants to see what was found. Local state so
    /// each selected document starts fresh.
    @State private var viewMode: ViewMode = .highlighted

    /// Presents `SummarySheet` with the per-type breakdown.
    @State private var showingSummary = false

    /// Presents the destructive-delete confirmation alert.
    @State private var showingDeleteConfirmation = false

    var body: some View {
        // Zero spacing so the stats bar sits flush against the text area.
        VStack(spacing: 0) {
            // Compact stats bar
            compactStatsBar

            contentForViewMode
        }
        // Empty title keeps the navigation bar but avoids a redundant heading;
        // the sidebar row already names the document.
        .navigationTitle("")
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // Segmented mode picker. Fixed width so the three segments do
                // not collapse to icons in a narrow toolbar.
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

                // Destructive role tints the icon red; the actual delete waits
                // for the confirmation alert below.
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
        // Two-step delete. After deletion the view model repairs the
        // selection, which causes `DocumentDetailView` to swap this view out.
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

    /// One-line strip under the toolbar: red shield + "N PII items found".
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

    /// The text area for the current `viewMode`. `@ViewBuilder` because each
    /// case returns a different concrete view type.
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

    /// Exports the redacted text and hands the file to the platform's native
    /// "get it out of the app" UI.
    ///
    /// The export itself is async (file write), so the whole flow runs in a
    /// `Task`. The platform UI must run on the main actor: macOS uses a modal
    /// `NSSavePanel` and copies the temp file to the chosen location; iOS
    /// presents a `UIActivityViewController` from the first window's root
    /// view controller because there is no SwiftUI share-sheet modifier in
    /// this flow. Errors are only logged.
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

                    // runModal blocks until the user picks a location or cancels.
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
                    // Walk the scene graph to find a presenter. Single-window
                    // app, so the first scene/window is the right one.
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
