//
//  FileRedactionRecordRepository.swift
//  StridApp
//
//  Hexagonal architecture role: **outbound adapter** implementing
//  `RedactionRecordRepositoryPort`.
//
//  On-disk layout (inside the app sandbox):
//
//      <Application Support>/Strid/Jobs/
//      ├── index.json                 ← [RedactionRecord] for every job
//      ├── <job-uuid>/
//      │   ├── original.<ext>         ← sandbox copy of the user's file
//      │   ├── redacted.<ext>         ← redacted output
//      │   ├── <vault file>           ← only for reversible jobs
//      │   └── restored.<ext>         ← written on demand by restore
//      └── <job-uuid>/ ...
//
//  The index is small (one entry per job) so it is rewritten in full on
//  every change; there is no incremental update. Application Support is
//  chosen over Documents so the files are not surfaced in the Files app and
//  are not shared with other apps, and over Caches so the OS never evicts
//  them.
//

import Foundation

/// Persists records as a JSON index under Application Support/Strid/Jobs, one folder per job.
///
/// An `actor` so concurrent saves/deletes from different tasks cannot
/// interleave their read-modify-write of `cache` and `index.json`.
actor FileRedactionRecordRepository: RedactionRecordRepositoryPort {
    /// In-memory mirror of `index.json`, newest first. `nil` until the first
    /// read; after that every write goes through this cache and is then
    /// flushed with `persist()`.
    private var cache: [RedactionRecord]?

    /// Shared file manager. Safe to hold inside the actor because all access
    /// is serialised.
    private let fm = FileManager.default

    /// `…/Application Support/Strid/Jobs`, created on first access.
    ///
    /// A throwing getter because locating Application Support can fail on
    /// exotic containers; callers propagate the error rather than crashing.
    private var root: URL {
        get throws {
            let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Strid/Jobs", isDirectory: true)
            if !fm.fileExists(atPath: base.path) {
                try fm.createDirectory(at: base, withIntermediateDirectories: true)
            }
            return base
        }
    }

    /// Location of the JSON index file.
    private var indexURL: URL { get throws { try root.appendingPathComponent("index.json") } }

    // MARK: - RedactionRecordRepositoryPort

    /// Returns all live records, newest first.
    ///
    /// On the first call the index is decoded from disk. A missing or
    /// corrupt index is treated as empty rather than as an error, so a bad
    /// file never locks the user out of the app. Records whose output file
    /// no longer exists are silently dropped from the cache (they will be
    /// removed from `index.json` on the next `persist()`).
    func all() async -> [RedactionRecord] {
        if let cache { return cache }
        let loaded: [RedactionRecord] = (try? Data(contentsOf: indexURL)).flatMap { try? JSONDecoder().decode([RedactionRecord].self, from: $0) } ?? []
        // Drop records whose files vanished (e.g. container moved).
        let alive = loaded.filter { fm.fileExists(atPath: $0.outputURL.path) }
        cache = alive.sorted { $0.createdAt > $1.createdAt }
        return cache!
    }

    /// Upserts `record` at the head of the list and rewrites the index.
    ///
    /// Any existing record with the same id is removed first, so renaming a
    /// job (mutating `name`) and saving again replaces it in place.
    func save(_ record: RedactionRecord) async throws {
        var list = await all().filter { $0.id != record.id }
        list.insert(record, at: 0)
        cache = list
        try persist()
    }

    /// Removes the record and its whole job folder, then rewrites the index.
    ///
    /// The folder removal is best-effort (`try?`): if the files are already
    /// gone the record should still disappear from the index.
    func delete(id: UUID) async throws {
        cache = await all().filter { $0.id != id }
        try? fm.removeItem(at: try root.appendingPathComponent(id.uuidString, isDirectory: true))
        try persist()
    }

    /// Returns `root/<id>/`, creating it if necessary. Called by the use
    /// case *before* a record exists so the redactor has somewhere to write.
    func jobDirectory(for id: UUID) async throws -> URL {
        let dir = try root.appendingPathComponent(id.uuidString, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        return dir
    }

    // MARK: - Private

    /// Serialises `cache` to `index.json`.
    ///
    /// `.atomic` writes to a temp file and renames, so a crash mid-write
    /// never leaves a truncated index. `.completeFileProtection` encrypts
    /// the file at rest while the device is locked; the index lists filenames
    /// and PII *counts* only, but the folders it points to hold originals.
    private func persist() throws {
        let data = try JSONEncoder().encode(cache ?? [])
        try data.write(to: indexURL, options: [.atomic, .completeFileProtection])
    }
}
