import SwiftUI

/// Displays the original, unmodified document text
struct OriginalTextView: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Color.stridText)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .background(Color.stridBackground)
    }
}
