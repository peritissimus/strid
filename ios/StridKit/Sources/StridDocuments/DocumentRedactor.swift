import Foundation
import StridKit
import UniformTypeIdentifiers

/// Formats the document layer can redact while preserving the container format.
public enum DocumentKind: String, Sendable, CaseIterable {
    case text, image, pdf, docx

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
    public var reversible: Bool { vaultKey != nil }

    public init(password: String? = nil, keepEncryption: Bool = false, ocrFallback: Bool = true, vaultKey: String? = nil) {
        self.password = password
        self.keepEncryption = keepEncryption
        self.ocrFallback = ocrFallback
        self.vaultKey = vaultKey
    }
}

/// Summary of what was redacted in a document.
public struct RedactionReport: Sendable {
    public var pages: Int
    public var entities: [PIIEntity]
    /// Non-fatal notes the user should see (signature removed, OCR fallback used, ...).
    public var warnings: [String]
    /// Token map when running in reversible mode.
    public var tokens: TokenMap?
    /// Where the encrypted vault was written, if any.
    public var vaultURL: URL?
    public var countsByType: [PIIEntityType: Int] {
        entities.reduce(into: [:]) { $0[$1.type, default: 0] += 1 }
    }
    public init(pages: Int = 1, entities: [PIIEntity] = [], warnings: [String] = []) {
        self.pages = pages
        self.entities = entities
        self.warnings = warnings
    }
}

public enum DocumentRedactionError: Error, LocalizedError {
    case unsupportedFormat(String)
    case unreadable(URL)
    case writeFailed(URL)
    case passwordRequired(URL)
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
    func redact(input: URL, output: URL, engine: StridEngine, style: RedactionStyle, options: DocumentOptions) throws -> RedactionReport
}

/// Entry point: PDF in, PDF out; image in, image out; text in, text out.
public enum DocumentRedactor {
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

    public static func defaultOutputURL(for input: URL) -> URL {
        let base = input.deletingPathExtension().lastPathComponent + "_redacted"
        return input.deletingLastPathComponent()
            .appendingPathComponent(base)
            .appendingPathExtension(input.pathExtension)
    }
}
