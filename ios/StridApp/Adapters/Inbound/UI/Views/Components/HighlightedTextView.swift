import SwiftUI

/// Displays document text with detected PII entities highlighted in red
struct HighlightedTextView: View {
    let text: String
    let entities: [DetectedPII]

    var body: some View {
        ScrollView {
            Text(buildHighlightedText())
                .font(.system(.body, design: .monospaced))
                .padding(30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func buildHighlightedText() -> AttributedString {
        var attributed = AttributedString(text)

        for entity in entities {
            // Convert String.Index range to integer offsets
            let startOffset = text.distance(from: text.startIndex, to: entity.range.lowerBound)
            let endOffset = text.distance(from: text.startIndex, to: entity.range.upperBound)

            // Create AttributedString indices from offsets
            let attrStartIndex = attributed.index(attributed.startIndex, offsetByCharacters: startOffset)
            let attrEndIndex = attributed.index(attributed.startIndex, offsetByCharacters: endOffset)

            // Check bounds
            guard attrStartIndex < attributed.endIndex,
                  attrEndIndex <= attributed.endIndex,
                  attrStartIndex < attrEndIndex else {
                continue
            }

            let attrRange = attrStartIndex..<attrEndIndex

            attributed[attrRange].foregroundColor = .red
            attributed[attrRange].font = .body.monospaced().bold()
            attributed[attrRange].backgroundColor = Color.red.opacity(0.15)
        }

        return attributed
    }
}
