//
// TextDocumentHandler.swift
// StridDocuments
//
// Simplest format handler: anything UTF-8 (plain text, CSV, Markdown, JSON, logs) is read as a
// string, run through the engine, and written back as a string. Either irreversible
// (`Redactor.redact`) or reversible (`Redactor.tokenize`) replacement is used depending on
// whether a vault key was supplied.
//
import Foundation
import StridKit

/// Plain text, CSV, Markdown, JSON: string replacement.
public struct TextDocumentHandler: DocumentHandler {
    public init() {}

    /// Reads `input` as UTF-8, redacts, and writes `output` atomically.
    ///
    /// - Parameters:
    ///   - input: Source file.
    ///   - output: Destination file (overwritten).
    ///   - engine: Detection engine to use.
    ///   - style: Replacement style for irreversible mode; ignored when `options.reversible`.
    ///   - options: `reversible` selects token substitution and populates `report.tokens`.
    /// - Returns: A single-page report listing every redacted entity.
    /// - Throws: `DocumentRedactionError.unreadable` if the file is not valid UTF-8, or any
    ///   file-system error from the write.
    public func redact(input: URL, output: URL, engine: StridEngine, style: RedactionStyle, options: DocumentOptions) throws -> RedactionReport {
        guard let text = try? String(contentsOf: input, encoding: .utf8) else {
            throw DocumentRedactionError.unreadable(input)
        }
        let entities = engine.detect(in: text)
        var report = RedactionReport(pages: 1, entities: entities)
        let redacted: String
        if options.reversible {
            // Stable [TYPE_n] tokens; the map goes into the vault via DocumentRedactor.
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
