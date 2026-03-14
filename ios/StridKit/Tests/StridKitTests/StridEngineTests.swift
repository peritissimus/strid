import Testing
@testable import StridKit

@Test func detectsPAN() async throws {
    let engine = StridEngine(threshold: 0.3)
    let text = "My PAN is ABCDE1234F"
    let entities = engine.detect(in: text)
    #expect(entities.contains { $0.type == .inPAN })
}

@Test func detectsEmail() async throws {
    let engine = StridEngine()
    let text = "Contact us at test@example.com for details"
    let entities = engine.detect(in: text)
    #expect(entities.contains { $0.type == .email })
}

@Test func redactsPlaceholder() async throws {
    let engine = StridEngine(threshold: 0.3)
    let text = "PAN: ABCDE1234F"
    let redacted = engine.redact(text, style: .placeholder)
    #expect(redacted.contains("<IN_PAN>"))
    #expect(!redacted.contains("ABCDE1234F"))
}

@Test func redactsAsterisks() async throws {
    let engine = StridEngine(threshold: 0.3)
    let text = "PAN: ABCDE1234F"
    let redacted = engine.redact(text, style: .asterisks)
    #expect(redacted.contains("**********"))
}

@Test func preservesTransactionDates() async throws {
    let engine = StridEngine()
    let text = "31/08/25  UPI-SOMEONE  0000110606687729  01/09/25  1,182.41"
    let entities = engine.detect(in: text)
    // Transaction dates should NOT be detected as DOB (no birth context)
    #expect(!entities.contains { $0.type == .inDOB })
}

@Test func detectsIFSC() async throws {
    let engine = StridEngine()
    let text = "RTGS/NEFT IFSC : HDFC0001234"
    let entities = engine.detect(in: text)
    #expect(entities.contains { $0.type == .inIFSC })
}
