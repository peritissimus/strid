import CoreGraphics
import Foundation
import PDFKit
import StridKit

/// PDF in, PDF out.
///
/// Every page is rasterised and black boxes are painted over PII, then a fresh PDF is built from the
/// rasters. This is a *true* redaction: the underlying text is gone, not hidden under an annotation.
/// Text-layer pages use PDFKit to locate spans exactly; scanned pages (and pages whose text layer is
/// unusable) fall back to Vision OCR.
public struct PDFDocumentHandler: DocumentHandler {
    /// Render scale relative to 72 dpi. 3 gives ~216 dpi, enough for OCR and readable output.
    public var scale: CGFloat = 3

    public init(scale: CGFloat = 3) { self.scale = scale }

    // MARK: Opening

    /// Opens a PDF, unlocking it when a password is supplied. Throws a specific error when one is needed.
    public static func open(_ url: URL, password: String?) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw DocumentRedactionError.unreadable(url) }
        if doc.isLocked {
            guard let password, !password.isEmpty else { throw DocumentRedactionError.passwordRequired(url) }
            guard doc.unlock(withPassword: password) else { throw DocumentRedactionError.wrongPassword(url) }
        }
        return doc
    }

    /// Inspects a document for things the user must know about before we flatten it.
    static func inspect(_ doc: PDFDocument, options: DocumentOptions) -> [String] {
        var w: [String] = []
        if doc.isEncrypted {
            w.append(options.keepEncryption
                ? "Input was encrypted; the same password has been applied to the output."
                : "Input was encrypted; the output is not. Pass --keep-encryption to re-apply the password.")
        }
        if !doc.allowsCopying || !doc.allowsPrinting {
            w.append("Input had copy/print restrictions (owner password). Restrictions are carried over to the output.")
        }
        var signatures = 0
        for i in 0..<doc.pageCount {
            for a in doc.page(at: i)?.annotations ?? [] where a.widgetFieldType == .signature {
                signatures += 1
            }
        }
        if signatures > 0 {
            w.append("Input contains \(signatures) digital signature field(s). Redaction rasterises pages, so the output is unsigned.")
        }
        if let root = doc.documentRef?.catalog, CGPDFDictionaryGetDictionary(root, "AcroForm", nil) {
            var form: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(root, "AcroForm", &form), let form, CGPDFDictionaryGetObject(form, "XFA", nil) {
                w.append("Input is an XFA form. PDFKit renders only the fallback page content; verify the output visually.")
            }
        }
        return w
    }

    /// Heuristic: a usable text layer has mostly printable, mostly recognisable tokens.
    static func textLayerLooksUsable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else { return false }
        let scalars = trimmed.unicodeScalars
        let letters = scalars.filter { CharacterSet.letters.contains($0) }.count
        let digits = scalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let junk = scalars.filter {
            !CharacterSet.alphanumerics.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.punctuationCharacters.contains($0) && !CharacterSet.symbols.contains($0)
        }.count
        let total = max(1, scalars.count)
        // Broken font encodings produce control chars / private-use glyphs, or no letters at all.
        if Double(junk) / Double(total) > 0.05 { return false }
        if Double(letters + digits) / Double(total) < 0.4 { return false }
        // Words of 2+ letters should exist in volume; mojibake tends to be long runs without spaces.
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        let wordy = words.filter { $0.count >= 2 && $0.count <= 25 }.count
        return Double(wordy) / Double(max(1, words.count)) > 0.6
    }

    // MARK: Redaction

    public func redact(input: URL, output: URL, engine: StridEngine, style: RedactionStyle, options: DocumentOptions) throws -> RedactionReport {
        let doc = try Self.open(input, password: options.password)
        var warnings = Self.inspect(doc, options: options)

        var all: [PIIEntity] = []
        var pageImages: [(CGImage, CGRect)] = []
        var ocrPages = 0
        var tokens: TokenMap? = options.reversible ? TokenMap() : nil

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            let raster = render(page, box: box)

            let text = page.string ?? ""
            let useText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (!options.ocrFallback || Self.textLayerLooksUsable(text))

            if useText {
                let entities = engine.detect(in: text)
                let ns = text as NSString
                var boxes: [Box] = []
                for e in entities {
                    let nsRange = NSRange(e.range, in: text)
                    guard nsRange.location != NSNotFound, nsRange.location + nsRange.length <= ns.length,
                          let sel = page.selection(for: nsRange) else { continue }
                    let label = tokens != nil ? tokens!.token(for: e) : nil
                    for line in sel.selectionsByLine() {
                        let r = line.bounds(for: page)
                        boxes.append(Box(rect: CGRect(
                            x: (r.minX - box.minX) * scale,
                            y: (box.maxY - r.maxY) * scale,
                            width: r.width * scale,
                            height: r.height * scale
                        ), label: label))
                    }
                }
                all += entities
                pageImages.append((Raster.blackout(raster, boxes: boxes, padding: 1.5 * scale), box))
            } else {
                ocrPages += 1
                let (img, entities) = try ImageDocumentHandler.redact(image: raster, engine: engine, tokens: &tokens)
                all += entities
                pageImages.append((img, box))
            }
        }
        if ocrPages > 0 {
            warnings.append("\(ocrPages) of \(doc.pageCount) page(s) had no usable text layer and were processed with OCR.")
        }

        try write(pages: pageImages, to: output, source: doc, options: options)
        var report = RedactionReport(pages: doc.pageCount, entities: all, warnings: warnings)
        report.tokens = tokens
        return report
    }

    func render(_ page: PDFPage, box: CGRect) -> CGImage {
        let w = Int(box.width * scale), h = Int(box.height * scale)
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()!
    }

    private func write(pages: [(CGImage, CGRect)], to url: URL, source: PDFDocument, options: DocumentOptions) throws {
        var aux: [CFString: Any] = [kCGPDFContextCreator: "Strid"]
        if source.isEncrypted, options.keepEncryption, let pw = options.password {
            aux[kCGPDFContextUserPassword] = pw
            aux[kCGPDFContextOwnerPassword] = pw
            aux[kCGPDFContextEncryptionKeyLength] = 128
        }
        if !source.allowsCopying { aux[kCGPDFContextAllowsCopying] = false }
        if !source.allowsPrinting { aux[kCGPDFContextAllowsPrinting] = false }
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let pdf = CGContext(consumer: consumer, mediaBox: nil, aux as CFDictionary)
        else { throw DocumentRedactionError.writeFailed(url) }
        for (image, box) in pages {
            var mediaBox = CGRect(origin: .zero, size: box.size)
            pdf.beginPage(mediaBox: &mediaBox)
            pdf.draw(image, in: mediaBox)
            pdf.endPage()
        }
        pdf.closePDF()
    }
}
