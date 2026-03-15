import Foundation

/// In-memory implementation of redaction history repository
final class InMemoryRedactionHistoryRepository: RedactionHistoryRepositoryPort {
    private var entries: [RedactionHistoryEntry] = []

    func addEntry(_ entry: RedactionHistoryEntry) async {
        entries.append(entry)
    }

    func getAllEntries() async -> [RedactionHistoryEntry] {
        entries.sorted { $0.timestamp > $1.timestamp }
    }

    func getEntries(forDocument documentId: UUID) async -> [RedactionHistoryEntry] {
        entries
            .filter { $0.documentId == documentId }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func deleteEntry(withId id: UUID) async {
        entries.removeAll { $0.id == id }
    }

    func clearHistory() async {
        entries.removeAll()
    }

    func getTotalRedactionCount() async -> Int {
        entries.count
    }
}
