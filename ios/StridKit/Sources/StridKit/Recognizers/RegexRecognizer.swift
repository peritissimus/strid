//
// RegexRecognizer.swift
// StridKit
//
// The workhorse recognizer behind almost every `IN_*` entity type. Each instance is configured
// declaratively (see `IndianBankingRecognizers`) with:
//
//   - one or more regex patterns describing the identifier's *shape*,
//   - a base confidence for a bare shape match,
//   - optional context words whose presence near the match adds `contextBoost`,
//   - an optional validator (checksum / structural test) that can veto a match or raise it to
//     `validatedScore`.
//
// This split lets weak shapes (e.g. "any 9-18 digits" for bank accounts) start below the
// threshold and only surface when the surrounding text says "A/c No" or the checksum agrees.
//
import Foundation

/// A reusable regex-based recognizer with optional context word boosting.
public struct RegexRecognizer: Recognizer {
    /// Type assigned to every match of this recognizer.
    public let entityType: PIIEntityType
    /// Compiled patterns. Patterns that fail to compile are silently dropped at init.
    public let patterns: [NSRegularExpression]
    /// Score of a bare match with no context and no validator.
    public let baseScore: Double
    /// Lower-cased words/phrases that indicate the right context, e.g. `"ifsc"`, `"a/c no"`.
    public let contextWords: [String]
    /// Added to the score (capped at 1.0) when any context word is found in the window.
    public let contextBoost: Double
    /// How far (in characters) to look around a match for context words.
    public let contextWindow: Int
    /// Characters to look *after* the match; defaults to `contextWindow`. Set small for label: value fields.
    ///
    /// Example: for "DOB: 12/03/1990  Account No: 1234567890", a small `contextAfter` on the DOB
    /// recognizer stops "account" (which follows the date) from being treated as birth context.
    public let contextAfter: Int
    /// Optional checksum / structural validator. A failing match is dropped.
    public let validator: (@Sendable (String) -> Bool)?
    /// Score when the validator passes (validators are strong evidence).
    public let validatedScore: Double

    /// - Parameters:
    ///   - entityType: Type to assign to matches.
    ///   - patterns: Regex source strings, compiled with default options (case-sensitive).
    ///   - baseScore: Confidence for a shape-only match.
    ///   - contextWords: Context vocabulary; matched case-insensitively as substrings of the window.
    ///   - contextBoost: Score increment when context is present.
    ///   - contextWindow: Characters to inspect before the match (and after, unless `contextAfter`).
    ///   - contextAfter: Characters to inspect after the match; `nil` means same as `contextWindow`.
    ///   - validator: Returns `false` to reject a match outright.
    ///   - validatedScore: Score floor applied when `validator` returns `true`.
    public init(
        entityType: PIIEntityType,
        patterns: [String],
        baseScore: Double = 0.6,
        contextWords: [String] = [],
        contextBoost: Double = 0.35,
        contextWindow: Int = 100,
        contextAfter: Int? = nil,
        validator: (@Sendable (String) -> Bool)? = nil,
        validatedScore: Double = 0.85
    ) {
        self.entityType = entityType
        self.patterns = patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
        self.baseScore = baseScore
        self.contextWords = contextWords.map { $0.lowercased() }
        self.contextBoost = contextBoost
        self.contextWindow = contextWindow
        self.contextAfter = contextAfter ?? contextWindow
        self.validator = validator
        self.validatedScore = validatedScore
    }

    /// Runs every pattern and scores each match.
    ///
    /// Scoring per match:
    ///   1. start at `baseScore`;
    ///   2. if a validator exists, reject on `false`, else raise to at least `validatedScore`;
    ///   3. if any context word appears in the window, add `contextBoost` (cap 1.0).
    /// Matches from different patterns may overlap; `StridEngine` resolves that later.
    ///
    /// - Parameter text: Text to scan.
    /// - Returns: One entity per surviving regex match.
    public func recognize(in text: String) -> [PIIEntity] {
        var entities: [PIIEntity] = []
        let nsText = text as NSString

        for regex in patterns {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                guard let swiftRange = Range(match.range, in: text) else { continue }
                let matched = String(text[swiftRange])

                var score = baseScore
                if let validator {
                    guard validator(matched) else { continue }
                    score = max(score, validatedScore)
                }
                if !contextWords.isEmpty && hasContext(around: match.range, in: text, nsText: nsText) {
                    score = min(score + contextBoost, 1.0)
                }

                entities.append(PIIEntity(
                    type: entityType,
                    text: matched,
                    range: swiftRange,
                    score: score
                ))
            }
        }

        return entities
    }

    /// Checks whether any context word occurs in the text surrounding a match.
    ///
    /// The window spans `contextWindow` UTF-16 units before the match and `contextAfter` after it,
    /// clamped to the string bounds, and is compared lower-cased. This is a plain substring test,
    /// so `"pan"` also matches inside "company"; context words are chosen with that in mind and
    /// the boost is bounded, so an accidental hit never promotes a match beyond 1.0.
    private func hasContext(around range: NSRange, in text: String, nsText: NSString) -> Bool {
        let start = max(0, range.location - contextWindow)
        let end = min(nsText.length, range.location + range.length + contextAfter)
        let windowRange = NSRange(location: start, length: end - start)
        let window = nsText.substring(with: windowRange).lowercased()
        return contextWords.contains { window.contains($0) }
    }
}
