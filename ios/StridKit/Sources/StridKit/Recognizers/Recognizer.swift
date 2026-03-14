import Foundation

/// Protocol for all PII recognizers.
public protocol Recognizer: Sendable {
    /// Scan text and return detected PII entities.
    func recognize(in text: String) -> [PIIEntity]
}
