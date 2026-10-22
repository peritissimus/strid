//
//  RedactFileUseCase.swift
//  StridApp
//
//  Hexagonal architecture role: **use case** (application service) for the
//  file pipeline.
//
//  This is the heart of the "pick a file, get a redacted copy" experience.
//  It orchestrates:
//
//    1. Working out whether the file type is supported (`DocumentKind`).
//    2. Copying the user's file into an app-owned job folder.
//    3. Running StridDocuments' `DocumentRedactor` off the main actor.
//    4. Translating library errors into user-facing `RedactFileError`s.
//    5. Summarising the result into a persisted `RedactionRecord`.
//
//  The same class also implements `RestoreFileUseCase`, which reverses a
//  redaction using the encrypted vault written during a reversible job.
//
//  Unlike the plain-text use cases this one imports StridDocuments/StridKit
//  directly: the document redactor *is* the domain operation here, and
//  wrapping it behind another port would add indirection without a second
//  implementation to justify it.
//

import Foundation
import StridDocuments
import StridKit

// MARK: - Errors

/// User-presentable failures of the file pipeline.
///
/// Every case carries a ready-to-display `errorDescription`, so view models
/// can show `error.localizedDescription` without further mapping.
enum RedactFileError: LocalizedError {
    /// The file extension is not one StridDocuments can read. Payload is the
    /// extension without the leading dot.
    case unsupported(String)
    /// The PDF is encrypted and no password was supplied.
    case passwordRequired
    /// A password was supplied but did not open the PDF.
    case wrongPassword
    /// Any other failure; payload is a human-readable message.
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let ext): "Strid can't read .\(ext) files yet."
        case .passwordRequired: "This PDF is password protected."
        case .wrongPassword: "That password didn't open the PDF."
        case .failed(let m): m
        }
    }
}

// MARK: - Request

/// Everything needed to start a redaction job. Built by the UI from the file
/// picker result and the options sheet.
struct RedactRequest {
    /// The file the user picked. May be a security-scoped URL that becomes
    /// invalid once the picker's access ends, which is why the use case
    /// copies it immediately.
    var sourceURL: URL

    /// Name to show for the job (usually `sourceURL.lastPathComponent`).
    var displayName: String

    /// Password for encrypted PDFs; `nil` to attempt opening without one.
    var password: String?

    /// If `true`, the redactor also writes an encrypted vault so the original
    /// can later be restored with `vaultKey`.
    var reversible: Bool

    /// Key used to encrypt the vault. Only consulted when `reversible` is
    /// `true`.
    var vaultKey: String?

    /// Which findings to redact: the profile's rules, narrowed by review.
    var policy: RedactionPolicy = .default
}

// MARK: - Use Case Protocols

/// Runs a file-redaction job end to end.
protocol RedactFileUseCase: Sendable {
    /// Redacts the file described by `request`.
    ///
    /// - Parameters:
    ///   - request: Source file and options.
    ///   - progress: Called with short stage labels ("Reading", "Redacting",
    ///     "Saving") as the job advances. May be invoked off the main actor.
    /// - Returns: The persisted record describing the finished job.
    /// - Throws: `RedactFileError` for every failure mode.
    func execute(_ request: RedactRequest, progress: @Sendable @escaping (String) -> Void) async throws -> RedactionRecord
}

/// Reverses a reversible redaction job.
protocol RestoreFileUseCase: Sendable {
    /// Restores the original content of `record` using its vault.
    ///
    /// - Parameters:
    ///   - record: A job with a non-nil `vaultURL`.
    ///   - key: The vault key that was used when the job was created.
    /// - Returns: URL of the restored file inside the job folder.
    /// - Throws: `RedactFileError.failed` if the job was not reversible, the
    ///   key is wrong, or the vault is corrupt.
    func execute(record: RedactionRecord, key: String) async throws -> URL
}

// MARK: - Implementation

/// Production implementation of both `RedactFileUseCase` and
/// `RestoreFileUseCase`, backed by StridDocuments.
final class RedactFileUseCaseImpl: RedactFileUseCase, RestoreFileUseCase {
    /// Owns the job folders and the record index.
    private let repository: RedactionRecordRepositoryPort

    /// The StridKit detection engine shared across jobs. Constructing an
    /// engine loads recognizer tables, so it is created once per use case
    /// rather than once per job.
    let engine: StridEngine

    /// - Parameters:
    ///   - repository: Injected by `DIContainer`.
    ///   - engine: Detection engine; defaults to a fresh `StridEngine`. Tests
    ///     can pass a configured instance.
    init(repository: RedactionRecordRepositoryPort, engine: StridEngine = StridEngine()) {
        self.repository = repository
        self.engine = engine
    }

    func execute(_ request: RedactRequest, progress: @Sendable @escaping (String) -> Void) async throws -> RedactionRecord {
        // 1. Reject unsupported formats before touching the file system.
        guard let docKind = DocumentKind.detect(url: request.sourceURL) else {
            throw RedactFileError.unsupported(request.sourceURL.pathExtension)
        }
        let id = UUID()
        let dir = try await repository.jobDirectory(for: id)

        progress("Reading")
        // Copy into the sandbox so the job survives the security-scoped URL going away.
        // Files with no extension are treated as plain text.
        let ext = request.sourceURL.pathExtension.isEmpty ? "txt" : request.sourceURL.pathExtension
        let input = dir.appendingPathComponent("original").appendingPathExtension(ext)
        let output = dir.appendingPathComponent("redacted").appendingPathExtension(ext)
        // copyItem fails if the destination exists, so clear any stale copy.
        try? FileManager.default.removeItem(at: input)
        try FileManager.default.copyItem(at: request.sourceURL, to: input)

        progress("Redacting")
        // keepEncryption is false so the redacted PDF opens without a
        // password; ocrFallback lets scanned PDFs/images still be processed.
        // The vault key is only forwarded when the user asked for a
        // reversible job, so an irreversible job never writes a vault.
        let options = DocumentOptions(password: request.password, keepEncryption: false, ocrFallback: true,
                                      vaultKey: request.reversible ? request.vaultKey : nil, policy: request.policy)
        let engine = self.engine
        let result: (url: URL, report: RedactionReport)
        do {
            // Redaction is CPU-bound (and may run OCR), so it runs on a
            // detached task to keep the UI responsive.
            result = try await Task.detached(priority: .userInitiated) {
                try DocumentRedactor.redact(input: input, output: output, engine: engine, style: .placeholder, options: options)
            }.value
        } catch DocumentRedactionError.passwordRequired {
            // On any failure the half-populated job folder is removed so no
            // orphaned copy of the user's original lingers on disk.
            try? FileManager.default.removeItem(at: dir)
            throw RedactFileError.passwordRequired
        } catch DocumentRedactionError.wrongPassword {
            try? FileManager.default.removeItem(at: dir)
            throw RedactFileError.wrongPassword
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw RedactFileError.failed(error.localizedDescription)
        }

        progress("Saving")
        // Map the library's DocumentKind onto the app-owned Kind enum.
        let kind: RedactionRecord.Kind = switch docKind {
        case .pdf: .pdf
        case .image: .image
        case .text: .text
        case .docx: .docx
        }
        // Flatten the typed count dictionary to raw-value keys for JSON.
        var counts: [String: Int] = [:]
        for (t, c) in result.report.countsByType { counts[t.rawValue] = c }
        let record = RedactionRecord(
            id: id, name: request.displayName, kind: kind, inputURL: input, outputURL: result.url,
            vaultURL: result.report.vaultURL, pages: result.report.pages, counts: counts,
            warnings: result.report.warnings, createdAt: Date(), reversible: request.reversible)
        try await repository.save(record)
        return record
    }

    func execute(record: RedactionRecord, key: String) async throws -> URL {
        guard let vault = record.vaultURL else { throw RedactFileError.failed("This redaction was not reversible.") }
        // The restored file sits next to the redacted output, in the job
        // folder, with the same extension.
        let out = record.outputURL.deletingLastPathComponent()
            .appendingPathComponent("restored").appendingPathExtension(record.outputURL.pathExtension)
        do {
            return try await Task.detached {
                try DocumentRedactor.restore(redacted: record.outputURL, vault: vault, key: key, output: out)
            }.value
        } catch {
            // Decryption failures are indistinguishable from corruption at
            // this level, so one message covers both.
            throw RedactFileError.failed("Wrong key, or the vault is damaged.")
        }
    }
}
