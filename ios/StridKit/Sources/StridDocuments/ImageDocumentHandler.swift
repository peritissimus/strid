//
// ImageDocumentHandler.swift
// StridDocuments
//
// Handler for raster images (PNG, JPEG, HEIC, TIFF, ...). There is no text to edit, so the flow is:
//
//   decode image -> Vision OCR (`OCR.recognise`) -> engine.detect on the OCR text
//     -> map each entity back to pixel rectangles via the OCR line geometry
//     -> paint opaque black boxes (`Raster.blackout`) -> re-encode in the source format
//
// The static `redact(image:engine:tokens:)` is shared with `PDFDocumentHandler`, which uses it for
// scanned pages (and pages whose text layer is unusable) after rasterising them.
//
import CoreGraphics
import Foundation
import ImageIO
import StridKit
import UniformTypeIdentifiers

/// PNG/JPEG/HEIC in, same format out. PII is painted over with black boxes located via Vision OCR.
public struct ImageDocumentHandler: DocumentHandler {
    public init() {}

    /// Decodes the first image in `input`, redacts it, and writes it to `output` in the same
    /// container type (falling back to PNG if the type cannot be determined).
    ///
    /// - Parameters:
    ///   - input: Image file.
    ///   - output: Destination image.
    ///   - engine: Detection engine.
    ///   - style: Ignored; raster output is always black boxes.
    ///   - options: `reversible` enables token labels inside the boxes and a token map in the report.
    /// - Returns: Single-page report with the OCR-detected entities.
    /// - Throws: `unreadable` if decoding fails, `writeFailed` if encoding fails, Vision errors.
    public func redact(input: URL, output: URL, engine: StridEngine, style: RedactionStyle, options: DocumentOptions) throws -> RedactionReport {
        // `kCGImageSourceShouldCache: false` avoids keeping a decoded copy around; the image is used once.
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw DocumentRedactionError.unreadable(input) }

        var map: TokenMap? = options.reversible ? TokenMap() : nil
        let (redacted, entities) = try Self.redact(image: image, engine: engine, policy: options.policy, tokens: &map)

        // Preserve the input container type (JPEG stays JPEG, HEIC stays HEIC).
        let type = (CGImageSourceGetType(source) as String?).flatMap(UTType.init) ?? .png
        guard let dest = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw DocumentRedactionError.writeFailed(output)
        }
        // Drop metadata (EXIF GPS etc.) on the way out; that is PII too.
        // Only a compression-quality property is passed, so no source metadata dictionary is copied.
        CGImageDestinationAddImage(dest, redacted, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw DocumentRedactionError.writeFailed(output) }
        var report = RedactionReport(pages: 1, entities: entities)
        report.tokens = map
        return report
    }

    /// Shared by the PDF handler for scanned pages. When `tokens` is non-nil, boxes are labelled.
    ///
    /// Steps:
    ///   1. OCR the image into an `OCRPage` (joined text plus per-line geometry).
    ///   2. Run the engine on the joined text.
    ///   3. For each entity, ask the page for the pixel rectangles covering its range. An entity
    ///      that spans two OCR lines yields two rectangles.
    ///   4. In reversible mode, allocate (or reuse) the entity's token and paint it in the box so
    ///      a human reading the redacted image can cross-reference the vault.
    ///
    /// - Parameters:
    ///   - image: Source bitmap.
    ///   - engine: Detection engine.
    ///   - tokens: `nil` for irreversible; otherwise the running token map, updated in place so
    ///     that tokens stay consistent across all pages of a PDF.
    /// - Returns: The redacted bitmap and the entities that were boxed.
    static func redact(image: CGImage, engine: StridEngine, policy: RedactionPolicy = .default, tokens: inout TokenMap?) throws -> (CGImage, [PIIEntity]) {
        let page = try OCR.recognise(image)
        var entities = engine.detect(in: page.text, policy: policy)
        let size = CGSize(width: image.width, height: image.height)
        var boxes: [Box] = []
        for e in entities {
            let label = tokens != nil ? tokens!.token(for: e) : nil
            boxes += page.rects(for: e, imageSize: size).map { Box(rect: $0, label: label) }
        }
        // Further passes: layout-aware order (see `Layout`) and, on bilingual pages, a Hindi-first
        // reading. Only findings whose boxes are not already painted are added, so the passes
        // never double-count one span.
        for alt in page.alternates {
            for e in engine.detect(in: alt.text, policy: policy) {
                let fresh = alt.rects(for: e, imageSize: size).filter { r in
                    !boxes.contains { b in
                        let i = b.rect.intersection(r)
                        return !i.isNull && i.width * i.height >= 0.8 * r.width * r.height
                    }
                }
                guard !fresh.isEmpty else { continue }
                let label = tokens != nil ? tokens!.token(for: e) : nil
                boxes += fresh.map { Box(rect: $0, label: label) }
                entities.append(e)
            }
        }
        // QR codes and barcodes: boxed whole, never decoded (see `Barcodes`).
        let codes = Barcodes.detect(in: image)
        boxes += codes.map { Box(rect: $0, label: nil) }
        return (Raster.blackout(image, boxes: boxes), entities + Barcodes.entities(for: codes, in: page.text))
    }
}
