//
//  NoSelectionView.swift
//  StridApp
//
//  Placeholder for the detail pane when documents exist but none is selected
//  (`AppNavigationState.documentList`). Also used by `DocumentDetailView` as a
//  fallback when the selected id no longer matches a document, e.g. right
//  after a delete. On iPhone the split view normally pushes straight to the
//  detail, so this is mostly seen on iPad and macOS.
//

import SwiftUI

/// View shown when documents exist but none is selected (common on macOS)
struct NoSelectionView: View {
    var body: some View {
        // System empty-state component: centred icon, title and description
        // with platform-appropriate styling for free.
        ContentUnavailableView {
            Label("Select a Document", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("Choose a scanned document from the sidebar to view its results")
        }
    }
}
