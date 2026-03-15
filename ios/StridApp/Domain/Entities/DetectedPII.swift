import Foundation
import StridKit

struct DetectedPII: Identifiable {
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
}
