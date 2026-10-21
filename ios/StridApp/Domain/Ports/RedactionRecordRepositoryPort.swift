//
//  RedactionRecordRepositoryPort.swift
//  StridApp
//
//  Hexagonal architecture role: **outbound port** (driven-side interface).
//
//  Persistence contract for the *file* pipeline's `RedactionRecord`s. Unlike
//  the other repository ports, this one also owns the on-disk working
//  directory for each job, because the redactor needs a sandbox location to
//  write to before a record even exists. Implemented by
//  `FileRedactionRecordRepository`.
//
//  `Sendable` is required because `RedactFileUseCaseImpl` is itself
//  `Sendable` and hands work to detached tasks.
//

import Foundation

/// Storage for file-redaction jobs and their working directories.
protocol RedactionRecordRepositoryPort: Sendable {
    /// All known records, newest first. Adapters may prune records whose
    /// files no longer exist.
    func all() async -> [RedactionRecord]

    /// Inserts or replaces a record (matched by `id`).
    ///
    /// - Parameter record: The job to persist.
    /// - Throws: If the index cannot be written.
    func save(_ record: RedactionRecord) async throws

    /// Removes a record and its job folder (input, output and vault files).
    ///
    /// - Parameter id: The `RedactionRecord.id` to remove.
    /// - Throws: If the index cannot be rewritten.
    func delete(id: UUID) async throws

    /// Directory for a job's files. Created on demand.
    ///
    /// - Parameter id: The job identifier; used as the folder name.
    /// - Returns: An existing, writable directory URL.
    /// - Throws: If the directory cannot be created.
    func jobDirectory(for id: UUID) async throws -> URL
}
