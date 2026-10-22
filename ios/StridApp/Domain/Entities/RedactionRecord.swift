//
//  RedactionRecord.swift
//  StridApp
//
//  Hexagonal architecture role: **domain entity**.
//
//  `RedactionRecord` is the persistent result of the *file* pipeline
//  (PDF / image / text / DOCX redaction via StridDocuments), as opposed to the
//  in-app plain-text flow modelled by `Document` / `RedactedDocument`.
//
//  Each record corresponds to one job folder on disk managed by
//  `RedactionRecordRepositoryPort`: the folder holds a sandbox copy of the
//  input, the redacted output and, for reversible jobs, an encrypted vault
//  that allows the original to be restored with a key.
//

import Foundation
import StridKit

/// A completed redaction job: the original (sandbox copy), the redacted output, and what was found.
///
/// The type is `Codable` because `FileRedactionRecordRepository` serialises
/// the whole list of records to a single JSON index file, and `Hashable` so
/// it can drive SwiftUI navigation and selection.
struct RedactionRecord: Identifiable, Equatable, Hashable {
    /// The broad input format of the job. Mirrors StridDocuments'
    /// `DocumentKind` but is owned by the app so the persisted JSON does not
    /// depend on library enum spellings.
    enum Kind: String, Codable, CaseIterable {
        /// A PDF, possibly password-protected or scanned (OCR fallback).
        case pdf
        /// A raster image (PNG/JPEG/etc.) redacted via OCR.
        case image
        /// A plain-text file.
        case text
        /// A Word `.docx` document.
        case docx
    }

    /// Identifier of the job. Also used as the name of its folder on disk.
    let id: UUID

    /// User-facing display name (typically the original filename). Mutable so
    /// the UI can let the user rename a job.
    var name: String

    /// Input format of the job.
    let kind: Kind

    /// Location of the sandbox copy of the original file inside the job
    /// folder. The original security-scoped URL is never stored.
    ///
    /// Held as an absolute URL in memory, but persisted as a filename only:
    /// the app container moves on every install and update, so an absolute
    /// path written today is wrong tomorrow (see `Codable` below).
    let inputURL: URL

    /// Location of the redacted output file inside the job folder.
    let outputURL: URL

    /// Location of the encrypted vault file for reversible redactions, or
    /// `nil` if the job was irreversible. Mutable so it can be cleared if the
    /// user discards the vault.
    var vaultURL: URL?

    /// Number of pages processed (1 for images and text).
    let pages: Int

    /// Entity type raw value -> count
    ///
    /// Keys are `PIIEntityType.rawValue` strings rather than the enum itself
    /// so that a record saved by an older build still decodes if a type is
    /// later renamed or removed; unknown keys are simply skipped by
    /// `sortedCounts`.
    let counts: [String: Int]

    /// Non-fatal issues reported by the redactor (e.g. low-confidence OCR
    /// pages) that the UI should surface to the user.
    let warnings: [String]

    /// When the job completed.
    let createdAt: Date

    /// Whether the job was run in reversible mode (a vault exists and the
    /// original can be restored with the key).
    let reversible: Bool

    // MARK: - Derived Values

    /// Total number of PII spans redacted across all types.
    var total: Int { counts.values.reduce(0, +) }

    /// `counts` as typed tuples, ordered by count descending and then by type
    /// name ascending for a stable display order. Entries whose raw value no
    /// longer maps to a `PIIEntityType` are dropped.
    var sortedCounts: [(type: PIIEntityType, count: Int)] {
        counts.compactMap { k, v in PIIEntityType(rawValue: k).map { ($0, v) } }
            .sorted { $0.count == $1.count ? $0.type.rawValue < $1.type.rawValue : $0.count > $1.count }
    }

    /// Short human-readable label for `kind`, used in list rows and badges.
    var kindLabel: String {
        switch kind {
        case .pdf: "PDF"
        case .image: "Image"
        case .text: "Text"
        case .docx: "Document"
        }
    }

    /// SF Symbol name representing `kind`.
    var symbol: String {
        switch kind {
        case .pdf: "doc.richtext"
        case .image: "photo"
        case .text: "text.alignleft"
        case .docx: "doc.text"
        }
    }
}

// MARK: - Persistence

/// Persisted with filenames, not paths. Every file of a job lives in
/// `<Jobs root>/<id>/`, so the index only needs the id and the last path
/// component; the root is supplied by the decoder through
/// `RedactionRecord.jobsRootKey` and the URLs are rebuilt on read.
///
/// Older indexes stored absolute `inputURL` / `outputURL` / `vaultURL`
/// values. Those are accepted too, keeping only their filename, which is how
/// records written before this change survive the container move that
/// otherwise lost them.
extension RedactionRecord: Codable {
    /// `JSONDecoder.userInfo` key whose value is the Jobs root `URL`.
    static let jobsRootKey = CodingUserInfoKey(rawValue: "strid.jobsRoot")!

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, pages, counts, warnings, createdAt, reversible
        case inputFile, outputFile, vaultFile
        // Legacy absolute URLs.
        case inputURL, outputURL, vaultURL
    }

    /// The folder every file of `id` lives in, under `root`.
    static func folder(for id: UUID, in root: URL) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        guard let root = decoder.userInfo[Self.jobsRootKey] as? URL else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "RedactionRecord needs the Jobs root in userInfo"))
        }
        let folder = Self.folder(for: id, in: root)
        func file(_ new: CodingKeys, legacy: CodingKeys) throws -> String? {
            if let name = try c.decodeIfPresent(String.self, forKey: new) { return name }
            return try c.decodeIfPresent(URL.self, forKey: legacy)?.lastPathComponent
        }
        guard let input = try file(.inputFile, legacy: .inputURL), let output = try file(.outputFile, legacy: .outputURL) else {
            throw DecodingError.keyNotFound(CodingKeys.outputFile, .init(codingPath: decoder.codingPath, debugDescription: "record has no files"))
        }
        self.id = id
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(Kind.self, forKey: .kind)
        inputURL = folder.appendingPathComponent(input)
        outputURL = folder.appendingPathComponent(output)
        vaultURL = try file(.vaultFile, legacy: .vaultURL).map { folder.appendingPathComponent($0) }
        pages = try c.decode(Int.self, forKey: .pages)
        counts = try c.decode([String: Int].self, forKey: .counts)
        warnings = try c.decode([String].self, forKey: .warnings)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        reversible = try c.decode(Bool.self, forKey: .reversible)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(inputURL.lastPathComponent, forKey: .inputFile)
        try c.encode(outputURL.lastPathComponent, forKey: .outputFile)
        try c.encodeIfPresent(vaultURL?.lastPathComponent, forKey: .vaultFile)
        try c.encode(pages, forKey: .pages)
        try c.encode(counts, forKey: .counts)
        try c.encode(warnings, forKey: .warnings)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(reversible, forKey: .reversible)
    }
}
