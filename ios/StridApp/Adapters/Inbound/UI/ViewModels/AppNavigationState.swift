//
//  AppNavigationState.swift
//  StridApp
//
//  Navigation state for the sidebar + detail text-scanner flow. Owned by
//  `DocumentListViewModel` and switched on by `DocumentDetailView` to decide
//  which detail pane to show. It is derived state: the view model recomputes
//  it from the scanned-document list and the current selection in
//  `updateNavigationState()`, and sets `.scanning` explicitly while a scan runs.
//

import Foundation

/// What the detail pane of the text-scanner flow should display.
///
/// `Equatable` so SwiftUI can diff it cheaply and so tests can assert on it.
enum AppNavigationState: Equatable {
    /// No documents scanned yet. `DocumentDetailView` shows `EmptyDetailView`,
    /// the welcome screen with import / sample / paste buttons.
    case empty

    /// Documents exist in the sidebar but none is selected. Shows
    /// `NoSelectionView`. Mostly seen on macOS where the split view starts
    /// with no selection.
    case documentList

    /// A scanned document with this id is selected. Shows
    /// `ScannedDocumentResultsView` for the matching `ScannedDocument`.
    case documentSelected(UUID)

    /// A scan is in progress for `Document`. Shows `ScanningProgressView`
    /// until the scan finishes and the result is saved and selected.
    case scanning(Document)
}
