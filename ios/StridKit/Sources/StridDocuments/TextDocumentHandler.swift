import Foundation
import StridKit

/// Plain text, CSV, Markdown, JSON: string replacement.
public struct TextDocumentHandler: DocumentHandler {
    public init() {}

    public func redact(input: URL, output: URL, engine: StridEngine, style: RedactionStyle, options: DocumentOptions) throws -> RedactionReport {
        guard let text = try? String(contentsOf: input, encoding: .utf8) else {
            throw DocumentRedactionError.unreadable(input)
        }
        let entities = engine.detect(in: text)
        var report = RedactionReport(pages: 1, entities: entities)
        let redacted: String
        if options.reversible {
            var map = TokenMap()
            redacted = Redactor.tokenize(text, entities: entities, map: &map)
            report.tokens = map
        } else {
            redacted = Redactor.redact(text, entities: entities, style: style)
        }
        try redacted.write(to: output, atomically: true, encoding: .utf8)
        return report
    }
}
