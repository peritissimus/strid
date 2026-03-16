import Foundation
import StridKit

struct DetectedPII: Identifiable, Codable {
    let id: UUID
    let entity: PIIEntity

    init(id: UUID = UUID(), entity: PIIEntity) {
        self.id = id
        self.entity = entity
    }

    var type: PIIEntityType { entity.type }
    var text: String { entity.text }
    var score: Double { entity.score }
    var range: Range<String.Index> { entity.range }

    // MARK: - Codable Implementation

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case text
        case score
        case rangeStart
        case rangeEnd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)

        let type = try container.decode(PIIEntityType.self, forKey: .type)
        let text = try container.decode(String.self, forKey: .text)
        let score = try container.decode(Double.self, forKey: .score)
        let rangeStart = try container.decode(Int.self, forKey: .rangeStart)
        let rangeEnd = try container.decode(Int.self, forKey: .rangeEnd)

        // Reconstruct range from offsets
        let startIndex = text.index(text.startIndex, offsetBy: rangeStart)
        let endIndex = text.index(text.startIndex, offsetBy: rangeEnd)
        let range = startIndex..<endIndex

        self.entity = PIIEntity(type: type, text: text, range: range, score: score)
    }

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
