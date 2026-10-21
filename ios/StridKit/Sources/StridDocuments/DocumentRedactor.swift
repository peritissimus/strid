//
// DocumentRedactor.swift
// StridDocuments
//
// Public facade of the document layer and home of its shared types:
//
//   - `DocumentKind`            which handler a file maps to, decided from its extension's UTType
//   - `DocumentOptions`         per-run knobs (PDF password, OCR fallback, reversible vault key)
//   - `RedactionReport`         what a handler reports back (pages, entities, warnings, tokens)
//   - `DocumentRedactionError`  user-facing failure cases
//   - `DocumentHandler`         protocol every format handler implements
//   - `DocumentRedactor`        dispatch + vault writing (`redact`) and vault reading (`restore`)
//
// Reversible flow in one picture:
//
//   redact(input, vaultKey) -> handler writes <out> with [TYPE_n] tokens or labelled boxes
//                           -> Vault{tokens, original bytes if raster} sealed to <out>.strid
//   restore(<out>, key)     -> open vault -> original bytes? write them : untokenise <out>
//
import Foundation
import StridKit
import UniformTypeIdentifiers

/// Formats the document layer can redact while preserving the container format.
public enum DocumentKind: String, Sendable, CaseIterable {
    /// - `text`:  UTF-8 text of any flavour (txt, csv, md, json, log, ...).
    /// - `image`: raster image (png, jpg, heic, tiff, ...).
    /// - `pdf`:   PDF, with or without a text layer.
    /// - `docx`:  word-processing document handled as an attributed string: `.docx` and `.rtf`.
    case text, image, pdf, docx

    /// Classifies a file by its extension's Uniform Type.
    ///
    /// Checks are ordered most-specific first: PDF and images before the generic `.text`
    /// conformance (an SVG, for example, conforms to both image and text and should be an image).
    /// RTF is folded into `.docx` because both go through `AttributedDocumentHandler`.
    ///
    /// - Parameter url: File whose `pathExtension` is inspected; contents are not read.
    /// - Returns: The kind, or `nil` for unknown or unsupported extensions.
    public static func detect(url: URL) -> DocumentKind? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.identifier == "org.openxmlformats.wordprocessingml.document"
            || type.conforms(to: .rtf) { return .docx }
        if type.conforms(to: .text) || type.conforms(to: .plainText) { return .text }
        return nil
    }
}

/// Per-document options.
public struct DocumentOptions: Sendable {
    /// Password for encrypted PDFs.
    public var password: String?
    /// Re-apply the same password to the output PDF. Off by default: the usual reason to redact is to share.
    public var keepEncryption: Bool = false
    /// Pages whose text layer looks like garbage are re-OCRed instead (default true).
    public var ocrFallback: Bool = true
    /// Reversible mode: stable tokens instead of placeholders, token labels on boxes, and an encrypted
    /// vault sidecar (`<output>.strid`) sealed with `vaultKey`.
    public var vaultKey: String?
    /// `true` when a vault key is present; handlers branch on this rather than on the key itself.
    public var reversible: Bool { vaultKey != nil }

    /// - Parameters:
    ///   - password: PDF user password, if the input is locked.
    ///   - keepEncryption: Re-encrypt the output PDF with the same password.
    ///   - ocrFallback: Allow OCR for pages with unusable text layers.
    ///   - vaultKey: Passphrase for the vault; non-nil turns on reversible mode.
    public init(password: String? = nil, keepEncryption: Bool = false, ocrFallback: Bool = true, vaultKey: String? = nil) {
        self.password = password
        self.keepEncryption = keepEncryption
        self.ocrFallback = ocrFallback
        self.vaultKey = vaultKey
    }
}

/// Summary of what was redacted in a document.
public struct RedactionReport: Sendable {
    /// Number of pages processed (1 for non-paginated formats).
    public var pages: Int
    /// Every entity that was redacted, across all pages.
    public var entities: [PIIEntity]
    /// Non-fatal notes the user should see (signature removed, OCR fallback used, ...).
    public var warnings: [String]
    /// Token map when running in reversible mode.
    public var tokens: TokenMap?
    /// Where the encrypted vault was written, if any.
    public var vaultURL: URL?
    /// Entity count per type, for summary tables.
    public var countsByType: [PIIEntityType: Int] {
        entities.reduce(into: [:]) { $0[$1.type, default: 0] += 1 }
    }
    public init(pages: Int = 1, entities: [PIIEntity] = [], warnings: [String] = []) {
        self.pages = pages
        self.entities = entities
        self.warnings = warnings
    }
}

/// Failures surfaced to the user by the document layer. Each carries enough to name the file.
public enum DocumentRedactionError: Error, LocalizedError {
    /// Extension not mapped to any handler (or DOCX on iOS).
    case unsupportedFormat(String)
    /// The handler could not parse the file (also used for a vault that lacks original bytes).
    case unreadable(URL)
    /// Output encoding or file creation failed.
    case writeFailed(URL)
    /// PDF is locked and no password was supplied.
    case passwordRequired(URL)
    /// PDF is locked and the supplied password did not unlock it.
    case wrongPassword(URL)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): "Unsupported document format: .\(ext)"
        case .unreadable(let url): "Could not read \(url.lastPathComponent)"
        case .writeFailed(let url): "Could not write \(url.lastPathComponent)"
        case .passwordRequired(let url): "\(url.lastPathComponent) is password protected. Supply the password to open it."
        case .wrongPassword(let url): "Wrong password for \(url.lastPathComponent)."
        }
    }
}

/// A format handler: reads a document, redacts PII in place, writes the same format back.
public protocol DocumentHandler: Sendable {
    /// Redacts `input` into `output`.
    ///
    /// - Parameters:
    ///   - input: Source file.
    ///   - output: Destination file; handlers overwrite it.
    ///   - engine: Detection engine to run on the extracted text.
    ///   - style: Replacement style for text-based outputs; raster handlers ignore it.
    ///   - options: Password, OCR and reversible settings.
    /// - Returns: A report; in reversible mode `tokens` must be populated so the vault can be built.
    func redact(input: URL, output: URL, engine: StridEngine, style: RedactionStyle, options: DocumentOptions) throws -> RedactionReport
}

/// Entry point: PDF in, PDF out; image in, image out; text in, text out.
public enum DocumentRedactor {
    /// Handler for a kind. Handlers are stateless value types, so a fresh one per call is free.
    public static func handler(for kind: DocumentKind) -> DocumentHandler {
        switch kind {
        case .text: TextDocumentHandler()
        case .image: ImageDocumentHandler()
        case .pdf: PDFDocumentHandler()
        case .docx: AttributedDocumentHandler()
        }
    }

    /// Redacts `input` and writes the result to `output` in the same format.
    /// If `output` is nil, writes next to the input as `<name>_redacted.<ext>`.
    ///
    /// When `options.vaultKey` is set, additionally seals a `Vault` to `Vault.sidecarURL(for: out)`
    /// and records that location in `report.vaultURL`. For PDF and image inputs the vault embeds
    /// the complete original file, since boxes cannot be lifted; for text and DOCX the token map
    /// alone suffices. The sidecar is written with `.completeFileProtection` so on iOS it is only
    /// readable while the device is unlocked.
    ///
    /// - Parameters:
    ///   - input: Source document.
    ///   - output: Destination, or `nil` for the default sibling path.
    ///   - engine: Detection engine; a default-configured one if omitted.
    ///   - style: Replacement style for text outputs.
    ///   - options: Per-run options.
    /// - Returns: The output URL actually written and the handler's report.
    /// - Throws: `DocumentRedactionError.unsupportedFormat` for unknown extensions, plus anything
    ///   the handler, vault sealing or file writes throw.
    @discardableResult
    public static func redact(
        input: URL,
        output: URL? = nil,
        engine: StridEngine = StridEngine(),
        style: RedactionStyle = .placeholder,
        options: DocumentOptions = DocumentOptions()
    ) throws -> (url: URL, report: RedactionReport) {
        guard let kind = DocumentKind.detect(url: input) else {
            throw DocumentRedactionError.unsupportedFormat(input.pathExtension)
        }
        let out = output ?? defaultOutputURL(for: input)
        var report = try handler(for: kind).redact(input: input, output: out, engine: engine, style: style, options: options)

        if let key = options.vaultKey {
            // Rasterised formats cannot be reversed from tokens alone: keep the original bytes too.
            let needsOriginal = kind == .pdf || kind == .image
            let vault = Vault(
                sourceName: input.lastPathComponent,
                format: input.pathExtension.lowercased(),
                tokens: report.tokens ?? TokenMap(),
                original: needsOriginal ? try Data(contentsOf: input) : nil)
            let vaultURL = Vault.sidecarURL(for: out)
            try vault.sealed(passphrase: key).write(to: vaultURL, options: [.atomic, .completeFileProtection])
            report.vaultURL = vaultURL
        }
        return (out, report)
    }

    /// Reverses a redaction using its vault. Returns the restored file URL.
    ///
    /// Resolution order:
    ///   1. Open the vault (default location `<redacted>.strid`) with `key`.
    ///   2. Choose the output name: `<original stem>_restored.<original ext>` next to the redacted file.
    ///   3. If the vault holds original bytes (PDF/image), write them verbatim and finish.
    ///   4. Otherwise untokenise: plain text via `TokenMap.restore`, DOCX/RTF via
    ///      `AttributedDocumentHandler.rewrite`. A PDF/image vault *without* original bytes
    ///      cannot be restored and reports the vault as unreadable.
    ///
    /// - Parameters:
    ///   - redacted: The redacted output file.
    ///   - vaultURL: Explicit vault path; defaults to the conventional sidecar.
    ///   - key: Vault passphrase.
    ///   - output: Explicit destination; defaults as described above.
    /// - Returns: The URL of the restored file.
    /// - Throws: `Vault.VaultError` for a bad key or non-vault file; `DocumentRedactionError` for
    ///   unsupported or non-restorable kinds; file I/O errors.
    @discardableResult
    public static func restore(redacted: URL, vault vaultURL: URL? = nil, key: String, output: URL? = nil) throws -> URL {
        let vurl = vaultURL ?? Vault.sidecarURL(for: redacted)
        let vault = try Vault.open(try Data(contentsOf: vurl), passphrase: key)
        let out = output ?? redacted.deletingLastPathComponent()
            .appendingPathComponent(URL(fileURLWithPath: vault.sourceName).deletingPathExtension().lastPathComponent + "_restored")
            .appendingPathExtension(vault.format)

        if let original = vault.original {
            try original.write(to: out, options: .atomic)
            return out
        }
        guard let kind = DocumentKind.detect(url: redacted) else {
            throw DocumentRedactionError.unsupportedFormat(redacted.pathExtension)
        }
        switch kind {
        case .text:
            let text = try String(contentsOf: redacted, encoding: .utf8)
            try vault.tokens.restore(text).write(to: out, atomically: true, encoding: .utf8)
        case .docx:
            try AttributedDocumentHandler.rewrite(redacted, to: out) { vault.tokens.restore($0) }
        case .pdf, .image:
            throw DocumentRedactionError.unreadable(vurl) // vault without original bytes
        }
        return out
    }

    /// `<dir>/<stem>_redacted.<ext>` for a given input.
    public static func defaultOutputURL(for input: URL) -> URL {
        let base = input.deletingPathExtension().lastPathComponent + "_redacted"
        return input.deletingLastPathComponent()
            .appendingPathComponent(base)
            .appendingPathExtension(input.pathExtension)
    }
}
