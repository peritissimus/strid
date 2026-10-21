import CoreGraphics
import CoreText
import Foundation
import StridKit
import Vision

/// A recognised line of text with its position on the page (Vision normalised coords, origin bottom-left).
struct OCRLine {
    let observation: VNRecognizedTextObservation
    let candidate: VNRecognizedText
    /// Normalised text (confusable glyphs mapped to Latin). Same character count as `candidate.string`.
    let text: String
    /// Range of this line inside the page's joined text.
    let range: Range<String.Index>
}

struct OCRPage {
    let text: String
    let lines: [OCRLine]

    /// Pixel-space rectangles (origin top-left) covering `entity` on an image of the given size.
    func rects(for entity: PIIEntity, imageSize: CGSize) -> [CGRect] {
        var rects: [CGRect] = []
        for line in lines where line.range.overlaps(entity.range) {
            let lo = max(line.range.lowerBound, entity.range.lowerBound)
            let hi = min(line.range.upperBound, entity.range.upperBound)
            // Map page-text indices to this line's own string indices.
            let offset = text.distance(from: line.range.lowerBound, to: lo)
            let length = text.distance(from: lo, to: hi)
            // Index into the candidate's *own* string (pre-normalisation); counts are identical by construction.
            let raw = line.candidate.string
            guard length > 0,
                  let start = raw.index(raw.startIndex, offsetBy: offset, limitedBy: raw.endIndex),
                  let end = raw.index(start, offsetBy: length, limitedBy: raw.endIndex)
            else { continue }

            let box: CGRect
            if let sub = try? line.candidate.boundingBox(for: start..<end) {
                box = sub.boundingBox
            } else {
                box = line.observation.boundingBox
            }
            rects.append(Self.denormalise(box, in: imageSize))
        }
        return rects
    }

    /// Vision gives normalised rects with a bottom-left origin; convert to top-left pixel coords.
    static func denormalise(_ box: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: box.minX * size.width,
            y: (1 - box.maxY) * size.height,
            width: box.width * size.width,
            height: box.height * size.height
        )
    }
}

enum OCR {
    /// Runs Vision text recognition and joins lines top-to-bottom into one string.
    static func recognise(_ image: CGImage, languages: [String] = ["en-IN", "en-US", "hi-IN"]) throws -> OCRPage {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false  // keep IDs and numbers verbatim
        request.recognitionLanguages = languages
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let observations = (request.results ?? [])
            .sorted { $0.boundingBox.minY > $1.boundingBox.minY } // top of page first

        var joined = ""
        var lines: [OCRLine] = []
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let normalised = normaliseConfusables(candidate.string)
            let start = joined.endIndex
            joined += normalised
            let end = joined.endIndex
            joined += "\n"
            lines.append(OCRLine(observation: obs, candidate: candidate, text: normalised, range: start..<end))
        }
        return OCRPage(text: joined, lines: lines)
    }

    /// With Hindi in the recognition language list, Vision sometimes emits Cyrillic or Greek look-alikes
    /// inside Latin words (e.g. "MEHТA" with U+0422). Map them back one-to-one so regexes and the
    /// narration parser see ASCII. Character count is preserved so offsets into the raw candidate stay valid.
    static let confusables: [Character: Character] = [
        "А": "A", "В": "B", "С": "C", "Е": "E", "Н": "H", "І": "I", "Ј": "J", "К": "K", "М": "M", "О": "O",
        "Р": "P", "Ѕ": "S", "Т": "T", "Х": "X", "У": "Y", "Ζ": "Z",
        "а": "a", "с": "c", "е": "e", "о": "o", "р": "p", "х": "x", "у": "y", "і": "i", "ј": "j", "ѕ": "s",
        "Α": "A", "Β": "B", "Ε": "E", "Η": "H", "Ι": "I", "Κ": "K", "Μ": "M", "Ν": "N", "Ο": "O", "Ρ": "P",
        "Τ": "T", "Υ": "Y", "Χ": "X", "ο": "o", "ν": "v",
        "٠": "0", "١": "1", "२": "2", "३": "3", "४": "4", "५": "5", "६": "6", "७": "7", "८": "8", "९": "9", "०": "0", "१": "1",
    ]
    static func normaliseConfusables(_ s: String) -> String {
        guard s.contains(where: { confusables[$0] != nil }) else { return s }
        return String(s.map { confusables[$0] ?? $0 })
    }
}

/// A box to paint, optionally labelled with its token.
struct Box {
    var rect: CGRect
    var label: String?
}

enum Raster {
    static func blackout(_ image: CGImage, rects: [CGRect], padding: CGFloat = 2) -> CGImage {
        blackout(image, boxes: rects.map { Box(rect: $0, label: nil) }, padding: padding)
    }

    /// Paints opaque black boxes over the given pixel rectangles (top-left origin), writes the token label
    /// in white inside each box when it fits, and returns a new image.
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
