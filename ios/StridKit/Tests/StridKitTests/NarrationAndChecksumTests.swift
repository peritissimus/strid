import Testing
@testable import StridKit

@Suite("Checksums")
struct ChecksumTests {
    @Test func verhoeffAcceptsValidAadhaar() {
        // Known-valid test vectors (Verhoeff check digit appended).
        #expect(Checksums.verhoeff("236") == true)        // 23 -> check 6
        #expect(Checksums.verhoeff("999999990018") == false)
        #expect(Checksums.verhoeff("999999990019") == true)
    }
    @Test func luhn() {
        #expect(Checksums.luhn("4111111111111111") == true)
        #expect(Checksums.luhn("4111111111111112") == false)
        #expect(Checksums.luhn("50100234567890") == false) // a bank account, not a card
    }
}

@Suite("Narration names")
struct NarrationTests {
    let r = NarrationRecognizer()
    func names(_ s: String) -> [String] { r.recognize(in: s).map(\.text) }

    @Test func upi() { #expect(names("UPI-PRIYA MEHTA-priya.mehta@oksbi-UTIB0001234-525412345678") == ["PRIYA MEHTA"]) }
    @Test func imps() { #expect(names("IMPS-P2A-ANIL KUMAR-9876501234@ybl-HDFC0000123") == ["ANIL KUMAR"]) }
    @Test func cheque() { #expect(names("CHQ DEP 000123 SUNITA SHARMA") == ["SUNITA SHARMA"]) }
    @Test func honorific() { #expect(names("MR RAHUL SHARMA") == ["RAHUL SHARMA"]) }
    @Test func neftCompanyIsNotAPerson() { #expect(names("NEFT CR-ICIC0000456-TCS LTD SALARY-N245251234567").isEmpty) }
    @Test func merchantIsNotAPerson() { #expect(names("UPI-SWIGGY-swiggy@axisbank-BIL/ONL/000123456").isEmpty) }
    @Test func initials() { #expect(names("UPI-RAMESH K-ramesh@ybl") == ["RAMESH K"]) }
}

@Suite("Engine filters")
struct FilterTests {
    @Test func labelsAreNotEntities() {
        let e = StridEngine()
        let found = e.detect(in: "IFSC: HDFC0000123 | MICR: 400240015\nRef No   Amount   Balance")
        #expect(!found.contains { $0.text == "IFSC" || $0.text == "MICR" || $0.text == "Ref" })
    }
    @Test func statementPeriodIsNotDOB() {
        let e = StridEngine()
        let found = e.detect(in: "DOB: 14/08/1987\nStatement Period: 01/09/2025 to 30/09/2025")
        let dobs = found.filter { $0.type == .inDOB }.map(\.text)
        #expect(dobs == ["14/08/1987"])
    }
    @Test func maskedCard() {
        let e = StridEngine()
        let found = e.detect(in: "ATM WDL-MUMBAI BANDRA-4567XXXXXXXX8901")
        #expect(found.contains { $0.type == .creditCard && $0.text == "4567XXXXXXXX8901" })
    }
}
