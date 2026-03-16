import SwiftUI

/// Row view for displaying a scanned document in the sidebar list (Notes-style)
struct DocumentSidebarRow: View {
    let document: ScannedDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(document.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(document.scannedAt, format: .dateTime.month().day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(document.preview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.trailing, 8)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}
