import Foundation
import Testing
@testable import StridKit

@Suite("Reversible redaction")
struct VaultTests {
    @Test func tokensAreStablePerValue() {
        let text = "Rahul Sharma paid Rahul Sharma; PAN ABCDE1234F"
        let e = StridEngine().detect(in: text)
        var map = TokenMap()
        let out = Redactor.tokenize(text, entities: e, map: &map)
        #expect(out.contains("[PERSON_1]"))
        #expect(!out.contains("[PERSON_2]"))
        #expect(out.contains("[IN_PAN_1]"))
        #expect(map.restore(out) == text)
    }

    @Test func vaultRoundTrip() throws {
        var map = TokenMap()
        _ = map.token(type: .person, value: "Rahul Sharma")
        let v = Vault(sourceName: "a.txt", format: "txt", tokens: map, original: Data("hello".utf8))
        let sealed = try v.sealed(passphrase: "correct horse")
        let back = try Vault.open(sealed, passphrase: "correct horse")
        #expect(back.tokens == map)
        #expect(back.original == Data("hello".utf8))
        #expect(throws: Vault.VaultError.self) { try Vault.open(sealed, passphrase: "wrong") }
        #expect(throws: Vault.VaultError.self) { try Vault.open(Data("nope".utf8), passphrase: "x") }
    }
}
