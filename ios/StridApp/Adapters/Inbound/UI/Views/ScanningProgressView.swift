import SwiftUI

/// View shown while actively scanning a document for PII
struct ScanningProgressView: View {
    let document: Document

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

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
