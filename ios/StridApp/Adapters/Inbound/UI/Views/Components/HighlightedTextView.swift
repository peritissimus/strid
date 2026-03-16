import SwiftUI

/// Displays document text with detected PII entities highlighted in red
struct HighlightedTextView: View {
    let text: String
    let entities: [DetectedPII]

    var body: some View {
        ScrollView {
            Text(buildHighlightedText())
                .font(.system(.body, design: .monospaced))
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func buildHighlightedText() -> AttributedString {
        var attributed = AttributedString(text)

        for entity in entities {
            if let range = Range(entity.range, in: attributed) {
                attributed[range].foregroundColor = .red
                attributed[range].font = .body.monospaced().bold()
                attributed[range].backgroundColor = Color.red.opacity(0.1)
            }
        }

        return attributed
    }
}
