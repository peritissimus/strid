import Foundation

protocol DocumentRepositoryPort {
    func save(document: Document) async throws
    func load(id: UUID) async throws -> Document?
    func loadCurrent() async -> Document?
    func saveCurrent(_ document: Document) async
    func clearCurrent() async
}
