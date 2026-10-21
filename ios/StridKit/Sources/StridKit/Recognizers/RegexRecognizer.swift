import Foundation

/// A reusable regex-based recognizer with optional context word boosting.
public struct RegexRecognizer: Recognizer {
    public let entityType: PIIEntityType
    public let patterns: [NSRegularExpression]
    public let baseScore: Double
    public let contextWords: [String]
    public let contextBoost: Double
    /// How far (in characters) to look around a match for context words.
    public let contextWindow: Int
    /// Characters to look *after* the match; defaults to `contextWindow`. Set small for label: value fields.
    public let contextAfter: Int
    /// Optional checksum / structural validator. A failing match is dropped.
    public let validator: (@Sendable (String) -> Bool)?
    /// Score when the validator passes (validators are strong evidence).
    public let validatedScore: Double

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

    private func hasContext(around range: NSRange, in text: String, nsText: NSString) -> Bool {
        let start = max(0, range.location - contextWindow)
        let end = min(nsText.length, range.location + range.length + contextAfter)
        let windowRange = NSRange(location: start, length: end - start)
        let window = nsText.substring(with: windowRange).lowercased()
        return contextWords.contains { window.contains($0) }
    }
}
