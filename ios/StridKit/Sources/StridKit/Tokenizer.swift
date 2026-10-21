//
// Tokenizer.swift
// StridKit
//
// Reversible redaction support. Instead of destroying a span with `<PERSON>` or `****`, the
// reversible pipeline substitutes a *stable token* such as `[PERSON_1]`: the same original value
// always maps to the same token within a document, so a redacted statement stays internally
// consistent ("[PERSON_1] paid [PERSON_2]; [PERSON_2] refunded [PERSON_1]").
//
// `TokenMap` is the lookup table that makes the substitution reversible. It is serialised into
// the encrypted `Vault` sidecar (see `Vault.swift`), never written in clear.
//
import Foundation

/// A reversible redaction: every distinct (type, value) pair gets a stable token such as `[PERSON_1]`.
///
/// Token numbering is per type and allocated in first-seen order. Because text redaction walks
/// entities back-to-front (see `Redactor.tokenize`), the *last* occurrence in the document is
/// typically `_1`; numbering is therefore an identity, not a reading-order index.
public struct TokenMap: Codable, Sendable, Equatable {
    /// One token assignment. This is the only part that is persisted.
    public struct Entry: Codable, Sendable, Equatable {
        /// The bracketed token, e.g. `[IN_PAN_2]`.
        public let token: String
        /// Entity type the value was detected as.
        public let type: PIIEntityType
        /// The original clear-text value the token stands for.
        public let value: String
    }
    /// All assignments in allocation order. Read-only from outside; grows via `token(for:)`.
    public private(set) var entries: [Entry] = []
    /// Reverse lookup from `"TYPE\u{0}value"` to token, so repeated values reuse their token in O(1).
    /// NUL is used as the separator because it cannot appear in a type raw value and is vanishingly
    /// unlikely inside detected text, so the key is unambiguous.
    private var index: [String: String] = [:]   // "TYPE\u{0}value" -> token
    /// Highest ordinal handed out per type, used to allocate the next `_n`.
    private var counters: [PIIEntityType: Int] = [:]

    public init() {}

    /// Returns the token for a value, allocating a new one on first sight.
    ///
    /// - Parameter entity: The detected entity; its `type` and `text` form the lookup key.
    /// - Returns: An existing token if this exact (type, text) was seen before, else a fresh one.
    public mutating func token(for entity: PIIEntity) -> String {
        token(type: entity.type, value: entity.text)
    }

    /// Core allocation routine behind `token(for:)`.
    ///
    /// Lookup is exact: `"Rahul Sharma"` and `"RAHUL SHARMA"` get different tokens, as do the
    /// same string detected as `.person` and as `.organization`.
    ///
    /// - Parameters:
    ///   - type: Entity type; becomes the token prefix.
    ///   - value: Clear-text value.
    /// - Returns: The stable token for this pair.
    public mutating func token(type: PIIEntityType, value: String) -> String {
        let key = type.rawValue + "\u{0}" + value
        if let t = index[key] { return t }
        let n = (counters[type] ?? 0) + 1
        counters[type] = n
        let t = "[\(type.rawValue)_\(n)]"
        index[key] = t
        entries.append(Entry(token: t, type: type, value: value))
        return t
    }

    /// Clear-text value for a token, or `nil` if the token is unknown.
    ///
    /// Linear scan; maps are small (one per document) so this is not a hot path.
    public func value(for token: String) -> String? {
        entries.first { $0.token == token }?.value
    }

    /// Reverses tokens in text. Longest tokens first so `[PERSON_1]` does not clobber `[PERSON_10]`.
    ///
    /// Plain substring replacement: if the redacted text was edited and a token was damaged or
    /// duplicated, restoration is best-effort for that token only.
    ///
    /// - Parameter text: Redacted text containing tokens.
    /// - Returns: Text with every known token replaced by its original value.
    public func restore(_ text: String) -> String {
        var out = text
        for e in entries.sorted(by: { $0.token.count > $1.token.count }) {
            out = out.replacingOccurrences(of: e.token, with: e.value)
        }
        return out
    }

    // MARK: - Codable

    /// Only `entries` is serialised; `index` and `counters` are derived caches.
    enum CodingKeys: String, CodingKey { case entries }

    /// Decodes `entries` and rebuilds the derived lookup structures so that a map loaded from a
    /// vault can keep allocating tokens without collisions.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decode([Entry].self, forKey: .entries)
        for e in entries {
            index[e.type.rawValue + "\u{0}" + e.value] = e.token
            // Recover the ordinal from the token text: "[IN_PAN_12]" -> split on "_" -> "12]" -> drop "]" -> 12.
            let n = Int(e.token.split(separator: "_").last?.dropLast() ?? "") ?? 0
            counters[e.type] = max(counters[e.type] ?? 0, n)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(entries, forKey: .entries)
    }
}

public extension Redactor {
    /// Replaces entities with stable tokens and returns the map needed to reverse it.
    ///
    /// Same back-to-front replacement strategy as `Redactor.redact`, so earlier ranges remain
    /// valid while later (in document order) spans are swapped for tokens of a different length.
    ///
    /// - Parameters:
    ///   - text: Original text.
    ///   - entities: Non-overlapping entities from `StridEngine.detect`.
    ///   - map: Token map to allocate from; pass an existing map to keep tokens consistent across
    ///     multiple pages or files of one job.
    /// - Returns: The tokenised text.
    static func tokenize(_ text: String, entities: [PIIEntity], map: inout TokenMap) -> String {
        guard !entities.isEmpty else { return text }
        var result = text
        for e in entities.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            result.replaceSubrange(e.range, with: map.token(for: e))
        }
        return result
    }
}
