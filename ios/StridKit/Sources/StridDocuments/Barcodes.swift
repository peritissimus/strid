//
// Barcodes.swift
// StridDocuments
//
// QR codes and barcodes on identity documents carry the printed data in machine-readable form:
// the Aadhaar QR holds the holder's name, date of birth, gender and full address, a PAN card's
// QR the PAN and name, a cheque's barcode the MICR line. Blacking out the printed fields while
// leaving the code intact leaks everything. So every detected code is boxed, whatever it encodes.
// The payload is never decoded or read here; only the bounding box is used.
//
import CoreGraphics
import Foundation
import StridKit
import Vision

enum Barcodes {
    /// Pixel rectangles (origin top-left) of every barcode or 2D code Vision finds in `image`.
    ///
    /// All symbologies Vision supports are requested. Detection failures (unsupported image,
    /// Vision error) return an empty list rather than throwing: a missing code is reported by the
    /// absence of a BARCODE entity, never by failing the whole document.
    static func detect(in image: CGImage) -> [CGRect] {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        let size = CGSize(width: image.width, height: image.height)
        return (request.results ?? []).map { OCRPage.denormalise($0.boundingBox, in: size) }
    }

    /// A `.barcode` entity anchored at the end of `text` for each rectangle, so reports and
    /// summaries count codes alongside text findings. The empty range keeps text redactors from
    /// touching anything.
    static func entities(for rects: [CGRect], in text: String) -> [PIIEntity] {
        rects.map { _ in PIIEntity(type: .barcode, text: "QR / barcode", range: text.endIndex..<text.endIndex, score: 1.0) }
    }
}
