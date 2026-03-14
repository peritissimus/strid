import Foundation

/// Produces redacted text from detected entities.
public enum Redactor {
    /// Redact entities from text using the specified style.
    public static func redact(_ text: String, entities: [PIIEntity], style: RedactionStyle) -> String {
        guard !entities.isEmpty else { return text }

        // Sort entities by range start position in reverse so we can replace from the end
        let sorted = entities.sorted { $0.range.lowerBound > $1.range.lowerBound }

        var result = text
        for entity in sorted {
            let replacement = replacementString(for: entity, style: style)
            result.replaceSubrange(entity.range, with: replacement)
        }

        return result
    }

    /// Build an attributed string with PII ranges highlighted.
    public static func highlightedRanges(in text: String, entities: [PIIEntity]) -> [(range: Range<String.Index>, entity: PIIEntity)] {
        entities.map { (range: $0.range, entity: $0) }
    }

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
