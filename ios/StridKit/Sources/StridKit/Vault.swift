//
// Vault.swift
// StridKit
//
// The encrypted sidecar that makes a reversible redaction actually reversible.
//
// When a document is redacted with a vault key, the pipeline writes `<output>.strid` next to the
// redacted output. The sidecar holds the `TokenMap` (token -> original value) and, for formats
// that are rasterised during redaction (PDF, images), the complete original file bytes, since
// black boxes cannot be undone from tokens alone. The whole payload is JSON, encrypted with
// AES-256-GCM under a key derived from the user's passphrase. Without the passphrase the sidecar
// reveals nothing about the document beyond its size.
//
import CryptoKit
import Foundation

/// Encrypted sidecar that makes a redaction reversible for whoever holds the key.
///
/// File layout (binary): magic "STRIDV1\n" | 16-byte salt | AES-GCM combined (nonce|ciphertext|tag) of JSON payload.
/// Key = HKDF-SHA256(passphrase, salt, info "strid-vault"). Nothing about the document is stored in clear.
///
/// Design notes:
///   - A fresh random salt per vault means the same passphrase yields a different key for every
///     file, so two vaults cannot be correlated and precomputed tables are useless.
///   - AES-GCM is authenticated: a wrong passphrase or a single flipped byte fails the tag check
///     and surfaces as `VaultError.badKey` rather than as garbage JSON.
///   - HKDF is a key *expansion* function, not a slow password hash. The passphrases produced by
///     `generatePassphrase` carry ~190 bits of entropy so stretching is unnecessary; user-chosen
///     short passphrases are correspondingly weaker.
public struct Vault: Codable, Sendable {
    /// Payload schema version, independent of the on-disk `magic` version.
    public var version: Int = 1
    /// When the vault was sealed.
    public var created: Date = Date()
    /// Original file name, for restore naming.
    public var sourceName: String
    /// Container format of the redacted output ("pdf", "png", "txt", ...).
    public var format: String
    /// Token -> original value map used to reverse text-based redactions.
    public var tokens: TokenMap
    /// Full original bytes. Present for rasterised formats (PDF, images) where tokens alone cannot restore.
    public var original: Data?

    /// - Parameters:
    ///   - sourceName: Name of the input file, used to name the restored output.
    ///   - format: Lower-cased file extension of the redacted output.
    ///   - tokens: Token map from the redaction run (may be empty for rasterised formats).
    ///   - original: Original file bytes when the format cannot be restored from tokens.
    public init(sourceName: String, format: String, tokens: TokenMap, original: Data? = nil) {
        self.sourceName = sourceName
        self.format = format
        self.tokens = tokens
        self.original = original
    }

    /// File signature. The trailing newline makes `head -c 8` output readable and guards
    /// against the magic being a prefix of some other format's header.
    static let magic = Data("STRIDV1\n".utf8)

    /// Failures when opening a vault. Deliberately coarse: a wrong key and a corrupted file are
    /// indistinguishable by design of authenticated encryption, and we do not want to leak more.
    public enum VaultError: Error, LocalizedError {
        /// `notAVault`: missing or mismatched magic header, or the file is too short to contain a salt.
        /// `badKey`: AES-GCM authentication failed, or the decrypted payload was not a valid vault.
        case notAVault, badKey
        public var errorDescription: String? {
            switch self {
            case .notAVault: "File is not a Strid vault."
            case .badKey: "Wrong key, or the vault is corrupted."
            }
        }
    }

    // MARK: - Key derivation

    /// Derives the 256-bit AES key for a vault from its passphrase and per-file salt.
    ///
    /// Domain-separated with the fixed info string `"strid-vault"` so that the same passphrase
    /// and salt could never produce a key usable in some other context of the app.
    ///
    /// - Parameters:
    ///   - passphrase: User-supplied or generated passphrase, used as HKDF input key material.
    ///   - salt: The 16 random bytes stored in the vault header.
    public static func key(from passphrase: String, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(passphrase.utf8)),
            salt: salt, info: Data("strid-vault".utf8), outputByteCount: 32)
    }

    /// Generates a random passphrase suitable for printing to the user.
    ///
    /// 24 bytes (192 bits) from the system CSPRNG, base64url-encoded without padding, giving a
    /// 32-character string that is safe to paste into a shell argument or a URL.
    public static func generatePassphrase() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        // Standard base64 -> base64url: '+' -> '-', '/' -> '_', strip '=' padding.
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Seal / open

    /// Encrypts this vault for writing to disk.
    ///
    /// - Parameter passphrase: Key material; the caller must retain it, nothing is stored.
    /// - Returns: `magic + salt + AES-GCM combined box`, ready to write as the `.strid` sidecar.
    /// - Throws: JSON encoding errors, CryptoKit errors, or `VaultError.badKey` in the (practically
    ///   impossible) case that the sealed box has no combined representation.
    public func sealed(passphrase: String) throws -> Data {
        var salt = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt)
        let saltData = Data(salt)
        let payload = try JSONEncoder().encode(self)
        // `seal` picks a fresh random 12-byte nonce; `combined` = nonce | ciphertext | 16-byte tag.
        let box = try AES.GCM.seal(payload, using: Self.key(from: passphrase, salt: saltData))
        guard let combined = box.combined else { throw VaultError.badKey }
        return Self.magic + saltData + combined
    }

    /// Decrypts and decodes a vault previously produced by `sealed(passphrase:)`.
    ///
    /// - Parameters:
    ///   - data: Full contents of the `.strid` file.
    ///   - passphrase: The passphrase used when sealing.
    /// - Returns: The decoded vault.
    /// - Throws: `VaultError.notAVault` if the header is wrong; `VaultError.badKey` for any
    ///   decryption or decoding failure (wrong passphrase, truncated or tampered file).
    public static func open(_ data: Data, passphrase: String) throws -> Vault {
        // Need at least magic + salt; the body length is checked by SealedBox(combined:).
        guard data.count > magic.count + 16, data.prefix(magic.count) == magic else { throw VaultError.notAVault }
        let salt = data.subdata(in: magic.count..<(magic.count + 16))
        let body = data.subdata(in: (magic.count + 16)..<data.count)
        do {
            let box = try AES.GCM.SealedBox(combined: body)
            let plain = try AES.GCM.open(box, using: key(from: passphrase, salt: salt))
            return try JSONDecoder().decode(Vault.self, from: plain)
        } catch {
            // Collapse every failure mode into one error so callers cannot distinguish
            // "wrong key" from "corrupt file" (and neither can an attacker).
            throw VaultError.badKey
        }
    }

    /// Conventional sidecar location: `<output>.strid`
    ///
    /// Appending (rather than replacing) the extension keeps `statement_redacted.pdf.strid`
    /// visibly paired with `statement_redacted.pdf` in a directory listing.
    public static func sidecarURL(for output: URL) -> URL {
        output.appendingPathExtension("strid")
    }
}
