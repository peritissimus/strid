import Foundation

/// A reversible redaction: every distinct (type, value) pair gets a stable token such as `[PERSON_1]`.
public struct TokenMap: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public let token: String
        public let type: PIIEntityType
        public let value: String
    }
    public private(set) var entries: [Entry] = []
    private var index: [String: String] = [:]   // "TYPE\u{0}value" -> token
    private var counters: [PIIEntityType: Int] = [:]

    public init() {}

    /// Returns the token for a value, allocating a new one on first sight.
    public mutating func token(for entity: PIIEntity) -> String {
        token(type: entity.type, value: entity.text)
    }

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

    public func value(for token: String) -> String? {
        entries.first { $0.token == token }?.value
    }

    /// Reverses tokens in text. Longest tokens first so `[PERSON_1]` does not clobber `[PERSON_10]`.
    public func restore(_ text: String) -> String {
        var out = text
        for e in entries.sorted(by: { $0.token.count > $1.token.count }) {
            out = out.replacingOccurrences(of: e.token, with: e.value)
        }
        return out
    }

    enum CodingKeys: String, CodingKey { case entries }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decode([Entry].self, forKey: .entries)
        for e in entries {
            index[e.type.rawValue + "\u{0}" + e.value] = e.token
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
    static func tokenize(_ text: String, entities: [PIIEntity], map: inout TokenMap) -> String {
        guard !entities.isEmpty else { return text }
        var result = text
        for e in entities.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            result.replaceSubrange(e.range, with: map.token(for: e))
        }
        return result
    }
}
