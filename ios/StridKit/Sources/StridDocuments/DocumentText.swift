import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import StridKit

/// Text extraction for detection and preview. Pages are joined with form feeds.
public enum DocumentText {
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
            let docType: NSAttributedString.DocumentType = url.pathExtension.lowercased() == "rtf" ? .rtf : .officeOpenXML
            guard let a = try? NSAttributedString(url: url, options: [.documentType: docType], documentAttributes: nil) else {
                throw DocumentRedactionError.unreadable(url)
            }
            return a.string
        case .image:
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
                if let s = page.string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !options.ocrFallback || PDFDocumentHandler.textLayerLooksUsable(s) {
                    pages.append(s)
                } else {
                    let raster = PDFDocumentHandler(scale: 3).render(page, box: page.bounds(for: .mediaBox))
                    pages.append(try OCR.recognise(raster).text)
                }
            }
            return pages.joined(separator: "\u{0C}")
        }
    }
}
