//
//  DocumentPreview.swift
//  StridApp
//
//  In-card preview of a redaction input or output file, used by
//  `RecordDetailView` to show the "Redacted" / "Original" sides. Dispatches
//  on `RedactionRecord.Kind` to a PDFKit view, an image view or a text view.
//  The PDF and image views have separate UIKit and AppKit implementations
//  under `#if os(...)`; the text view is pure SwiftUI.
//

import SwiftUI
import PDFKit
import StridDocuments

/// Renders a PDF, image or text file inside the card. Same look on iOS and macOS.
struct DocumentPreview: View {
    /// File to render. `RecordDetailView` swaps between input and output URLs.
    let url: URL
    /// Decides which renderer to use.
    let kind: RedactionRecord.Kind

    var body: some View {
        ZStack {
            // Opaque surface behind every renderer so transparent PDFs and
            // letterboxed images sit on the same dark panel.
            Theme.surface
            switch kind {
            case .pdf: PDFKitView(url: url)
            case .image: ImageFileView(url: url)
            // Word files are shown as extracted text, not laid-out pages.
            case .text, .docx: TextFileView(url: url)
            }
        }
    }
}

/// Scrollable monospaced dump of a text-like file's contents.
struct TextFileView: View {
    let url: URL
    /// Extracted text. Empty until the task runs or if extraction fails.
    @State private var text = ""
    var body: some View {
        ScrollView {
            Text(text).font(Theme.mono(12)).foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Extra top padding clears the REDACTED/ORIGINAL badge that
                // RecordDetailView overlays in the top-left corner.
                .padding(16).padding(.top, 36)
                .textSelection(.enabled)
        }
        // Keyed on the URL so flipping between original and redacted
        // re-extracts; `DocumentText.extract` handles .txt and .docx.
        .task(id: url) { text = (try? DocumentText.extract(from: url)) ?? "" }
    }
}

#if os(iOS)
import UIKit

/// UIKit `PDFView` wrapper configured for continuous vertical paging.
struct PDFKitView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        // Fit page width to the card; user can still pinch-zoom.
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = UIColor(Theme.surface)
        // Page shadows look wrong on a black panel.
        v.pageShadowsEnabled = false
        return v
    }
    /// Only reload the document when the URL actually changes, so SwiftUI
    /// re-renders do not reset the scroll position.
    func updateUIView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url { v.document = PDFDocument(url: url) }
    }
}

/// Zoomable image preview. Scrolls in both axes and starts centred so a
/// scaled-to-fit image sits in the middle of the card.
struct ImageFileView: View {
    let url: URL
    var body: some View {
        if let img = UIImage(contentsOfFile: url.path) {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: img).resizable().scaledToFit()
            }
            .defaultScrollAnchor(.center)
        } else { Text("Can't show image").foregroundStyle(Theme.ink4) }
    }
}
#elseif os(macOS)
import AppKit

/// AppKit `PDFView` wrapper; mirrors the iOS configuration minus the
/// page-shadow flag, which has no AppKit counterpart here.
struct PDFKitView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = NSColor(Theme.surface)
        return v
    }
    /// Only reload when the URL changes, preserving scroll position.
    func updateNSView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url { v.document = PDFDocument(url: url) }
    }
}

/// Image preview for macOS. No default scroll anchor API is used here; the
/// image simply scrolls from the top-left.
struct ImageFileView: View {
    let url: URL
    var body: some View {
        if let img = NSImage(contentsOf: url) {
            ScrollView([.horizontal, .vertical]) { Image(nsImage: img).resizable().scaledToFit() }
        } else { Text("Can't show image").foregroundStyle(Theme.ink4) }
    }
}
#endif
