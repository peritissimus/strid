//
//  RedactedTextView.swift
//  StridApp
//
//  Read-only, selectable rendering of the redacted output text, where each
//  detected PII span has been replaced by a placeholder. Used by
//  `ScannedDocumentResultsView` for `ViewMode.redacted`. Layout is identical
//  to `OriginalTextView` so toggling modes keeps the text in place.
//

import SwiftUI

/// Displays the redacted version of the document with PII replaced
struct RedactedTextView: View {
    /// The redacted text (`RedactedDocument.redactedContent`).
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                // Monospaced to match the other two renderings.
                .font(.system(.body, design: .monospaced))
                .padding(30)
                // Fill the width and left-align so short documents do not
                // centre inside the scroll view.
                .frame(maxWidth: .infinity, alignment: .leading)
                // Users may want to copy the safe, redacted text.
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
