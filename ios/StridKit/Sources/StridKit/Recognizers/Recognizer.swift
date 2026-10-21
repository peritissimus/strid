//
// Recognizer.swift
// StridKit
//
// The single abstraction every detector in the pipeline conforms to. `StridEngine` holds an
// array of `Recognizer`s, runs each over the input text, concatenates their results, and then
// filters, deduplicates and post-processes the combined entity list. Concrete implementations:
//
//   - `RegexRecognizer`         pattern + context-word + checksum based (most Indian banking types)
//   - `NLPRecognizer`           Apple NLTagger named-entity recognition (person / place / org)
//   - `DataDetectorRecognizer`  NSDataDetector (email, phone, URL, postal address)
//   - `NarrationRecognizer`     template parser for ALL-CAPS bank statement narrations
//   - `IndianPlaceRecognizer`   gazetteer of Indian states and cities
//
import Foundation

/// Protocol for all PII recognizers.
///
/// A recognizer is a stateless, thread-safe scanner: given the full text of a document (or page)
/// it returns every candidate entity it can find, each with a confidence `score` in `0...1`.
/// Recognizers should *not* worry about overlaps with other recognizers or about thresholds;
/// `StridEngine` resolves both centrally. Returning a low-scored candidate is preferable to
/// returning nothing, because context words and validators can raise or lower it later.
///
/// Conformance to `Sendable` lets `StridEngine` itself be `Sendable` and be shared across
/// concurrency domains (e.g. a SwiftUI view model and a background detection task).
public protocol Recognizer: Sendable {
    /// Scan text and return detected PII entities.
    ///
    /// - Parameter text: The complete text to scan. Ranges in the returned entities are
    ///   `String.Index` ranges into *this exact string*, so callers must keep it unmodified
    ///   until they have finished using the ranges.
    /// - Returns: Zero or more entities, in no particular order, possibly overlapping each other
    ///   or entities from other recognizers.
    func recognize(in text: String) -> [PIIEntity]
}
