import Testing
@testable import StridKit

private let statement = """
Name: Rahul Sharma   Customer ID: 88213345
Account No: 50100234567890   IFSC: HDFC0001234
15/09/25  POS AMAZON PAY INDIA  Ref 5254123456  1,182.41
Nominee: Priya Mehta
"""

@Test func defaultPolicyChangesNothing() {
    let engine = StridEngine()
    let a = engine.detect(in: statement)
    let b = engine.detect(in: statement, policy: .default)
    #expect(a.map(\.text) == b.map(\.text))
}

@Test func disabledTypesAreDropped() {
    let engine = StridEngine()
    let all = engine.detect(in: statement)
    #expect(all.contains { $0.type == .inTxnRef })
    let policy = RedactionPolicy(enabledTypes: Set(PIIEntityType.allCases).subtracting([.inTxnRef]))
    let some = engine.detect(in: statement, policy: policy)
    #expect(!some.contains { $0.type == .inTxnRef })
    #expect(some.contains { $0.type == .inBankAccount })
}

@Test func alwaysRedactTermIsFoundCaseInsensitivelyAndWordBounded() {
    let engine = StridEngine()
    let policy = RedactionPolicy(alwaysRedact: [.init("rahul sharma", type: .person)])
    let found = engine.detect(in: "Paid by RAHUL SHARMA, not by Rahulsharman.", policy: policy)
    let persons = found.filter { $0.type == .person && $0.score >= 1.0 }
    #expect(persons.map(\.text) == ["RAHUL SHARMA"])
}

@Test func alwaysRedactNumberIgnoresSpacingAndDashes() {
    let engine = StridEngine()
    let policy = RedactionPolicy(alwaysRedact: [.init("5010 0234 5678 90", type: .inBankAccount)])
    let text = "A/c 50100234567890 and 5010-0234-5678-90"
    let found = engine.detect(in: text, policy: policy).filter { $0.type == .inBankAccount }
    #expect(found.count == 2)
}

@Test func alwaysRedactTermBeatsPublicOrganisationList() {
    let engine = StridEngine()
    // "HDFC Bank" is normally kept visible as a public organisation.
    let text = "Statement from HDFC Bank, Bandra branch"
    #expect(!engine.detect(in: text).contains { $0.text.lowercased() == "hdfc bank" })
    let policy = RedactionPolicy(alwaysRedact: [.init("HDFC Bank", type: .organization)])
    #expect(engine.detect(in: text, policy: policy).contains { $0.text == "HDFC Bank" })
}

@Test func keepVisibleSuppressesAFinding() {
    let engine = StridEngine()
    let base = engine.detect(in: statement)
    let priya = base.first { $0.text.lowercased().contains("priya") }
    #expect(priya != nil)
    let policy = RedactionPolicy(keepVisible: ["Priya Mehta"])
    let after = engine.detect(in: statement, policy: policy)
    #expect(!after.contains { $0.text.lowercased().contains("priya") })
    #expect(after.contains { $0.type == .inBankAccount })
}

@Test func excludedValuesDropOnlyThatValue() {
    let engine = StridEngine()
    let base = engine.detect(in: statement)
    guard let ref = base.first(where: { $0.type == .inTxnRef }) else { Issue.record("no txn ref"); return }
    let policy = RedactionPolicy(excludedValues: [RedactionPolicy.normalise(ref.text)])
    let after = engine.detect(in: statement, policy: policy)
    #expect(!after.contains { $0.text == ref.text })
    #expect(after.count == base.count - 1)
}

@Test func normaliseCollapsesNumbersAndCase() {
    #expect(RedactionPolicy.normalise("5010 0234-5678") == "501002345678")
    #expect(RedactionPolicy.normalise("  Rahul   Sharma ") == "rahul sharma")
}
