import CryptoKit
import Foundation

/// Encrypted sidecar that makes a redaction reversible for whoever holds the key.
///
/// File layout (binary): magic "STRIDV1\n" | 16-byte salt | AES-GCM combined (nonce|ciphertext|tag) of JSON payload.
/// Key = HKDF-SHA256(passphrase, salt, info "strid-vault"). Nothing about the document is stored in clear.
public struct Vault: Codable, Sendable {
    public var version: Int = 1
    public var created: Date = Date()
    /// Original file name, for restore naming.
    public var sourceName: String
    /// Container format of the redacted output ("pdf", "png", "txt", ...).
    public var format: String
    public var tokens: TokenMap
    /// Full original bytes. Present for rasterised formats (PDF, images) where tokens alone cannot restore.
    public var original: Data?

    public init(sourceName: String, format: String, tokens: TokenMap, original: Data? = nil) {
        self.sourceName = sourceName
        self.format = format
        self.tokens = tokens
        self.original = original
    }

    static let magic = Data("STRIDV1\n".utf8)

    public enum VaultError: Error, LocalizedError {
        case notAVault, badKey
        public var errorDescription: String? {
            switch self {
            case .notAVault: "File is not a Strid vault."
            case .badKey: "Wrong key, or the vault is corrupted."
            }
        }
    }

    public static func key(from passphrase: String, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(passphrase.utf8)),
            salt: salt, info: Data("strid-vault".utf8), outputByteCount: 32)
    }

    /// Generates a random passphrase suitable for printing to the user.
    public static func generatePassphrase() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public func sealed(passphrase: String) throws -> Data {
        var salt = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt)
        let saltData = Data(salt)
        let payload = try JSONEncoder().encode(self)
        let box = try AES.GCM.seal(payload, using: Self.key(from: passphrase, salt: saltData))
        guard let combined = box.combined else { throw VaultError.badKey }
        return Self.magic + saltData + combined
    }

    public static func open(_ data: Data, passphrase: String) throws -> Vault {
        guard data.count > magic.count + 16, data.prefix(magic.count) == magic else { throw VaultError.notAVault }
        let salt = data.subdata(in: magic.count..<(magic.count + 16))
        let body = data.subdata(in: (magic.count + 16)..<data.count)
        do {
            let box = try AES.GCM.SealedBox(combined: body)
            let plain = try AES.GCM.open(box, using: key(from: passphrase, salt: salt))
            return try JSONDecoder().decode(Vault.self, from: plain)
        } catch {
            throw VaultError.badKey
        }
    }

    /// Conventional sidecar location: `<output>.strid`
    public static func sidecarURL(for output: URL) -> URL {
        output.appendingPathExtension("strid")
    }
}
