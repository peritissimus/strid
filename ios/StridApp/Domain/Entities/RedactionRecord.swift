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
struct RedactionRecord: Identifiable, Codable, Equatable, Hashable {
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
