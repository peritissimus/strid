//
//  OriginalTextView.swift
//  StridApp
//
//  Read-only, selectable rendering of a document's source text. Used by
//  `ScannedDocumentResultsView` for `ViewMode.original`. Shares its layout
//  with `RedactedTextView` so switching modes does not shift the text.
//

import SwiftUI

/// Displays the original, unmodified document text
struct OriginalTextView: View {
    /// The full source text to show.
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                // Monospaced so columns in bank statements and CSVs line up,
                // and so character offsets match the highlighted view.
                .font(.system(.body, design: .monospaced))
                .padding(30)
                // Fill the width and left-align; otherwise short documents
                // would centre inside the scroll view.
                .frame(maxWidth: .infinity, alignment: .leading)
                // Let users copy text out.
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
