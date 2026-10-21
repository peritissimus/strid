import CoreGraphics
import Foundation
import ImageIO
import StridKit
import UniformTypeIdentifiers

/// PNG/JPEG/HEIC in, same format out. PII is painted over with black boxes located via Vision OCR.
public struct ImageDocumentHandler: DocumentHandler {
    public init() {}

    public func redact(input: URL, output: URL, engine: StridEngine, style: RedactionStyle, options: DocumentOptions) throws -> RedactionReport {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw DocumentRedactionError.unreadable(input) }

        var map: TokenMap? = options.reversible ? TokenMap() : nil
        let (redacted, entities) = try Self.redact(image: image, engine: engine, tokens: &map)

        let type = (CGImageSourceGetType(source) as String?).flatMap(UTType.init) ?? .png
        guard let dest = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw DocumentRedactionError.writeFailed(output)
        }
        // Drop metadata (EXIF GPS etc.) on the way out; that is PII too.
        CGImageDestinationAddImage(dest, redacted, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw DocumentRedactionError.writeFailed(output) }
        var report = RedactionReport(pages: 1, entities: entities)
        report.tokens = map
        return report
    }

    /// Shared by the PDF handler for scanned pages. When `tokens` is non-nil, boxes are labelled.
    static func redact(image: CGImage, engine: StridEngine, tokens: inout TokenMap?) throws -> (CGImage, [PIIEntity]) {
        let page = try OCR.recognise(image)
        let entities = engine.detect(in: page.text)
        let size = CGSize(width: image.width, height: image.height)
        var boxes: [Box] = []
        for e in entities {
            let label = tokens != nil ? tokens!.token(for: e) : nil
            boxes += page.rects(for: e, imageSize: size).map { Box(rect: $0, label: label) }
        }
        return (Raster.blackout(image, boxes: boxes), entities)
    }
}
