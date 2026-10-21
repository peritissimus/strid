//
// RedactionPolicy.swift
// StridKit
//
// Per-run rules layered on top of the engine's detection: which entity types
// to report, literal terms the user wants redacted no matter what the models
// think, literal terms that must stay readable (a vendor name, a bank's own
// name), and individual findings the user unticked in a review step.
//
// The engine itself stays immutable and shared; a policy is a value passed
// with each `detect` call, so one engine can serve jobs with different rules.
//
import Foundation

/// Rules for one detection run. `.default` reports every finding unchanged.
public struct RedactionPolicy: Sendable, Equatable {
    /// A literal the user asked to always redact, with the type it should be reported as.
    public struct Term: Sendable, Equatable, Hashable {
        public var text: String
        public var type: PIIEntityType
        public init(_ text: String, type: PIIEntityType) {
            self.text = text
            self.type = type
        }
    }

    /// Entity types to report. `nil` means every type.
    public var enabledTypes: Set<PIIEntityType>?

    /// Literals redacted on every occurrence, case-insensitively, regardless of
    /// score or `enabledTypes`. Matched on word boundaries so "Rahul" does not
    /// hit "Rahulpur"; digit runs are matched with spaces and dashes ignored so
    /// "5012 3456 7890" and "501234567890" are the same account number.
    public var alwaysRedact: [Term] = []

    /// Literals that are never redacted even when a recognizer flags them.
    /// A finding is dropped when its whole text equals a kept term, or when the
    /// finding lies entirely inside a kept phrase ("Amazon Seller Services").
    public var keepVisible: [String] = []

    /// Exact finding texts the user unticked during review, compared after
    /// `RedactionPolicy.normalise`.
    public var excludedValues: Set<String> = []

    public static let `default` = RedactionPolicy()

    public init(enabledTypes: Set<PIIEntityType>? = nil, alwaysRedact: [Term] = [],
                keepVisible: [String] = [], excludedValues: Set<String> = []) {
        self.enabledTypes = enabledTypes
        self.alwaysRedact = alwaysRedact
        self.keepVisible = keepVisible
        self.excludedValues = excludedValues
    }

    /// `true` when the policy changes nothing.
    public var isDefault: Bool { self == .default }

    // MARK: - Normalisation

    /// Canonical form used for value comparison: lower-cased, whitespace
    /// collapsed to single spaces, and for strings that are mostly digits
    /// every space and dash removed.
    public static func normalise(_ s: String) -> String {
        let collapsed = s.lowercased()
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let digits = collapsed.filter(\.isNumber).count
        let letters = collapsed.filter(\.isLetter).count
        if digits > 0, digits >= letters {
            return collapsed.filter { !$0.isWhitespace && $0 != "-" }
        }
        return collapsed
    }

    // MARK: - Application

    /// Findings for the always-redact terms in `text`, each at score 1.
    func termEntities(in text: String) -> [PIIEntity] {
        var out: [PIIEntity] = []
        for term in alwaysRedact {
            let needle = term.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty, let regex = Self.regex(for: needle) else { continue }
            let ns = text as NSString
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard let r = Range(m.range, in: text) else { continue }
                out.append(PIIEntity(type: term.type, text: String(text[r]), range: r, score: 1.0))
            }
        }
        return out
    }

    /// Regex for one literal: word-bounded, case-insensitive, with every run
    /// of spaces or dashes inside a mostly-numeric term allowed to vary.
    static func regex(for needle: String) -> NSRegularExpression? {
        let numeric = needle.filter(\.isNumber).count >= max(1, needle.filter(\.isLetter).count)
        var pattern = ""
        if numeric {
            // Each significant character may be followed by optional separators.
            let chars = needle.filter { !$0.isWhitespace && $0 != "-" }
            pattern = chars.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "[ \\-]?")
        } else {
            pattern = needle.split(whereSeparator: \.isWhitespace)
                .map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s+")
        }
        return try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])" + pattern + "(?![\\p{L}\\p{N}])",
                                        options: [.caseInsensitive])
    }

    /// Drops findings the policy rejects: disabled types, kept literals and
    /// unticked values. Always-redact findings are never dropped.
    func filter(_ entities: [PIIEntity], in text: String) -> [PIIEntity] {
        let kept = keepVisible.map(Self.normalise).filter { !$0.isEmpty }
        let keptRanges = keepRanges(in: text)
        return entities.filter { e in
            if e.score >= 1.0, alwaysRedact.contains(where: { $0.type == e.type && Self.normalise($0.text) == Self.normalise(e.text) }) {
                return true
            }
            if let enabled = enabledTypes, !enabled.contains(e.type) { return false }
            let norm = Self.normalise(e.text)
            if excludedValues.contains(norm) { return false }
            if kept.contains(norm) { return false }
            if keptRanges.contains(where: { $0.lowerBound <= e.range.lowerBound && e.range.upperBound <= $0.upperBound }) { return false }
            return true
        }
    }

    /// Ranges in `text` covered by a kept phrase, so findings inside them can be dropped.
    private func keepRanges(in text: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        for phrase in keepVisible {
            let needle = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty, let regex = Self.regex(for: needle) else { continue }
            let ns = text as NSString
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                if let r = Range(m.range, in: text) { out.append(r) }
            }
        }
        return out
    }
}
