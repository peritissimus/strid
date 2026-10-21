//
//  HighlightedTextView.swift
//  StridApp
//
//  Renders a document's source text with every detected PII span drawn in
//  bold red on a translucent red background. Used by
//  `ScannedDocumentResultsView` for `ViewMode.highlighted`, which is the
//  default mode right after a scan.
//
//  Two implementations live here because the platforms differ:
//  - iOS: a SwiftUI `Text` built from an `AttributedString`, using the exact
//    `String.Index` ranges reported by the detector.
//  - macOS: an `NSTextView` wrapped in `NSViewRepresentable`. SwiftUI `Text`
//    on macOS did not reliably render background colours and wrapping for
//    long documents, so AppKit is used instead. It builds an
//    `NSAttributedString` by searching for each entity's text, which also
//    highlights repeated occurrences.
//

import SwiftUI

#if os(macOS)
import AppKit

/// macOS-specific text view with proper highlighting support
struct HighlightedTextViewMac: NSViewRepresentable {
    /// Full source text.
    let text: String

    /// Detections to highlight. Only `entity.text` is used on macOS; ranges
    /// are rediscovered by substring search (see `buildHighlightedText()`).
    let entities: [DetectedPII]

    /// Builds the scroll view + text view pair once. Attributes are applied
    /// in `updateNSView`, so this only configures appearance and layout.
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        // Read-only but selectable so users can copy text.
        textView.isEditable = false
        textView.isSelectable = true
        // Clear background lets the SwiftUI window background show through.
        textView.drawsBackground = true
        textView.backgroundColor = .clear
        // 30pt inset matches the `.padding(30)` used by the iOS and sibling views.
        textView.textContainerInset = NSSize(width: 30, height: 30)
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        scrollView.documentView = textView
        // Vertical scrolling only; text wraps to the width instead.
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        // Make the container track the scroll view width so text wraps and
        // grows vertically without bound.
        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        }

        return scrollView
    }

    /// Replaces the text storage with a freshly built attributed string
    /// whenever SwiftUI re-renders (new document or new entities).
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        let attributedString = buildHighlightedText()
        textView.textStorage?.setAttributedString(attributedString)
    }

    /// Builds the attributed string: monospaced label-coloured text with each
    /// PII occurrence in bold red over a 15% red background.
    ///
    /// Occurrences are found by substring search rather than by the detector's
    /// `range`, so every repeat of a detected value is highlighted, not just
    /// the first. `NSRange` locations are computed from `String.distance`,
    /// which counts Characters; this matches `NSAttributedString` for the
    /// mostly-ASCII bank statements the app targets.
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
    /// Full source text.
    let text: String

    /// Detections whose ranges (iOS) or text (macOS) should be highlighted.
    let entities: [DetectedPII]

    var body: some View {
        #if os(macOS)
        // Delegate to AppKit; see file header for why.
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
    /// Builds an `AttributedString` with each detected range styled red.
    ///
    /// `DetectedPII.range` is a `Range<String.Index>` into `text`, but
    /// `AttributedString` has its own index type. The conversion goes through
    /// integer character offsets: distance in the `String`, then
    /// `index(_:offsetByCharacters:)` in the `AttributedString`. A bounds
    /// check skips any range that no longer fits (defensive against stale or
    /// inverted ranges) rather than trapping.
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

            // Same treatment as macOS: red bold text on a 15% red wash.
            attributed[attrRange].foregroundColor = .red
            attributed[attrRange].font = .body.monospaced().bold()
            attributed[attrRange].backgroundColor = Color.red.opacity(0.15)
        }

        return attributed
    }
    #endif
}
