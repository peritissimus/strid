//
//  ScanningProgressView.swift
//  StridApp
//
//  Interstitial shown in the detail pane while `DocumentListViewModel` is in
//  `AppNavigationState.scanning`. It only lasts as long as detection +
//  redaction take, after which the view model selects the saved result and
//  `DocumentDetailView` swaps in `ScannedDocumentResultsView`.
//

import SwiftUI

/// View shown while actively scanning a document for PII
struct ScanningProgressView: View {
    /// The document being scanned. Currently unused by the layout but kept so
    /// the view can show document-specific info (title, length) later.
    let document: Document

    var body: some View {
        // Spacers centre the spinner and caption vertically.
        VStack(spacing: 30) {
            Spacer()

            // Indeterminate spinner, enlarged because it is the focal point
            // of an otherwise empty pane.
            ProgressView()
                .scaleEffect(1.8)

            VStack(spacing: 8) {
                Text("Analyzing Document")
                    .font(.title2.bold())

                Text("Scanning for personal information...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
