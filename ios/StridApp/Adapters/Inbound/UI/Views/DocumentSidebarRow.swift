import SwiftUI

/// Row view for displaying a scanned document in the sidebar list
struct DocumentSidebarRow: View {
    let document: ScannedDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(document.title)
                .font(.headline)
                .lineLimit(1)

            Text(document.preview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Label(document.entityCountSummary, systemImage: "exclamationmark.shield")
                    .font(.caption)
                    .foregroundStyle(.red)

                Spacer()

                Text(document.scannedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
