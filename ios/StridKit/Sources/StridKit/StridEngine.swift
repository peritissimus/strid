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
        return extendAcrossWraps(deduplicateOverlaps(filtered), in: text)
    }

    /// PDF tables wrap long identifiers mid-token across visual lines, so an entity can end exactly at a
    /// line break with its tail on the next line (or start at a line beginning with its head above).
    /// Extend such entities over the adjoining alphanumeric run, as long as that run is not a date,
    /// an amount, or the start of a new row.
    private func extendAcrossWraps(_ entities: [PIIEntity], in text: String) -> [PIIEntity] {
        let structured: Set<PIIEntityType> = [.inTxnRef, .inUPIID, .inIFSC, .inBankAccount, .inCustomerID, .email, .creditCard, .inAadhaar]
        return entities.map { e in
            guard structured.contains(e.type) else { return e }
            var lower = e.range.lowerBound, upper = e.range.upperBound

            // Tail on the next line.
            if upper < text.endIndex, text[upper] == "\n" {
                let next = text.index(after: upper)
                if let run = Self.leadingRun(in: text, from: next), Self.plausibleWrapFragment(text[run]) {
                    upper = run.upperBound
                }
            }
            // Head on the previous line.
            if lower > text.startIndex, text[text.index(before: lower)] == "\n" {
                let lineEnd = text.index(before: lower)
                if let run = Self.trailingRun(in: text, upTo: lineEnd), Self.plausibleWrapFragment(text[run]),
                   text.distance(from: run.lowerBound, to: run.upperBound) <= 8 {
                    lower = run.lowerBound
                }
            }
            guard lower != e.range.lowerBound || upper != e.range.upperBound else { return e }
            let r = lower..<upper
            return PIIEntity(type: e.type, text: String(text[r]), range: r, score: e.score)
        }
    }

    private static let runChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@."))

    private static func leadingRun(in text: String, from start: String.Index) -> Range<String.Index>? {
        var i = start
        while i < text.endIndex, let u = text[i].unicodeScalars.first, text[i].unicodeScalars.count == 1, runChars.contains(u) {
            i = text.index(after: i)
        }
        guard i > start else { return nil }
        // Must be followed by whitespace/EOL or a narration separator, never ',' (amount) or '/' (date).
        if i < text.endIndex, !(text[i].isWhitespace || text[i] == "-") { return nil }
        return start..<i
    }

    private static func trailingRun(in text: String, upTo end: String.Index) -> Range<String.Index>? {
        var i = end
        while i > text.startIndex {
            let p = text.index(before: i)
            guard let u = text[p].unicodeScalars.first, text[p].unicodeScalars.count == 1, runChars.contains(u) else { break }
            i = p
        }
        guard i < end else { return nil }
        if i > text.startIndex, !(text[text.index(before: i)].isWhitespace || text[text.index(before: i)] == "-") { return nil }
        return i..<end
    }

    /// Short alnum fragment, not a date, not a word.
    private static func plausibleWrapFragment(_ s: Substring) -> Bool {
        guard !s.isEmpty, s.count <= 16, !s.contains("/") else { return false }
        let digits = s.filter(\.isNumber).count
        // Pure digits of any length, or short mixed fragments; never a plain word.
        return digits == s.count || (digits > 0 && s.count <= 8) || (s.count <= 4 && s.allSatisfy { $0.isUppercase || $0.isNumber })
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
