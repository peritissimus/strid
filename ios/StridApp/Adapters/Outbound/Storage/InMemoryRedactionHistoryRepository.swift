//
//  InMemoryRedactionHistoryRepository.swift
//  StridApp
//
//  Hexagonal architecture role: **outbound adapter** implementing
//  `RedactionHistoryRepositoryPort`.
//
//  Keeps the text-redaction audit trail in a plain array for the lifetime of
//  the process. History is intentionally not written to disk in this
//  adapter: it contains full original (unredacted) text, and keeping it
//  volatile avoids leaving sensitive content behind.
//
//  Note: this is a `final class`, not an actor. The `async` methods satisfy
//  the port's signature but do not provide isolation on their own; callers
//  (the view models) drive it from the main actor.
//

import Foundation

/// In-memory implementation of redaction history repository
final class InMemoryRedactionHistoryRepository: RedactionHistoryRepositoryPort {
    /// Entries in insertion order. Sorting happens on read.
    private var entries: [RedactionHistoryEntry] = []

    /// Appends an entry.
    func addEntry(_ entry: RedactionHistoryEntry) async {
        entries.append(entry)
    }

    /// All entries, newest first.
    func getAllEntries() async -> [RedactionHistoryEntry] {
        entries.sorted { $0.timestamp > $1.timestamp }
    }

    /// Entries for one document, newest first.
    func getEntries(forDocument documentId: UUID) async -> [RedactionHistoryEntry] {
        entries
            .filter { $0.documentId == documentId }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Removes the entry with `id`; no-op if absent.
    func deleteEntry(withId id: UUID) async {
        entries.removeAll { $0.id == id }
    }

    /// Removes every entry.
    func clearHistory() async {
        entries.removeAll()
    }

    /// Number of stored entries.
    func getTotalRedactionCount() async -> Int {
        entries.count
    }
}
