//
// OCR.swift
// StridDocuments
//
// Everything needed to redact pixels rather than characters:
//
//   - `OCR.recognise`       runs Vision text recognition and flattens the result into one string
//                           (`OCRPage.text`) that the engine can scan, while remembering, per line,
//                           where in that string it sits and where on the image it was found.
//   - `OCRPage.rects(for:)` maps an entity's range in the joined string back to pixel rectangles.
//   - `Raster.blackout`     paints those rectangles black, optionally with a token label.
//
// Coordinate systems to keep straight:
//   Vision      normalised 0...1, origin bottom-left
//   `Box.rect`  pixels, origin top-left (what `OCRPage.denormalise` produces)
//   CGContext   pixels, origin bottom-left (hence the flip inside `Raster.blackout`)
//
import CoreGraphics
import CoreText
import Foundation
import StridKit
import Vision

/// A recognised line of text with its position on the page (Vision normalised coords, origin bottom-left).
///
/// Backend-agnostic: both the classic `VNRecognizeTextRequest` path and the newer document
/// recogniser produce these, so `OCRPage.rects(for:)` never has to know which one ran.
struct OCRLine {
    /// Raw recogniser output for the line, before confusable normalisation.
    let raw: String
    /// Normalised text (confusable glyphs mapped to Latin). Same character count as `raw`.
    let text: String
    /// Whole-line rectangle (normalised, origin bottom-left); the fallback when a sub-range box is unavailable.
    let lineBox: CGRect
    /// Normalised rectangle for a sub-range of `raw`, or `nil` when the backend cannot provide one.
    let boxForRange: (Range<String.Index>) -> CGRect?
    /// Range of this line inside the page's joined text.
    let range: Range<String.Index>
}

/// One OCR'd image: the joined text the engine scans plus the line geometry to map results back.
struct OCRPage {
    /// All lines, top to bottom, each terminated by `"\n"`.
    let text: String
    /// Line records in the same order as they appear in `text`.
    let lines: [OCRLine]
    /// The same lines in layout-aware reading order (see `Layout`), or `nil` when disabled.
    /// Detection runs on both orders and the boxes are unioned: the plain top-to-bottom order
    /// keeps table rows together (a reference next to its narration), the block order keeps
    /// multi-column headers together (an address next to the account details).
    var reflowed: OCRPage? {
        get { reflowedBox?.page }
        set { reflowedBox = newValue.map(Boxed.init) }
    }
    /// Heap box so the value type can hold another page of its own kind.
    private var reflowedBox: Boxed? = nil
    private final class Boxed { let page: OCRPage; init(page: OCRPage) { self.page = page } }

    /// Pixel-space rectangles (origin top-left) covering `entity` on an image of the given size.
    ///
    /// For each OCR line the entity overlaps, the overlapping character span is translated into
    /// the candidate's own string indices and Vision is asked for that substring's bounding box.
    /// If Vision cannot provide one, the whole line's box is used, which over-redacts but never
    /// under-redacts.
    ///
    /// - Parameters:
    ///   - entity: Entity whose `range` indexes into `text`.
    ///   - imageSize: Pixel dimensions used to denormalise Vision coordinates.
    /// - Returns: One rectangle per overlapped line (possibly empty if ranges do not line up).
    func rects(for entity: PIIEntity, imageSize: CGSize) -> [CGRect] {
        var rects: [CGRect] = []
        for line in lines where line.range.overlaps(entity.range) {
            let lo = max(line.range.lowerBound, entity.range.lowerBound)
            let hi = min(line.range.upperBound, entity.range.upperBound)
            // Map page-text indices to this line's own string indices.
            let offset = text.distance(from: line.range.lowerBound, to: lo)
            let length = text.distance(from: lo, to: hi)
            // Index into the recogniser's *own* string (pre-normalisation); counts are identical by construction.
            // (`normaliseConfusables` is a one-to-one character map, so offsets transfer directly.)
            let raw = line.raw
            guard length > 0,
                  let start = raw.index(raw.startIndex, offsetBy: offset, limitedBy: raw.endIndex),
                  let end = raw.index(start, offsetBy: length, limitedBy: raw.endIndex)
            else { continue }

            let box = line.boxForRange(start..<end) ?? line.lineBox
            rects.append(Self.denormalise(box, in: imageSize))
        }
        return rects
    }

    /// Vision gives normalised rects with a bottom-left origin; convert to top-left pixel coords.
    ///
    /// `y` flips via `1 - maxY`: the top edge in Vision space becomes the top edge measured from
    /// the top of the image.
    static func denormalise(_ box: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: box.minX * size.width,
            y: (1 - box.maxY) * size.height,
            width: box.width * size.width,
            height: box.height * size.height
        )
    }
}

/// Vision text-recognition wrapper.
enum OCR {
    /// Runs Vision text recognition and joins lines top-to-bottom into one string.
    ///
    /// Settings:
    ///   - input is conditionally upscaled first (see `Preprocess`); on a degraded-photo corpus
    ///     this took recall from 0.87 to 0.94 with no change on clean scans. Vision's newer
    ///     document recogniser (`RecognizeDocumentsRequest`) was measured and scored lower on
    ///     both corpora, so the classic request stays.
    ///   - `.accurate` recognition level: slower but necessary for small statement print.
    ///   - language correction *off*: Vision's dictionary would "fix" identifiers like `HDFC0001234`
    ///     or `ABCDE1234F` into words, destroying exactly the tokens we need to detect.
    ///   - languages default to Indian English, US English and Hindi, in that priority order.
    ///
    /// Observations are sorted by `boundingBox.minY` descending (Vision's origin is bottom-left, so
    /// larger `minY` means higher on the page) and concatenated with `"\n"`. Each line's range in
    /// the joined string excludes its newline. Only the single top candidate per line is used.
    ///
    /// - Parameters:
    ///   - image: Bitmap to recognise.
    ///   - languages: Vision language identifiers.
    /// - Returns: The page text and line geometry.
    /// - Throws: Vision errors from `perform`.
    static func recognise(_ image: CGImage, languages: [String] = ["en-IN", "en-US", "hi-IN"]) throws -> OCRPage {
        // Phone photos and low-dpi scans are often too small for the recogniser to read small
        // print reliably. Upscaling costs time, not geometry: Vision reports normalised
        // coordinates, so rectangles map straight back onto the original image.
        let prepared = Preprocess.upscaled(image)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false  // keep IDs and numbers verbatim
        request.recognitionLanguages = languages
        let handler = VNImageRequestHandler(cgImage: prepared, options: [:])
        try handler.perform([request])

        let observations = (request.results ?? [])
            .sorted { $0.boundingBox.minY > $1.boundingBox.minY } // top of page first

        var raws: [Layout.Raw] = []
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            raws.append((candidate.string, obs.boundingBox, { range in
                (try? candidate.boundingBox(for: range))?.boundingBox
            }))
        }
        // STRID_OCR_LAYOUT=blocks makes the layout order the primary (and only) text, which is how
        // `strid text` can show what the second pass sees.
        if Layout.blocksOnly { return assemble(Layout.reflow(raws)) }
        var page = assemble(raws)
        if Layout.enabled, raws.count > 1 {
            page.reflowed = assemble(Layout.reflow(raws))
        }
        return page
    }

    /// Joins recognised lines (already top-to-bottom) into an `OCRPage`, normalising confusables.
    static func assemble(_ raws: [Layout.Raw]) -> OCRPage {
        var joined = ""
        var lines: [OCRLine] = []
        for r in raws {
            let normalised = normaliseConfusables(r.raw)
            let start = joined.endIndex
            joined += normalised
            let end = joined.endIndex
            joined += "\n"
            lines.append(OCRLine(raw: r.raw, text: normalised, lineBox: r.lineBox, boxForRange: r.boxForRange, range: start..<end))
        }
        return OCRPage(text: joined, lines: lines)
    }

    /// With Hindi in the recognition language list, Vision sometimes emits Cyrillic or Greek look-alikes
    /// inside Latin words (e.g. "MEHТA" with U+0422). Map them back one-to-one so regexes and the
    /// narration parser see ASCII. Character count is preserved so offsets into the raw candidate stay valid.
    ///
    /// Rows: Cyrillic capitals, Cyrillic lower case, Greek capitals and a couple of Greek lower case,
    /// then Arabic-Indic and Devanagari digits mapped to ASCII digits (so an Aadhaar or amount
    /// printed in Devanagari numerals still validates and matches).
    static let confusables: [Character: Character] = [
        "А": "A", "В": "B", "С": "C", "Е": "E", "Н": "H", "І": "I", "Ј": "J", "К": "K", "М": "M", "О": "O",
        "Р": "P", "Ѕ": "S", "Т": "T", "Х": "X", "У": "Y", "Ζ": "Z",
        "а": "a", "с": "c", "е": "e", "о": "o", "р": "p", "х": "x", "у": "y", "і": "i", "ј": "j", "ѕ": "s",
        "Α": "A", "Β": "B", "Ε": "E", "Η": "H", "Ι": "I", "Κ": "K", "Μ": "M", "Ν": "N", "Ο": "O", "Ρ": "P",
        "Τ": "T", "Υ": "Y", "Χ": "X", "ο": "o", "ν": "v",
        "٠": "0", "١": "1", "२": "2", "३": "3", "४": "4", "५": "5", "६": "6", "७": "7", "८": "8", "९": "9", "०": "0", "१": "1",
    ]

    /// Applies `confusables` character by character. Fast path returns the input unchanged when it
    /// contains no confusable at all (the common case).
    static func normaliseConfusables(_ s: String) -> String {
        guard s.contains(where: { confusables[$0] != nil }) else { return s }
        return String(s.map { confusables[$0] ?? $0 })
    }
}

/// Image conditioning before recognition. Nothing here changes the image's aspect ratio, so
/// normalised Vision coordinates from the prepared image apply unchanged to the original.
enum Preprocess {
    /// Shorter side the recogniser should see, in pixels. Below this, small statement print
    /// (6–8pt at phone-camera distance) is a few pixels tall and digits start to merge.
    static let targetShortSide = 2400
    /// Images whose shorter side is at least this are left alone: resampling a sharp image adds
    /// nothing and measurably costs a few reads (e.g. a capital I turning into a lowercase l).
    static let minShortSide = 1700
    /// Never blow an image up more than this; past 3x there is no new information to find.
    static let maxScale = 3

    /// Returns `image` enlarged by an integer factor (2x or 3x) with high-quality interpolation
    /// when its shorter side is under `minShortSide`, otherwise the image itself.
    static func upscaled(_ image: CGImage) -> CGImage {
        let short = min(image.width, image.height)
        guard short > 0, short < minShortSide else { return image }
        let scale = min(maxScale, Int((Double(targetShortSide) / Double(short)).rounded(.up)))
        guard scale > 1 else { return image }
        let w = image.width * scale, h = image.height * scale
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }
}

/// A box to paint, optionally labelled with its token.
struct Box {
    /// Pixel rectangle, origin top-left.
    var rect: CGRect
    /// Reversible-mode token (e.g. `[PERSON_1]`) to draw inside the box; `nil` for a plain box.
    var label: String?
}

/// Bitmap painting helpers for raster redaction.
enum Raster {
    /// Convenience for unlabelled boxes.
    static func blackout(_ image: CGImage, rects: [CGRect], padding: CGFloat = 2) -> CGImage {
        blackout(image, boxes: rects.map { Box(rect: $0, label: nil) }, padding: padding)
    }

    /// Paints opaque black boxes over the given pixel rectangles (top-left origin), writes the token label
    /// in white inside each box when it fits, and returns a new image.
    ///
    /// The source is drawn into a fresh RGBA context of the same pixel size, boxes are filled on
    /// top, and the context is snapshotted. Boxes are grown by `padding` on every side so that
    /// anti-aliased glyph edges and slightly loose OCR geometry are fully covered. The original
    /// pixels under a box are gone in the returned image; nothing is layered or hidden.
    ///
    /// - Parameters:
    ///   - image: Source bitmap.
    ///   - boxes: Rectangles (and optional labels) to paint.
    ///   - padding: Extra pixels around each rectangle.
    /// - Returns: The redacted bitmap, or the input unchanged if there is nothing to paint or a
    ///   context could not be created.
    static func blackout(_ image: CGImage, boxes: [Box], padding: CGFloat = 2) -> CGImage {
        let rects = boxes.map(\.rect)
        guard !rects.isEmpty else { return image }
        let w = image.width, h = image.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        for b in boxes {
            let r = b.rect
            // CGContext has a bottom-left origin; flip y.
            let flipped = CGRect(x: r.minX - padding, y: CGFloat(h) - r.maxY - padding,
                                 width: r.width + 2 * padding, height: r.height + 2 * padding)
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(flipped)
            if let label = b.label { drawLabel(label, in: flipped, ctx: ctx) }
        }
        return ctx.makeImage() ?? image
    }

    /// Centred white monospace label, shrunk to fit; skipped if it would be unreadable.
    ///
    /// Starts at 62% of the box height and steps the font size down by one point until the
    /// line's typographic width fits inside the box with a 2px margin each side. Anything under
    /// 5pt is not drawn at all; the box stays black and the vault still holds the mapping.
    /// `textPosition` is in the (bottom-left origin) context space, so the baseline is placed a
    /// little below the box's vertical centre to optically centre cap-height glyphs.
    private static func drawLabel(_ text: String, in box: CGRect, ctx: CGContext) {
        var size = box.height * 0.62
        guard size >= 5 else { return }
        var line: CTLine
        repeat {
            let font = CTFontCreateWithName("Menlo" as CFString, size, nil)
            let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1)]
            line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary))
            if CTLineGetTypographicBounds(line, nil, nil, nil) <= Double(box.width - 4) { break }
            size -= 1
        } while size >= 5
        guard size >= 5 else { return }
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        ctx.saveGState()
        ctx.textPosition = CGPoint(x: box.midX - width / 2, y: box.midY - size * 0.35)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}

/// Reading-order reconstruction for OCR output, used as a second detection pass.
///
/// Vision returns one observation per visual line fragment with no notion of columns. Sorting
/// those by vertical position alone interleaves side-by-side blocks, so a statement header reads
///
///     MR. RAHUL SHARMA          Account Branch : S S PLAZA
///     A3                        Address        : ...
///     4TH BLOCK, KORAMANGALA    Phone no.      : ...
///
/// as "MR. RAHUL SHARMA / Account Branch : S S PLAZA / A3 / Address : ... / 4TH BLOCK ..." and every
/// line-based recognizer (address blocks, wrapped identifiers, labelled values) sees a field
/// label between each pair of address lines. Two passes repair this:
///
///   1. `mergeRows`: fragments on the same baseline separated by less than ~0.7 line heights are
///      joined with a space ("Cust ID" + ": 123456" -> "Cust ID : 123456"), so a label stays with
///      its value when Vision split them. Table cells sit much further apart and stay separate.
///   2. `orderBlocks`: lines are grouped into blocks when they are vertically adjacent (gap under
///      0.9 line heights) and horizontally aligned (shared left edge or overlapping extent).
///      Blocks are then emitted top-to-bottom, left-to-right, each block's lines contiguous.
///
/// Geometry stays attached to every fragment, so boxes for a merged line still come from Vision.
///
/// Block order is *not* used alone: in tightly set tables it reads column by column, which
/// separates a reference number from the narration that gives it context and measurably lowers
/// recall. `ImageDocumentHandler` therefore detects on both orders and paints the union.
enum Layout {
    typealias Raw = (raw: String, lineBox: CGRect, boxForRange: (Range<String.Index>) -> CGRect?)

    /// Set `STRID_OCR_LAYOUT=lines` to fall back to plain top-to-bottom order (for A/B evaluation).
    static let enabled = ProcessInfo.processInfo.environment["STRID_OCR_LAYOUT"] != "lines"
    /// Set `STRID_OCR_LAYOUT=blocks` to use the layout order alone (debugging the second pass).
    static let blocksOnly = ProcessInfo.processInfo.environment["STRID_OCR_LAYOUT"] == "blocks"

    static func reflow(_ raws: [Raw]) -> [Raw] {
        orderBlocks(mergeRows(raws))
    }

    /// Largest horizontal gap, in line heights, that still joins two fragments on one baseline.
    static let rowGap: CGFloat = 0.7
    /// Largest vertical gap, in line heights, between consecutive lines of one block.
    static let blockGap: CGFloat = 0.9

    /// Joins fragments that share a baseline and nearly touch. Greedy, left to right.
    static func mergeRows(_ raws: [Raw]) -> [Raw] {
        let items = raws.sorted { a, b in
            if abs(a.lineBox.midY - b.lineBox.midY) > 1e-6 { return a.lineBox.midY > b.lineBox.midY }
            return a.lineBox.minX < b.lineBox.minX
        }
        var used = [Bool](repeating: false, count: items.count)
        var out: [Raw] = []
        for i in items.indices where !used[i] {
            var cur = items[i]
            used[i] = true
            while true {
                var best = -1
                var bestGap = CGFloat.infinity
                for j in items.indices where !used[j] {
                    let b = items[j].lineBox
                    let h = max(cur.lineBox.height, b.height)
                    guard h > 0, abs(b.midY - cur.lineBox.midY) <= 0.4 * h else { continue }
                    let gap = b.minX - cur.lineBox.maxX
                    guard gap >= -0.2 * h, gap <= rowGap * h, gap < bestGap else { continue }
                    bestGap = gap
                    best = j
                }
                guard best >= 0 else { break }
                cur = join(cur, items[best])
                used[best] = true
            }
            out.append(cur)
        }
        return out
    }

    /// Concatenates two fragments with a single space, keeping a `boxForRange` that answers from
    /// whichever original fragment(s) a range falls in (union when it spans both).
    static func join(_ a: Raw, _ b: Raw) -> Raw {
        let s = a.raw + " " + b.raw
        let aCount = a.raw.count
        let aRaw = a.raw, bRaw = b.raw
        let aBox = a.lineBox, bBox = b.lineBox
        let aFor = a.boxForRange, bFor = b.boxForRange
        return (s, aBox.union(bBox), { range in
            let lo = s.distance(from: s.startIndex, to: range.lowerBound)
            let hi = s.distance(from: s.startIndex, to: range.upperBound)
            var rects: [CGRect] = []
            if lo < aCount {
                let end = min(hi, aCount)
                if end > lo {
                    let r = aRaw.index(aRaw.startIndex, offsetBy: lo)..<aRaw.index(aRaw.startIndex, offsetBy: end)
                    rects.append(aFor(r) ?? aBox)
                }
            }
            if hi > aCount + 1 {
                let start = max(lo, aCount + 1) - (aCount + 1)
                let end = hi - (aCount + 1)
                if end > start {
                    let r = bRaw.index(bRaw.startIndex, offsetBy: start)..<bRaw.index(bRaw.startIndex, offsetBy: end)
                    rects.append(bFor(r) ?? bBox)
                }
            }
            guard var u = rects.first else { return nil }
            for r in rects.dropFirst() { u = u.union(r) }
            return u
        })
    }

    /// Groups lines into vertically contiguous, horizontally aligned blocks and emits them in
    /// reading order (block top, then block left edge).
    static func orderBlocks(_ rows: [Raw]) -> [Raw] {
        let sorted = rows.sorted { $0.lineBox.maxY > $1.lineBox.maxY }  // top of page first
        var blocks: [[Int]] = []
        for (i, r) in sorted.enumerated() {
            let b = r.lineBox
            var best = -1
            var bestGap = CGFloat.infinity
            for (bi, blk) in blocks.enumerated() {
                let last = sorted[blk[blk.count - 1]].lineBox
                let h = max(b.height, last.height)
                guard h > 0 else { continue }
                // Vision's origin is bottom-left: the previous line's bottom is `minY`, this line's top is `maxY`.
                let gap = last.minY - b.maxY
                guard gap >= -0.5 * h, gap <= blockGap * h else { continue }
                let overlap = min(b.maxX, last.maxX) - max(b.minX, last.minX)
                let leftAligned = abs(b.minX - last.minX) <= 0.8 * h
                guard leftAligned || overlap >= 0.5 * min(b.width, last.width) else { continue }
                if gap < bestGap { bestGap = gap; best = bi }
            }
            if best >= 0 { blocks[best].append(i) } else { blocks.append([i]) }
        }
        let ordered = blocks.sorted { x, y in
            let a = sorted[x[0]].lineBox, b = sorted[y[0]].lineBox
            if abs(a.maxY - b.maxY) > 0.5 * max(a.height, b.height) { return a.maxY > b.maxY }
            return a.minX < b.minX
        }
        return ordered.flatMap { $0.map { sorted[$0] } }
    }
}
