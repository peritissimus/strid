//
// StridEngine.swift
// StridKit
//
// The orchestrator of the detection pipeline and the main public entry point of StridKit.
//
// `detect(in:)` runs these stages in order:
//
//   1. Run every recognizer over the text and concatenate their candidates.
//   2. `EntityFilters.apply`     drop systematic false positives (labels, headers, short tokens).
//   3. Threshold + allow-list    keep only entities scoring >= `threshold` and of allowed types.
//   4. `deduplicateOverlaps`     resolve overlapping spans to a single winner per region.
//   5. `extendAcrossWraps`       grow structured identifiers that PDF extraction split across lines.
//
// `redact(_:style:)` is a convenience that chains `detect` with `Redactor.redact`.
//
import Foundation

/// Main PII detection and redaction engine.
///
/// Immutable after construction and `Sendable`, so one instance can be created at app launch
/// and shared freely. Construction compiles every regex in `IndianBankingRecognizers`, so avoid
/// creating engines in a tight loop.
public final class StridEngine: Sendable {
    /// Ordered list of detectors. Order does not affect results: all output is merged and
    /// resolved by score and specificity, never by which recognizer ran first.
    private let recognizers: [Recognizer]
    /// Minimum `PIIEntity.score` for an entity to survive stage 3.
    private let threshold: Double
    /// Optional allow-list of entity types; `nil` means every type is reported.
    private let allowedTypes: Set<PIIEntityType>?

    /// - Parameters:
    ///   - threshold: Minimum confidence score for an entity to be reported.
    ///   - entities: If provided, only these entity types are reported. `nil` means all types.
    public init(threshold: Double = 0.5, entities: Set<PIIEntityType>? = nil) {
        self.recognizers = [
            NLPRecognizer(),           // Apple NLTagger: person / place / organisation
            DataDetectorRecognizer(),  // NSDataDetector: email / phone / URL / address
        ] + IndianBankingRecognizers.all()  // regex + narration + gazetteer recognizers
        self.threshold = threshold
        self.allowedTypes = entities
    }

    /// Detect all PII entities in the given text.
    ///
    /// - Parameter text: Text to scan. Returned ranges index into this string.
    /// - Returns: Non-overlapping entities sorted by position, each at or above the threshold.
    public func detect(in text: String) -> [PIIEntity] {
        var allEntities: [PIIEntity] = []

        // Stage 1: gather every candidate from every recognizer.
        for recognizer in recognizers {
            let found = recognizer.recognize(in: text)
            allEntities.append(contentsOf: found)
        }

        // Stages 2 + 3: filter by threshold, deduplicate overlapping ranges (keep highest score)
        let filtered = EntityFilters.apply(allEntities).filter { entity in
            entity.score >= threshold && (allowedTypes?.contains(entity.type) ?? true)
        }
        // Stages 4 + 5.
        return extendAcrossWraps(deduplicateOverlaps(filtered), in: text)
    }

    // MARK: - Line-wrap extension

    /// PDF tables wrap long identifiers mid-token across visual lines, so an entity can end exactly at a
    /// line break with its tail on the next line (or start at a line beginning with its head above).
    /// Extend such entities over the adjoining alphanumeric run, as long as that run is not a date,
    /// an amount, or the start of a new row.
    ///
    /// Example (narration column of a statement, text layer extracted by PDFKit):
    ///
    ///     UPI-PRIYA MEHTA-priya.mehta@oksbi-UTIB0001234-5254123
    ///     45678-PAYMENT
    ///
    /// The txn-ref regex matches `5254123` (ends at `\n`); the next line starts with `45678`, a
    /// pure-digit run followed by `-`, so the entity grows to cover `5254123\n45678`. Redacting the
    /// grown range then blacks out both fragments instead of leaving `45678` legible.
    ///
    /// Only "structured" identifier types are extended; names and locations are never grown.
    private func extendAcrossWraps(_ entities: [PIIEntity], in text: String) -> [PIIEntity] {
        let structured: Set<PIIEntityType> = [.inTxnRef, .inUPIID, .inIFSC, .inBankAccount, .inCustomerID, .email, .creditCard, .inAadhaar]
        return entities.map { e in
            guard structured.contains(e.type) else { return e }
            var lower = e.range.lowerBound, upper = e.range.upperBound

            // Tail on the next line.
            // Entity ends immediately before "\n": look at the run that starts the following line.
            if upper < text.endIndex, text[upper] == "\n" {
                let next = text.index(after: upper)
                if let run = Self.leadingRun(in: text, from: next), Self.plausibleWrapFragment(text[run]) {
                    upper = run.upperBound
                }
            }
            // Head on the previous line.
            // Entity starts immediately after "\n": look at the run that ends the preceding line.
            // The head is capped at 8 characters because a long trailing run on the previous line
            // is far more likely to be a complete separate value (an amount, another reference).
            if lower > text.startIndex, text[text.index(before: lower)] == "\n" {
                let lineEnd = text.index(before: lower)
                if let run = Self.trailingRun(in: text, upTo: lineEnd), Self.plausibleWrapFragment(text[run]),
                   text.distance(from: run.lowerBound, to: run.upperBound) <= 8 {
                    lower = run.lowerBound
                }
            }
            // Nothing changed: return the original instance (keeps its id and avoids a copy).
            guard lower != e.range.lowerBound || upper != e.range.upperBound else { return e }
            let r = lower..<upper
            // The new `text` includes the embedded "\n"; that is intentional so the redacted
            // output replaces the whole span, newline included.
            return PIIEntity(type: e.type, text: String(text[r]), range: r, score: e.score)
        }
    }

    /// Characters that can be part of a wrapped identifier fragment: letters, digits, and the
    /// `@` / `.` found inside UPI IDs and email addresses.
    private static let runChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@."))

    /// Longest run of `runChars` starting exactly at `start`.
    ///
    /// Only single-scalar characters are accepted (`unicodeScalars.count == 1`), which keeps
    /// combining marks and emoji out of the run and makes the `CharacterSet` test meaningful.
    ///
    /// - Returns: The run's range, or `nil` if there is no run or it is terminated by a character
    ///   that indicates the run is really part of a different value.
    private static func leadingRun(in text: String, from start: String.Index) -> Range<String.Index>? {
        var i = start
        while i < text.endIndex, let u = text[i].unicodeScalars.first, text[i].unicodeScalars.count == 1, runChars.contains(u) {
            i = text.index(after: i)
        }
        guard i > start else { return nil }
        // Must be followed by whitespace/EOL or a narration separator, never ',' (amount) or '/' (date).
        // e.g. "45678-PAYMENT" is a continuation; "45,678.00" is an amount; "12/03/2024" is a date.
        if i < text.endIndex, !(text[i].isWhitespace || text[i] == "-") { return nil }
        return start..<i
    }

    /// Longest run of `runChars` ending exactly at `end` (exclusive), scanning backwards.
    ///
    /// Mirror image of `leadingRun`: the run must be *preceded* by whitespace, line start, or a
    /// `-` separator so that we never bite the tail off an unrelated adjacent value.
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
    ///
    /// Accepts, in order of the `return` expression:
    ///   - any all-digit run (`45678`, `000123456789`): the common wrapped-number case,
    ///   - a short mixed run with at least one digit (`N2452`, `7A3B`): wrapped alnum refs,
    ///   - up to four upper-case letters/digits (`UTIB`, `HDFC`): the head of a wrapped IFSC or
    ///     bank-prefixed reference.
    /// Rejects anything over 16 characters, anything containing `/` (dates), and plain words.
    private static func plausibleWrapFragment(_ s: Substring) -> Bool {
        guard !s.isEmpty, s.count <= 16, !s.contains("/") else { return false }
        let digits = s.filter(\.isNumber).count
        // Pure digits of any length, or short mixed fragments; never a plain word.
        return digits == s.count || (digits > 0 && s.count <= 8) || (s.count <= 4 && s.allSatisfy { $0.isUppercase || $0.isNumber })
    }

    // MARK: - Redaction

    /// Redact PII from text using the given style.
    ///
    /// Convenience for `Redactor.redact(text, entities: detect(in: text), style: style)`.
    ///
    /// - Parameters:
    ///   - text: Text to redact.
    ///   - style: Replacement rendering; defaults to `<TYPE>` placeholders.
    /// - Returns: The redacted text.
    public func redact(_ text: String, style: RedactionStyle = .placeholder) -> String {
        let entities = detect(in: text)
        return Redactor.redact(text, entities: entities, style: style)
    }

    // MARK: - Overlap resolution

    /// Generic model-derived types lose ties against structured identifiers.
    ///
    /// Used only when two overlapping entities have *exactly* the same score. Higher wins:
    ///   - 0: NSDataDetector / NLTagger catch-alls (phone, location, organisation, URL)
    ///   - 1: person names
    ///   - 2: everything else (PAN, IFSC, Aadhaar, UPI, card, txn ref, ...)
    /// So a `1.0`-scored IFSC beats a `1.0`-scored NLTagger "organisation" over the same text.
    private static func specificity(_ t: PIIEntityType) -> Int {
        switch t {
        case .phone, .location, .organization, .url: 0
        case .person: 1
        default: 2
        }
    }

    /// Deduplicate overlapping entities — when two entities overlap, keep the one with the higher score.
    /// If scores are equal, keep the longer match.
    ///
    /// Algorithm: a single sweep over entities sorted by start position (longest first on ties).
    /// `lastEnd` tracks the right edge of the most recently accepted entity. Any entity starting
    /// before `lastEnd` overlaps the accepted one and either replaces it (higher score, or equal
    /// score and more specific type) or is dropped. Because the sort puts the longest span first
    /// among equal starts, "keep the longer match" falls out naturally: the shorter one arrives
    /// second and loses unless it scores strictly higher.
    ///
    /// Note that replacement compares against `result.last` only; a chain A-B-C where B replaces
    /// A and C overlaps only A is handled correctly because `lastEnd` is reset to B's end.
    ///
    /// - Parameter entities: Filtered entities, any order.
    /// - Returns: Non-overlapping entities in ascending position order.
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
                // (or the same score with a more specific type, see `specificity`).
                if let last = result.last, entity.score > last.score
                    || (entity.score == last.score && Self.specificity(entity.type) > Self.specificity(last.type)) {
                    result.removeLast()
                    result.append(entity)
                    lastEnd = entity.range.upperBound
                }
                // Otherwise skip
            } else {
                // No overlap with the last accepted entity: accept and advance the sweep edge.
                result.append(entity)
                lastEnd = entity.range.upperBound
            }
        }

        return result
    }
}
