import SwiftUI

#if os(macOS)
import AppKit

/// macOS-specific text view with proper highlighting support
struct HighlightedTextViewMac: NSViewRepresentable {
    let text: String
    let entities: [DetectedPII]

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 30, height: 30)
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        let attributedString = buildHighlightedText()
        textView.textStorage?.setAttributedString(attributedString)
    }

    private func buildHighlightedText() -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text)
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        // Set default attributes
        attributed.addAttribute(.font, value: font, range: NSRange(location: 0, length: attributed.length))
        attributed.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: attributed.length))

        // Highlight PII entities by searching for their text
        for entity in entities {
            let piiText = entity.text

            // Find all occurrences of this PII text in the document
            var searchRange = text.startIndex..<text.endIndex

            while let range = text.range(of: piiText, range: searchRange) {
                let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
                let length = piiText.count

                let nsRange = NSRange(location: startOffset, length: length)
                let boldFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .bold)

                attributed.addAttribute(.foregroundColor, value: NSColor.systemRed, range: nsRange)
                attributed.addAttribute(.font, value: boldFont, range: nsRange)
                attributed.addAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.15), range: nsRange)

                // Move past this occurrence
                guard range.upperBound < text.endIndex else { break }
                searchRange = range.upperBound..<text.endIndex
            }
        }

        return attributed
    }
}
#endif

/// Displays document text with detected PII entities highlighted in red
struct HighlightedTextView: View {
    let text: String
    let entities: [DetectedPII]

    var body: some View {
        #if os(macOS)
        HighlightedTextViewMac(text: text, entities: entities)
        #else
        ScrollView {
            Text(buildHighlightedText())
                .font(.system(.body, design: .monospaced))
                .padding(30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

    #if os(iOS)
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
    #endif
}
