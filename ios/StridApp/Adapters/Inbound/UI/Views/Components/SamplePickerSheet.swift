//
//  SamplePickerSheet.swift
//  StridApp
//
//  Modal sheet listing the bundled sample documents, grouped by category
//  (banking, medical, employment, personal). Presented when
//  `DocumentListViewModel.showingSamplePicker` is true, which the welcome
//  screen and the sidebar "+" menu both set. Tapping a sample scans it
//  immediately and dismisses the sheet.
//

import SwiftUI

/// Sheet for selecting and loading sample documents
struct SamplePickerSheet: View {
    /// Shared list view model; the chosen sample is scanned through it.
    @Bindable var viewModel: DocumentListViewModel

    /// Dismisses the sheet after a selection or on Cancel.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Own NavigationStack so the sheet gets a title bar and toolbar.
        NavigationStack {
            List {
                // One section per category, in `SampleCategory` declaration order.
                ForEach(SampleDocument.SampleCategory.allCases, id: \.self) { category in
                    Section {
                        ForEach(SampleDocument.samples.filter { $0.category == category }) { sample in
                            Button {
                                // Scan first, then dismiss, so the detail pane
                                // is already in the scanning state when the
                                // sheet goes away.
                                Task {
                                    await viewModel.createNewDocument(content: sample.content, source: .sample)
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 16) {
                                    // Category icon, fixed width so titles align.
                                    Image(systemName: category.icon)
                                        .font(.title2)
                                        .frame(width: 40)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(sample.title)
                                            .font(.headline)

                                        Text(sample.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }

                                    Spacer()

                                    // Manual chevron because a Button row does
                                    // not get a disclosure indicator.
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    } header: {
                        Text(category.rawValue)
                    }
                }
            }
            .navigationTitle("Sample Documents")
            // Large title on iOS; no-op on macOS (see ViewExtensions).
            .platformNavigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .platformTopBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        #if os(iOS)
        // Half-height by default, expandable to full, with a grab handle.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #else
        // macOS sheets size to content; give the list a sensible minimum.
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }
}
