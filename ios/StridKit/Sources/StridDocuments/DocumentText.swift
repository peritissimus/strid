//
// DocumentText.swift
// StridDocuments
//
// Read-only text extraction. Used wherever the caller wants the engine's *findings* without
// producing a redacted file: the CLI `detect` and `eval` commands, dry runs, and UI previews.
// Mirrors the per-format decisions the redaction handlers make (same DOCX type resolution, same
// PDF text-layer-vs-OCR heuristic) so that what is previewed matches what would be redacted.
//
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import StridKit

/// Text extraction for detection and preview. Pages are joined with form feeds.
public enum DocumentText {
    /// Extracts the text the redaction pipeline would scan for `url`.
    ///
    /// Per format:
    ///   - text: read as UTF-8.
    ///   - docx/rtf: `NSAttributedString.string`.
    ///   - image: Vision OCR of the first frame.
    ///   - pdf: per page, the PDFKit text layer if present and usable, else OCR of a 3x raster.
    ///     Pages are joined with `\u{0C}` (form feed) so page boundaries are recoverable.
    ///
    /// - Parameters:
    ///   - url: Document to read.
    ///   - options: Supplies the PDF password and the `ocrFallback` switch.
    /// - Returns: The extracted text.
    /// - Throws: `DocumentRedactionError` for unsupported or unreadable inputs, password errors
    ///   for locked PDFs, and Vision errors from OCR.
    public static func extract(from url: URL, options: DocumentOptions = DocumentOptions()) throws -> String {
        guard let kind = DocumentKind.detect(url: url) else {
            throw DocumentRedactionError.unsupportedFormat(url.pathExtension)
        }
        switch kind {
        case .text:
            guard let s = try? String(contentsOf: url, encoding: .utf8) else {
                throw DocumentRedactionError.unreadable(url)
            }
            return s
        case .docx:
            let docType = try AttributedDocumentHandler.documentType(for: url)
            guard let a = try? NSAttributedString(url: url, options: [.documentType: docType], documentAttributes: nil) else {
                throw DocumentRedactionError.unreadable(url)
            }
            return a.string
        case .image:
            // Only the first image in the container is considered (multi-frame HEIC/GIF are rare here).
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                throw DocumentRedactionError.unreadable(url)
            }
            return try OCR.recognise(img).text
        case .pdf:
            let doc = try PDFDocumentHandler.open(url, password: options.password)
            var pages: [String] = []
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                // Same decision as PDFDocumentHandler.redact: trust the text layer when it is
                // non-empty and (unless the fallback is disabled) passes the sanity heuristic.
                if let s = page.string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !options.ocrFallback || PDFDocumentHandler.textLayerLooksUsable(s) {
                    pages.append(s)
                } else {
                    // Scanned or broken page: rasterise at 3x (~216 dpi) and OCR it.
                    let raster = PDFDocumentHandler(scale: 3).render(page, box: page.bounds(for: .mediaBox))
                    pages.append(try OCR.recognise(raster).text)
                }
            }
            return pages.joined(separator: "\u{0C}")
        }
    }
}
