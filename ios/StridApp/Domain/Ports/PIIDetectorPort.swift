import Foundation

protocol PIIDetectorPort {
    func detect(in text: String) async -> [DetectedPII]
    func redact(_ text: String) async -> String
}
