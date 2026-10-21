//
//  DocumentDetailView.swift
//  StridApp
//
//  Detail-pane router for the text-scanner flow. It is intended for the
//  detail slot of a split view next to `DocumentSidebarView`, and it maps
//  each `AppNavigationState` case to a concrete screen. It holds no state of
//  its own; everything comes from `DocumentListViewModel`.
//

import SwiftUI

/// Router view that displays the appropriate detail view based on navigation state
struct DocumentDetailView: View {
    /// Shared list view model. `@Bindable` so it can be passed on to child
    /// views that need bindings into it.
    @Bindable var viewModel: DocumentListViewModel

    var body: some View {
        // `Group` lets the switch return heterogeneous views from `body`.
        Group {
            switch viewModel.navigationState {
            case .empty:
                // Nothing scanned yet: welcome screen with intake buttons.
                EmptyDetailView(viewModel: viewModel)

            case .documentList:
                // Documents exist, nothing selected.
                NoSelectionView()

            case .documentSelected(let id):
                // Look the record up by id at render time rather than storing
                // the document in the navigation state, so the detail always
                // reflects the latest list. If the id is stale (just deleted)
                // fall back to the no-selection placeholder.
                if let document = viewModel.scannedDocuments.first(where: { $0.id == id }) {
                    ScannedDocumentResultsView(
                        document: document,
                        viewModel: viewModel
                    )
                } else {
                    NoSelectionView()
                }

            case .scanning(let doc):
                // Scan in flight: spinner until the result is saved and selected.
                ScanningProgressView(document: doc)
            }
        }
    }
}
