import SwiftUI

/// View shown while actively scanning a document for PII
struct ScanningProgressView: View {
    let document: Document

    var body: some View {
        ZStack {
            Color.stridMonochromeGradient
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                ProgressView()
                    .scaleEffect(1.8)
                    .tint(Color.stridWhite)

                VStack(spacing: 8) {
                    Text("Analyzing Document")
                        .font(.title2.bold())
                        .foregroundStyle(Color.stridWhite)

                    Text("Scanning for personal information...")
                        .font(.subheadline)
                        .foregroundStyle(Color.stridWhite.opacity(0.7))
                }

                Spacer()
            }
        }
    }
}
