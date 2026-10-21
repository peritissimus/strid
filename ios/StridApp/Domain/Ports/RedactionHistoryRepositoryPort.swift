//
//  RedactionHistoryRepositoryPort.swift
//  StridApp
//
//  Hexagonal architecture role: **outbound port** (driven-side interface).
//
//  Persistence contract for the text-redaction audit trail
//  (`RedactionHistoryEntry`). Written by `RecordRedactionUseCase`, read by
//  `GetRedactionHistoryUseCase`. The shipping adapter is
//  `InMemoryRedactionHistoryRepository`.
//

import Foundation

/// Port for managing redaction history persistence
protocol RedactionHistoryRepositoryPort {
    /// Add a new redaction entry to history
    ///
    /// - Parameter entry: The completed redaction to record.
    func addEntry(_ entry: RedactionHistoryEntry) async

    /// Get all history entries, sorted by most recent first
    func getAllEntries() async -> [RedactionHistoryEntry]

    /// Get entries for a specific document
    ///
    /// - Parameter documentId: The `Document.id` to filter by.
    /// - Returns: Matching entries, most recent first.
    func getEntries(forDocument documentId: UUID) async -> [RedactionHistoryEntry]

    /// Delete a specific entry
    ///
    /// - Parameter id: The `RedactionHistoryEntry.id` to remove. Unknown ids
    ///   are ignored.
    func deleteEntry(withId id: UUID) async

    /// Clear all history
    func clearHistory() async

    /// Get total number of redactions performed
    ///
    /// - Returns: The number of stored entries.
    func getTotalRedactionCount() async -> Int
}
