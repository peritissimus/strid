//
//  PIIDetectorPort.swift
//  StridApp
//
//  Hexagonal architecture role: **outbound port** (driven-side interface).
//
//  The domain's view of "something that can find and mask PII in text". It
//  deliberately exposes only two operations so the use cases never import
//  StridKit directly; `StridKitPIIDetectorAdapter` bridges to the real engine
//  and tests can plug in a deterministic fake.
//

import Foundation

/// Abstraction over the PII detection engine.
protocol PIIDetectorPort {
    /// Finds every PII span in `text`.
    ///
    /// - Parameter text: Plain text to scan.
    /// - Returns: Detected entities in the order the engine reports them.
    func detect(in text: String) async -> [DetectedPII]

    /// Returns `text` with every detected PII span replaced by a placeholder.
    ///
    /// - Parameter text: Plain text to redact.
    /// - Returns: The masked text, same length or shorter/longer depending on
    ///   the placeholder style.
    func redact(_ text: String) async -> String
}
