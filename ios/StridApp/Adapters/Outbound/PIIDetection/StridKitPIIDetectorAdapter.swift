import Foundation
import StridKit

final class StridKitPIIDetectorAdapter: PIIDetectorPort {
    private let engine = StridEngine()

    func detect(in text: String) async -> [DetectedPII] {
        let entities = engine.detect(in: text)
        return entities.map { DetectedPII(entity: $0) }
    }

    func redact(_ text: String) async -> String {
        engine.redact(text)
    }
}
