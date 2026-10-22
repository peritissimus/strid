//
// PDFDocumentHandler.swift
// StridDocuments
//
// The PDF handler. Rather than editing the PDF content stream (fragile, and trivially reversible
// if done as an annotation), every page is rendered to a bitmap, PII is painted over, and a new
// image-only PDF is assembled. Per page the flow is:
//
//   render page at `scale` -> does the text layer exist and look sane?
//     yes: engine.detect(page.string) -> PDFKit selection per entity -> page-space rects
//          -> scale/flip into raster pixels -> Raster.blackout
//     no:  ImageDocumentHandler.redact(raster)  (Vision OCR path, same as a scanned image)
//
// The output keeps page sizes, copy/print restrictions and, optionally, the user password, but
// loses everything else: fonts, links, forms, signatures, and the text layer itself.
//
import CoreGraphics
import Foundation
import ImageIO
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

    /// Render scale for the OCR pass on pages without a text layer (`STRID_OCR_SCALE` overrides
    /// for measurement). The painted output always uses `scale`.
    /// Measured on an 81-page scanned statement: 144 dpi lost 5% of findings (and was no
    /// faster, since small renders are upscaled again before recognition), so the default is
    /// the output scale.
    public var ocrScale: CGFloat = ProcessInfo.processInfo.environment["STRID_OCR_SCALE"].flatMap { Double($0) }.map { CGFloat($0) } ?? 3

    // MARK: Opening

    /// Opens a PDF, unlocking it when a password is supplied. Throws a specific error when one is needed.
    ///
    /// - Parameters:
    ///   - url: PDF file.
    ///   - password: User (or owner) password for locked files; ignored for unlocked ones.
    /// - Returns: An unlocked `PDFDocument`.
    /// - Throws: `unreadable` if PDFKit cannot parse the file, `passwordRequired` if it is locked
    ///   and no password was given, `wrongPassword` if unlocking failed.
    public static func open(_ url: URL, password: String?) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw DocumentRedactionError.unreadable(url) }
        if doc.isLocked {
            guard let password, !password.isEmpty else { throw DocumentRedactionError.passwordRequired(url) }
            guard doc.unlock(withPassword: password) else { throw DocumentRedactionError.wrongPassword(url) }
        }
        return doc
    }

    /// Inspects a document for things the user must know about before we flatten it.
    ///
    /// Produces human-readable warnings for: encryption (and whether it is being carried over),
    /// owner-password restrictions, digital signature widgets (which rasterising invalidates),
    /// and XFA forms (whose dynamic content PDFKit does not render).
    ///
    /// - Returns: Zero or more warning strings for `RedactionReport.warnings`.
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
        // Count signature form fields across all pages.
        var signatures = 0
        for i in 0..<doc.pageCount {
            for a in doc.page(at: i)?.annotations ?? [] where a.widgetFieldType == .signature {
                signatures += 1
            }
        }
        if signatures > 0 {
            w.append("Input contains \(signatures) digital signature field(s). Redaction rasterises pages, so the output is unsigned.")
        }
        // XFA detection: walk the raw catalog for /AcroForm -> /XFA via CoreGraphics, since PDFKit
        // exposes no API for it.
        if let root = doc.documentRef?.catalog, CGPDFDictionaryGetDictionary(root, "AcroForm", nil) {
            var form: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(root, "AcroForm", &form), let form, CGPDFDictionaryGetObject(form, "XFA", nil) {
                w.append("Input is an XFA form. PDFKit renders only the fallback page content; verify the output visually.")
            }
        }
        return w
    }

    /// Heuristic: a usable text layer has mostly printable, mostly recognisable tokens.
    ///
    /// Scanned PDFs from some bank portals carry a text layer produced by a poor OCR pass or a
    /// broken font encoding (every glyph mapped to a private-use code point). Trusting such a
    /// layer would silently miss everything, so a page is only treated as text when:
    ///   - it has at least 20 non-blank characters,
    ///   - at most 5% of scalars are "junk" (not alphanumeric, whitespace, punctuation or symbol),
    ///   - at least 40% of scalars are letters or digits,
    ///   - at least 60% of whitespace-separated tokens are 2-25 characters long (mojibake tends
    ///     to produce either single glyphs or very long unbroken runs).
    /// Otherwise the page goes to OCR (unless `ocrFallback` is off).
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

    /// Redacts every page and writes a new image-only PDF.
    ///
    /// Text-layer pages: entity ranges from the engine are converted to `NSRange`s over
    /// `page.string`, turned into `PDFSelection`s, and each selection's per-line bounds (in PDF
    /// page points, origin bottom-left, relative to the media box) are mapped to raster pixels:
    ///
    ///     px.x = (r.minX - box.minX) * scale
    ///     px.y = (box.maxY - r.maxY) * scale      // flip to top-left origin
    ///
    /// Padding is `1.5 * scale` pixels so it stays ~1.5pt regardless of render scale.
    ///
    /// OCR pages: delegated to `ImageDocumentHandler.redact`, sharing the token map so a name on
    /// a scanned page 3 gets the same `[PERSON_n]` as on text page 1.
    ///
    /// - Parameters:
    ///   - input: PDF file.
    ///   - output: Destination PDF.
    ///   - engine: Detection engine.
    ///   - style: Ignored; output is always black boxes.
    ///   - options: Password, encryption carry-over, OCR fallback and reversible settings.
    /// - Returns: Report with page count, all entities, inspection and OCR warnings, and tokens.
    /// - Throws: Open / password errors, Vision errors, `writeFailed`.
    public func redact(input: URL, output: URL, engine: StridEngine, style: RedactionStyle, options: DocumentOptions) throws -> RedactionReport {
        let doc = try Self.open(input, password: options.password)
        var warnings = Self.inspect(doc, options: options)

        var all: [PIIEntity] = []
        var ocrPages = 0
        var tokens: TokenMap? = options.reversible ? TokenMap() : nil
        let timing = Timing()

        // Pages are rasterised, painted and written one at a time. Holding every page bitmap
        // until the end costs ~18 MB per A4 page at scale 3, which is over a gigabyte for an
        // 80-page statement and more than an iPhone will allow.
        let writer = try PageWriter(url: output, source: doc, options: options)
        // Vision work (OCR, barcode search) is the cost on scanned pages and runs on the GPU and
        // Neural Engine, so a window of pages is recognised concurrently; detection, token
        // numbering, painting and writing then happen in page order on this thread.
        let window = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount))
        var start = 0
        while start < doc.pageCount {
            let end = min(doc.pageCount, start + window)
            var batch: [(index: Int, page: PDFPage, box: CGRect, raster: CGImage, text: String, useText: Bool)] = []
            for i in start..<end {
                guard let page = doc.page(at: i) else { continue }
                let box = page.bounds(for: .mediaBox)
                let raster = timing.measure("render") { render(page, box: box) }
                let text = page.string ?? ""
                let useText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && (!options.ocrFallback || Self.textLayerLooksUsable(text))
                batch.append((i, page, box, raster, text, useText))
            }
            // Concurrent Vision passes, one slot per page in the window.
            var ocr = [Result<OCRPage, Error>?](repeating: nil, count: batch.count)
            var codes = [[CGRect]](repeating: [], count: batch.count)
            timing.measure("vision") {
                ocr.withUnsafeMutableBufferPointer { ocrBuf in
                    codes.withUnsafeMutableBufferPointer { codeBuf in
                        DispatchQueue.concurrentPerform(iterations: batch.count) { k in
                            let item = batch[k]
                            codeBuf[k] = Barcodes.detect(in: item.raster)
                            if !item.useText {
                                // Recognition runs on a smaller render than the one that is painted:
                                // Vision's cost grows with pixel count, and statement print is read
                                // as well at 144 dpi as at 216. Geometry is normalised, so boxes map
                                // onto the full-size raster unchanged.
                                let small = ocrScale < scale ? self.render(item.page, box: item.box, scale: ocrScale) : item.raster
                                ocrBuf[k] = Result { try OCR.recognise(small) }
                            }
                        }
                    }
                }
            }
            for (k, item) in batch.enumerated() {
                let (page, box, raster, text) = (item.page, item.box, item.raster, item.text)
                if item.useText {
                    let entities = timing.measure("detect") { engine.detect(in: text, policy: options.policy) }
                    let ns = text as NSString
                    var boxes: [Box] = []
                    timing.measure("geometry") {
                        for e in entities {
                            let nsRange = NSRange(e.range, in: text)
                            // Guard against ranges PDFKit cannot resolve (e.g. an entity that
                            // `extendAcrossWraps` grew over a newline PDFKit does not count).
                            guard nsRange.location != NSNotFound, nsRange.location + nsRange.length <= ns.length,
                                  let sel = page.selection(for: nsRange) else { continue }
                            let label = tokens != nil ? tokens!.token(for: e) : nil
                            // One box per visual line so a wrapped entity gets two tight boxes, not one
                            // huge rectangle spanning the gap.
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
                    }
                    // Codes drawn or embedded on a text-layer page (e-Aadhaar, e-PAN) are boxed too.
                    boxes += codes[k].map { Box(rect: $0, label: nil) }
                    all += entities + Barcodes.entities(for: codes[k], in: text)
                    let painted = timing.measure("blackout") { Raster.blackout(raster, boxes: boxes, padding: 1.5 * scale) }
                    try timing.measure("write") { try writer.add(painted, box: box) }
                } else {
                    ocrPages += 1
                    let recognised = try ocr[k]!.get()
                    let (img, entities) = try timing.measure("ocr") {
                        try ImageDocumentHandler.redact(image: raster, page: recognised, codes: codes[k], engine: engine, policy: options.policy, tokens: &tokens)
                    }
                    all += entities
                    try timing.measure("write") { try writer.add(img, box: box) }
                }
            }
            start = end
        }
        if ocrPages > 0 {
            warnings.append("\(ocrPages) of \(doc.pageCount) page(s) had no usable text layer and were processed with OCR.")
        }

        timing.measure("close") { writer.close() }
        timing.report(pages: doc.pageCount)
        var report = RedactionReport(pages: doc.pageCount, entities: all, warnings: warnings)
        report.tokens = tokens
        return report
    }

    /// Rasterises one page into an opaque white-backed RGBA bitmap at `scale` x 72 dpi.
    ///
    /// The context is scaled and translated so that the page's media box origin maps to the
    /// bitmap origin; PDFKit then draws the page (including annotations) with `.mediaBox`.
    /// Force-unwraps are acceptable here: a failure means an out-of-memory or zero-size page,
    /// neither of which can be meaningfully recovered from mid-document.
    func render(_ page: PDFPage, box: CGRect) -> CGImage { render(page, box: box, scale: scale) }

    func render(_ page: PDFPage, box: CGRect, scale: CGFloat) -> CGImage {
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

    /// Streams redacted page bitmaps into a new PDF via CoreGraphics, one page at a time.
    ///
    /// Each page keeps its original point size (the bitmap is drawn to fill the media box, so the
    /// output has the same dimensions as the input regardless of `scale`). Document-level
    /// settings carried over from the source: copy and print permissions always; user/owner
    /// password (128-bit RC4/AES as CoreGraphics chooses) only when `keepEncryption` is set and
    /// a password is known. The creator is stamped as "Strid".
    ///
    /// Bitmaps are handed to the PDF context as JPEG data so the page is stored with DCT
    /// compression (the context passes JPEG-encoded images through unchanged) instead of being
    /// deflated as raw RGBA, which is both slower and several times larger.
    final class PageWriter {
        private let pdf: CGContext
        private let quality: CGFloat

        /// - Throws: `DocumentRedactionError.writeFailed` if the consumer or context cannot be created.
        init(url: URL, source: PDFDocument, options: DocumentOptions, quality: CGFloat = 0.82) throws {
            var aux: [CFString: Any] = [kCGPDFContextCreator: "Strid"]
            if source.isEncrypted, options.keepEncryption, let pw = options.password {
                aux[kCGPDFContextUserPassword] = pw
                aux[kCGPDFContextOwnerPassword] = pw
                aux[kCGPDFContextEncryptionKeyLength] = 128
            }
            if !source.allowsCopying { aux[kCGPDFContextAllowsCopying] = false }
            if !source.allowsPrinting { aux[kCGPDFContextAllowsPrinting] = false }
            guard let consumer = CGDataConsumer(url: url as CFURL),
                  let ctx = CGContext(consumer: consumer, mediaBox: nil, aux as CFDictionary)
            else { throw DocumentRedactionError.writeFailed(url) }
            pdf = ctx
            self.quality = quality
        }

        func add(_ image: CGImage, box: CGRect) throws {
            var mediaBox = CGRect(origin: .zero, size: box.size)
            pdf.beginPage(mediaBox: &mediaBox)
            pdf.draw(Self.jpegBacked(image, quality: quality) ?? image, in: mediaBox)
            pdf.endPage()
        }

        func close() { pdf.closePDF() }

        /// The same pixels as a CGImage whose data provider is a JPEG stream.
        static func jpegBacked(_ image: CGImage, quality: CGFloat) -> CGImage? {
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(dest), let provider = CGDataProvider(data: data) else { return nil }
            return CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
    }

    /// Per-phase wall-clock totals, printed to stderr when `STRID_TIMING` is set.
    final class Timing {
        private var totals: [String: Double] = [:]
        private let enabled = ProcessInfo.processInfo.environment["STRID_TIMING"] != nil

        func measure<T>(_ phase: String, _ body: () throws -> T) rethrows -> T {
            guard enabled else { return try body() }
            let t = CFAbsoluteTimeGetCurrent()
            defer { totals[phase, default: 0] += CFAbsoluteTimeGetCurrent() - t }
            return try body()
        }

        func report(pages: Int) {
            guard enabled else { return }
            let all = totals.values.reduce(0, +)
            let lines = totals.sorted { $0.value > $1.value }.map { String(format: "  %-9@ %6.2fs", $0.key as NSString, $0.value) }
            FileHandle.standardError.write(("timing for \(pages) pages, \(String(format: "%.2f", all))s total:\n" + lines.joined(separator: "\n") + "\n").data(using: .utf8)!)
        }
    }
}
