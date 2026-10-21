import Foundation

/// Main PII detection and redaction engine.
public final class StridEngine: Sendable {
    private let recognizers: [Recognizer]
    private let threshold: Double
    private let allowedTypes: Set<PIIEntityType>?

    /// - Parameters:
    ///   - threshold: Minimum confidence score for an entity to be reported.
    ///   - entities: If provided, only these entity types are reported. `nil` means all types.
    public init(threshold: Double = 0.5, entities: Set<PIIEntityType>? = nil) {
        self.recognizers = [
            NLPRecognizer(),
            DataDetectorRecognizer(),
        ] + IndianBankingRecognizers.all()
        self.threshold = threshold
        self.allowedTypes = entities
    }

    /// Detect all PII entities in the given text.
    public func detect(in text: String) -> [PIIEntity] {
        var allEntities: [PIIEntity] = []

        for recognizer in recognizers {
            let found = recognizer.recognize(in: text)
            allEntities.append(contentsOf: found)
        }

        // Filter by threshold, deduplicate overlapping ranges (keep highest score)
        let filtered = EntityFilters.apply(allEntities).filter { entity in
            entity.score >= threshold && (allowedTypes?.contains(entity.type) ?? true)
        }
        return deduplicateOverlaps(filtered)
    }

    /// Redact PII from text using the given style.
    public func redact(_ text: String, style: RedactionStyle = .placeholder) -> String {
        let entities = detect(in: text)
        return Redactor.redact(text, entities: entities, style: style)
    }

    /// Generic model-derived types lose ties against structured identifiers.
    private static func specificity(_ t: PIIEntityType) -> Int {
        switch t {
        case .phone, .location, .organization, .url: 0
        case .person: 1
        default: 2
        }
    }

    /// Deduplicate overlapping entities — when two entities overlap, keep the one with the higher score.
    /// If scores are equal, keep the longer match.
    private func deduplicateOverlaps(_ entities: [PIIEntity]) -> [PIIEntity] {
        guard !entities.isEmpty else { return [] }

        // Sort by start position, then by length descending
        let sorted = entities.sorted { a, b in
            if a.range.lowerBound == b.range.lowerBound {
                return a.text.count > b.text.count
            }
            return a.range.lowerBound < b.range.lowerBound
        }

        var result: [PIIEntity] = []
        var lastEnd: String.Index?

        for entity in sorted {
            if let end = lastEnd, entity.range.lowerBound < end {
                // Overlapping — replace if this one has a higher score
                if let last = result.last, entity.score > last.score
                    || (entity.score == last.score && Self.specificity(entity.type) > Self.specificity(last.type)) {
                    result.removeLast()
                    result.append(entity)
                    lastEnd = entity.range.upperBound
                }
                // Otherwise skip
            } else {
                result.append(entity)
                lastEnd = entity.range.upperBound
            }
        }

        return result
    }
}
