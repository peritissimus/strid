import Foundation
import StridKit

/// DOCX and RTF via Foundation's attributed-string document readers and writers.
/// Keeps paragraph and run formatting; replaces PII spans with the redaction string.
public struct AttributedDocumentHandler: DocumentHandler {
    public init() {}

    public func redact(input: URL, output: URL, engine: StridEngine, style: RedactionStyle, options: DocumentOptions) throws -> RedactionReport {
        let docType: NSAttributedString.DocumentType =
            input.pathExtension.lowercased() == "rtf" ? .rtf : .officeOpenXML
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
    static func rewrite(_ input: URL, to output: URL, transform: (String) -> String) throws {
        let docType: NSAttributedString.DocumentType = input.pathExtension.lowercased() == "rtf" ? .rtf : .officeOpenXML
        guard let attributed = try? NSMutableAttributedString(url: input, options: [.documentType: docType], documentAttributes: nil) else {
            throw DocumentRedactionError.unreadable(input)
        }
        // Tokens are bracketed and never span attribute runs in practice, so replace per token occurrence.
        let regex = try NSRegularExpression(pattern: #"\[[A-Z_]+_\d+\]"#)
        let text = attributed.string
        for m in regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).reversed() {
            let token = (text as NSString).substring(with: m.range)
            attributed.replaceCharacters(in: m.range, with: transform(token))
        }
        let data = try attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: docType])
        try data.write(to: output, options: .atomic)
    }
}
