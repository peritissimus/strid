import Foundation

/// Main PII detection and redaction engine.
public final class StridEngine: Sendable {
    private let recognizers: [Recognizer]
    private let threshold: Double

    public init(threshold: Double = 0.5) {
        self.recognizers = [
            NLPRecognizer(),
            DataDetectorRecognizer(),
        ] + IndianBankingRecognizers.all()
        self.threshold = threshold
    }

    /// Detect all PII entities in the given text.
    public func detect(in text: String) -> [PIIEntity] {
        var allEntities: [PIIEntity] = []

        for recognizer in recognizers {
            let found = recognizer.recognize(in: text)
            allEntities.append(contentsOf: found)
        }

        // Filter by threshold, deduplicate overlapping ranges (keep highest score)
        let filtered = allEntities.filter { $0.score >= threshold }
        return deduplicateOverlaps(filtered)
    }

    /// Redact PII from text using the given style.
    public func redact(_ text: String, style: RedactionStyle = .placeholder) -> String {
        let entities = detect(in: text)
        return Redactor.redact(text, entities: entities, style: style)
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
                if let last = result.last, entity.score > last.score {
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
