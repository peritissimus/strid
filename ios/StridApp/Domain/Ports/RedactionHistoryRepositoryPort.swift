import Foundation

/// Port for managing redaction history persistence
protocol RedactionHistoryRepositoryPort {
    /// Add a new redaction entry to history
    func addEntry(_ entry: RedactionHistoryEntry) async

    /// Get all history entries, sorted by most recent first
    func getAllEntries() async -> [RedactionHistoryEntry]

    /// Get entries for a specific document
    func getEntries(forDocument documentId: UUID) async -> [RedactionHistoryEntry]

    /// Delete a specific entry
    func deleteEntry(withId id: UUID) async

    /// Clear all history
    func clearHistory() async

    /// Get total number of redactions performed
    func getTotalRedactionCount() async -> Int
}
