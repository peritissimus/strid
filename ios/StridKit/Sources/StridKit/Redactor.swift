//
// Redactor.swift
// StridKit
//
// Pure string transformation step of the pipeline: given the original text and the entity list
// produced by `StridEngine.detect(in:)`, produce the redacted text. Contains no detection logic.
//
// `Redactor` is a namespace enum; the reversible, token-based variant (`Redactor.tokenize`) lives
// in `Tokenizer.swift` as an extension so that this file stays about irreversible redaction only.
//
import Foundation

/// Produces redacted text from detected entities.
public enum Redactor {
    /// Redact entities from text using the specified style.
    ///
    /// Entities are expected to be non-overlapping (as returned by `StridEngine.detect`). If
    /// overlapping entities were passed, a later replacement could land inside an already
    /// replaced range and corrupt the output, so callers should always go through the engine.
    ///
    /// - Parameters:
    ///   - text: The original text the entity ranges refer to.
    ///   - entities: Non-overlapping entities to replace.
    ///   - style: Rendering of each replacement (placeholder, asterisks, fill character).
    /// - Returns: A new string with every entity replaced; `text` unchanged if `entities` is empty.
    public static func redact(_ text: String, entities: [PIIEntity], style: RedactionStyle) -> String {
        guard !entities.isEmpty else { return text }

        // Sort entities by range start position in reverse so we can replace from the end.
        // Replacing back-to-front means every earlier `String.Index` stays valid even though the
        // replacement text may be shorter or longer than the span it replaces.
        let sorted = entities.sorted { $0.range.lowerBound > $1.range.lowerBound }

        var result = text
        for entity in sorted {
            let replacement = replacementString(for: entity, style: style)
            result.replaceSubrange(entity.range, with: replacement)
        }

        return result
    }

    /// Build an attributed string with PII ranges highlighted.
    ///
    /// Currently a thin projection that pairs each entity with its range, in the form the UI
    /// preview layer consumes to apply highlight attributes. Kept as an API seam so highlighting
    /// logic (merging adjacent ranges, colouring by type) can grow here without touching callers.
    ///
    /// - Parameters:
    ///   - text: The source text (unused today; retained for API symmetry with `redact`).
    ///   - entities: Entities to highlight.
    /// - Returns: One `(range, entity)` tuple per entity, in input order.
    public static func highlightedRanges(in text: String, entities: [PIIEntity]) -> [(range: Range<String.Index>, entity: PIIEntity)] {
        entities.map { (range: $0.range, entity: $0) }
    }

    /// Computes the replacement text for a single entity under the given style.
    ///
    /// - `.placeholder` emits the entity type's raw value in angle brackets, e.g. `<IN_PAN>`.
    /// - `.asterisks` and `.charFill` emit one character per *grapheme* of the original, so the
    ///   visual width of the redacted span roughly matches the original.
    private static func replacementString(for entity: PIIEntity, style: RedactionStyle) -> String {
        switch style {
        case .placeholder:
            return "<\(entity.type.rawValue)>"
        case .asterisks:
            return String(repeating: "*", count: entity.text.count)
        case .charFill(let char):
            return String(repeating: char, count: entity.text.count)
        }
    }
}
