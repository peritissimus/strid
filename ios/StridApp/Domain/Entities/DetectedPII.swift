//
//  DetectedPII.swift
//  StridApp
//
//  Hexagonal architecture role: **domain entity** (thin wrapper over a
//  StridKit value).
//
//  StridKit's `PIIEntity` is the engine's native detection result. The app
//  wraps it in `DetectedPII` for two reasons:
//
//  1. `Identifiable` – SwiftUI `ForEach` needs a stable identity, and
//     `PIIEntity` has none of its own.
//  2. `Codable` – `PIIEntity.range` is a `Range<String.Index>`, which is not
//     serialisable. `DetectedPII` provides a custom encoding that flattens the
//     range into integer offsets so `ScanResults` / `ScannedDocument` can be
//     persisted as JSON.
//

import Foundation
import StridKit

/// A single piece of personally identifiable information found by the
/// detector, with an app-level identity and JSON persistence support.
struct DetectedPII: Identifiable, Codable {
    /// Stable identity for list diffing and persistence.
    let id: UUID

    /// The underlying StridKit detection (type, matched text, range, score).
    let entity: PIIEntity

    /// Wraps a StridKit entity.
    ///
    /// - Parameters:
    ///   - id: Identifier; a fresh `UUID` by default.
    ///   - entity: The detection produced by `StridEngine.detect(in:)`.
    init(id: UUID = UUID(), entity: PIIEntity) {
        self.id = id
        self.entity = entity
    }

    // MARK: - Convenience Accessors

    /// The PII category (e.g. Aadhaar, PAN, email). Forwarded from `entity`.
    var type: PIIEntityType { entity.type }

    /// The exact substring that matched. Forwarded from `entity`.
    var text: String { entity.text }

    /// Detector confidence in `0...1`. Forwarded from `entity`.
    var score: Double { entity.score }

    /// Location of the match within the *source* text (valid only for the
    /// string the entity was detected in; see the `Codable` notes below).
    var range: Range<String.Index> { entity.range }

    // MARK: - Codable Implementation

    /// JSON keys. `PIIEntity` itself is not `Codable`, so its fields are
    /// flattened into this struct's container, with the `String.Index` range
    /// replaced by two integer offsets.
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case text
        case score
        case rangeStart
        case rangeEnd
    }

    /// Rebuilds a `DetectedPII` from JSON.
    ///
    /// The range offsets are applied to the stored `text` (the extracted PII
    /// substring), not to the original document, because the original is not
    /// available at decode time. Combined with `encode(to:)`, this means a
    /// round-tripped entity's `range` always covers the whole of `text`.
    ///
    /// - Throws: `DecodingError` if any key is missing or has the wrong type.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)

        let type = try container.decode(PIIEntityType.self, forKey: .type)
        let text = try container.decode(String.self, forKey: .text)
        let score = try container.decode(Double.self, forKey: .score)
        let rangeStart = try container.decode(Int.self, forKey: .rangeStart)
        let rangeEnd = try container.decode(Int.self, forKey: .rangeEnd)

        // Reconstruct range from offsets. Offsets are Character counts into
        // `text`, matching what `encode(to:)` wrote.
        let startIndex = text.index(text.startIndex, offsetBy: rangeStart)
        let endIndex = text.index(text.startIndex, offsetBy: rangeEnd)
        let range = startIndex..<endIndex

        self.entity = PIIEntity(type: type, text: text, range: range, score: score)
    }

    /// Serialises the entity to JSON.
    ///
    /// The original `range` (which points into the source document) is
    /// deliberately *not* preserved. `String.Index` values are only meaningful
    /// against the string they were created from, so persisting them would be
    /// fragile. Instead the range is normalised to `0..<text.count`, which is
    /// always valid against the stored `text`.
    ///
    /// - Throws: `EncodingError` from the underlying encoder.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(entity.type, forKey: .type)
        try container.encode(entity.text, forKey: .text)
        try container.encode(entity.score, forKey: .score)

        // For persistence, we store simple offsets
        // When decoding, we reconstruct the range as 0..<text.count
        // since entity.text is already the extracted PII text
        try container.encode(0, forKey: .rangeStart)
        try container.encode(entity.text.count, forKey: .rangeEnd)
    }
}
