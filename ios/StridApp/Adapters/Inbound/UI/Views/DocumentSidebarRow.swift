//
//  DocumentSidebarRow.swift
//  StridApp
//
//  One row of the scanned-documents sidebar (`DocumentSidebarView`). Mirrors
//  the Notes app layout: title and date on the first line, a two-line text
//  preview underneath. Purely presentational; selection and swipe actions are
//  attached by the parent list.
//

import SwiftUI

/// Row view for displaying a scanned document in the sidebar list (Notes-style)
struct DocumentSidebarRow: View {
    /// The record to display. `title` and `preview` are derived properties on
    /// `ScannedDocument` that trim and collapse the original text.
    let document: ScannedDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title left, scan date right. Month + day only; the year is
            // omitted to keep the row compact, as in Notes.
            HStack {
                Text(document.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(document.scannedAt, format: .dateTime.month().day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Two-line preview of the body text. Trailing padding keeps it
            // clear of the list's disclosure/selection chrome.
            Text(document.preview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.trailing, 8)
        }
        // Extra vertical padding gives the rows the taller Notes-like rhythm
        // instead of the default compact list height.
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}
