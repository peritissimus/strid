//
// AttributedDocumentHandler.swift
// StridDocuments
//
// Handler for rich-text containers that Foundation can round-trip as `NSAttributedString`:
// RTF everywhere, and Office Open XML (`.docx`) where the platform supports it (macOS only;
// iOS Foundation cannot read or write DOCX). Redaction happens on the attributed string so run
// formatting (bold, fonts, paragraph styles) around the redacted span is preserved; the span
// itself inherits the attributes of the text it replaces.
//
import Foundation
import StridKit

/// DOCX and RTF via Foundation's attributed-string document readers and writers.
/// Keeps paragraph and run formatting; replaces PII spans with the redaction string.
public struct AttributedDocumentHandler: DocumentHandler {
    public init() {}

    /// Loads the document, redacts its plain-text projection in place, and writes it back in the
    /// same document type.
    ///
    /// The engine sees `attributed.string`, so entity ranges are ranges into that string; each is
    /// converted to an `NSRange` and replaced via `replaceCharacters(in:with:)`, which keeps the
    /// attributes of the first replaced character for the new text.
    ///
    /// - Parameters:
    ///   - input: `.docx` or `.rtf` file.
    ///   - output: Destination, written atomically in the same type as the input.
    ///   - engine: Detection engine.
    ///   - style: Replacement style when not reversible.
    ///   - options: `reversible` switches to token substitution.
    /// - Returns: Single-page report; `tokens` set in reversible mode.
    /// - Throws: `unsupportedFormat` for DOCX on iOS, `unreadable` if Foundation cannot parse the
    ///   file, or serialisation / write errors.
    public func redact(input: URL, output: URL, engine: StridEngine, style: RedactionStyle, options: DocumentOptions) throws -> RedactionReport {
        let docType = try Self.documentType(for: input)
        let attributed: NSMutableAttributedString
        do {
            attributed = try NSMutableAttributedString(
                url: input,
                options: [.documentType: docType],
                documentAttributes: nil
            )
        } catch {
            throw DocumentRedactionError.unreadable(input)
        }

        let text = attributed.string
        let entities = engine.detect(in: text)
        var map = TokenMap()
        // Replace from the back so earlier ranges stay valid.
        for e in entities.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            let nsRange = NSRange(e.range, in: text)
            // For irreversible mode, reuse Redactor on a one-entity string so the replacement text
            // for this span is computed exactly as it would be for plain text (placeholder,
            // asterisks of equal length, or fill character).
            let replacement = options.reversible
                ? map.token(for: e)
                : Redactor.redact(e.text, entities: [
                    PIIEntity(type: e.type, text: e.text, range: e.text.startIndex..<e.text.endIndex, score: e.score)
                ], style: style)
            attributed.replaceCharacters(in: nsRange, with: replacement)
        }

        let data = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: docType]
        )
        try data.write(to: output, options: .atomic)
        var report = RedactionReport(pages: 1, entities: entities)
        if options.reversible { report.tokens = map }
        return report
    }

    /// Reads a DOCX/RTF, transforms its plain text (preserving attributes of the first character of each
    /// replaced token run), and writes it back. Used by restore.
    /// RTF everywhere; DOCX only where Foundation can read it (macOS). iOS gets a clear error.
    ///
    /// - Parameter url: File whose extension decides the document type.
    /// - Returns: `.rtf` for `.rtf` files; `.officeOpenXML` for everything else on macOS.
    /// - Throws: `DocumentRedactionError.unsupportedFormat` for non-RTF files on iOS.
    static func documentType(for url: URL) throws -> NSAttributedString.DocumentType {
        if url.pathExtension.lowercased() == "rtf" { return .rtf }
        #if os(macOS)
        return .officeOpenXML
        #else
        throw DocumentRedactionError.unsupportedFormat(url.pathExtension)
        #endif
    }

    /// Applies `transform` to every reversible token in a redacted DOCX/RTF and writes the result.
    ///
    /// This is the restore path for attributed documents: `DocumentRedactor.restore` passes
    /// `vault.tokens.restore` as the transform, so each `[TYPE_n]` token is swapped for its
    /// original value while surrounding formatting is kept.
    ///
    /// - Parameters:
    ///   - input: Redacted `.docx` / `.rtf`.
    ///   - output: Destination for the restored document.
    ///   - transform: Maps a token string (e.g. `"[PERSON_1]"`) to its replacement.
    /// - Throws: `unsupportedFormat`, `unreadable`, or write errors.
    static func rewrite(_ input: URL, to output: URL, transform: (String) -> String) throws {
        let docType = try documentType(for: input)
        guard let attributed = try? NSMutableAttributedString(url: input, options: [.documentType: docType], documentAttributes: nil) else {
            throw DocumentRedactionError.unreadable(input)
        }
        // Tokens are bracketed and never span attribute runs in practice, so replace per token occurrence.
        // Pattern: "[" + upper-case letters/underscores + "_" + digits + "]", e.g. "[IN_PAN_3]".
        let regex = try NSRegularExpression(pattern: #"\[[A-Z_]+_\d+\]"#)
        let text = attributed.string
        // Iterate matches back-to-front so earlier NSRanges remain valid after each replacement.
        for m in regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).reversed() {
            let token = (text as NSString).substring(with: m.range)
            attributed.replaceCharacters(in: m.range, with: transform(token))
        }
        let data = try attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: docType])
        try data.write(to: output, options: .atomic)
    }
}
