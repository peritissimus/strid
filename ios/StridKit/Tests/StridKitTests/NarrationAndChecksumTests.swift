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

@Suite("HDFC wrapped narrations")
struct WrappedNarrationTests {
    let e = StridEngine()
    @Test func singleWordUPIName() {
        let f = e.detect(in: "01/04/26 UPI-SHANAWAZ-shanawaz12@okaxis-UTIB0000123-5101234567\n89-M-UPI")
        #expect(f.contains { $0.type == .person && $0.text == "SHANAWAZ" })
        // Reference wrapped across the line break is captured whole.
        #expect(f.contains { $0.type == .inTxnRef && $0.text == "5101234567\n89" })
    }
    @Test func wrappedNEFTRef() {
        let f = e.detect(in: "NEFT CR-ICIC0000456-RZPX PVT LTD PAYROLL-IDFBH260\n92904881")
        #expect(f.contains { $0.type == .inTxnRef && $0.text.contains("92904881") })
    }
    @Test func gatewayBlob() {
        let f = e.detect(in: "UPI-SHIVA-BAJAJPAY.6879729.MDBCXUL@hdfcbank-HDFC0000001-5101234567")
        #expect(f.contains { $0.type == .inTxnRef && $0.text.contains("6879729") } || f.contains { $0.type == .inUPIID && $0.text.contains("6879729") })
    }
    @Test func doesNotEatNextRowDate() {
        let f = e.detect(in: "ref 510123456789\n02/04/26 UPI-X")
        #expect(f.contains { $0.type == .inTxnRef && $0.text == "510123456789" })
    }
    @Test func doesNotEatAmount() {
        let f = e.detect(in: "IMPS-P2A-VIDYANAND-vidya@ybl-510123456789\n351,684.00")
        #expect(f.contains { $0.type == .inTxnRef && $0.text == "510123456789" })
    }
}

@Suite("Role-labelled names")
struct RoleLabelTests {
    private func names(_ text: String) -> [String] {
        NarrationRecognizer().recognize(in: text).map { String(text[$0.range]) }
    }
    @Test func nomineeAndManagerAreCaught() {
        #expect(names("Account Type: Savings Nominee: Sunita Sharma") == ["Sunita Sharma"])
        #expect(names("Relationship Manager: Neha Iyer, neha@x.com") == ["Neha Iyer"])
        #expect(names("Joint Holder: RAHUL SHARMA") == ["RAHUL SHARMA"])
    }
    @Test func nameDoesNotRunOntoNextLine() {
        #expect(names("Nominee: Sunita Sharma\nAadhaar (masked): XXXX") == ["Sunita Sharma"])
    }
}

@Suite("GSTIN checksum")
struct GSTINTests {
    @Test func validAndInvalid() {
        #expect(Checksums.gstin("29AAJCB4821P1Z4") == true)
        // Published example from GST FAQs.
        #expect(Checksums.gstin("27AAPFU0939F1ZV") == true)
        #expect(Checksums.gstin("27AAPFU0939F1ZX") == false)
        #expect(Checksums.gstin("27AAPFU0939F1Z") == false)
    }
}

@Suite("GSTIN recognizer")
struct GSTINRecognizerTests {
    @Test func labelledButCorruptedIsStillCaught() {
        let hits = IndianBankingRecognizers.gstin.recognize(in: "GST Registration No: 29AAJCB4821P1ZQ")
        #expect(hits.map(\.text) == ["29AAJCB4821P1ZQ"])
        #expect(hits.first.map { $0.score < 0.9 } == true)
    }
    @Test func unlabelledAndCorruptedIsDropped() {
        #expect(IndianBankingRecognizers.gstin.recognize(in: "ref 29AAJCB4821P1ZQ paid").isEmpty)
    }
    @Test func validOneScoresHigh() {
        let hits = IndianBankingRecognizers.gstin.recognize(in: "27AAPFU0939F1ZV")
        #expect(hits.first.map { $0.score >= 0.95 } == true)
    }
}

@Suite("Address blocks")
struct AddressBlockTests {
    private func run(_ text: String) -> [(String, String)] {
        AddressBlockRecognizer().recognize(in: text).map { ($0.type.rawValue, String(text[$0.range])) }
    }
    @Test func labelledBlockYieldsNameAndAddress() {
        let text = """
        Billing Address :
        Kavya Raghunathan
        Flat 7B, Prestige Lakeside Habitat, Varthur Road
        Gunjur, Whitefield
        BENGALURU, KARNATAKA, 560087
        IN
        State/UT Code: 29
        """
        let got = run(text)
        #expect(got.contains { $0 == ("PERSON", "Kavya Raghunathan") })
        let addr = got.first { $0.0 == "ADDRESS" }?.1 ?? ""
        #expect(addr.hasPrefix("Flat 7B"))
        // The block closes at the PIN line and then takes the bare country line under it.
        #expect(addr.hasSuffix("560087\nIN"))
        #expect(!addr.contains("State/UT"))
    }
    @Test func companyFirstLineIsNotAPerson() {
        let got = run("Address: Brightline Retail Private Limited\nSurvey No. 45/2, Soukya Road\nBengaluru 560067")
        #expect(!got.contains { $0.0 == "PERSON" })
        #expect(got.first { $0.0 == "ADDRESS" }?.1.hasPrefix("Brightline") == true)
    }
    @Test func labelAtEndOfAMultiColumnLine() {
        let text = """
        PAN No: AAJCB4821P
        Order Number: 171-8264519-3350731 Order Date: 12.10.2025 Shipping Address :
        Kavya Raghunathan
        Kavya Raghunathan
        Flat 7B, Prestige Lakeside Habitat, Varthur Road
        Gunjur, Whitefield
        BENGALURU, KARNATAKA, 560087
        IN
        """
        let got = run(text)
        #expect(got.filter { $0 == ("PERSON", "Kavya Raghunathan") }.count == 2)
        #expect(got.first { $0.0 == "ADDRESS" }?.1.hasPrefix("Flat 7B") == true)
    }
    @Test func unlabelledPlaceNamesAreIgnored() {
        #expect(run("Branch: Bandra West, Mumbai 400050").isEmpty)
    }
}

@Suite("Field labels and numeric types") struct FieldLabelTests {
    let engine = StridEngine()
    func types(_ text: String) -> [(String, String)] { engine.detect(in: text).map { ($0.type.rawValue, $0.text) } }

    @Test func phoneUnderCustIDLabelStaysPhone() {
        let got = types("Phone no. : 9876543210\nCust ID : 78945612\nMICR : 560240002\nAccount No : 50100234567890")
        #expect(got.contains { $0 == ("PHONE", "9876543210") || $0 == ("IN_PHONE", "9876543210") })
        #expect(got.contains { $0 == ("IN_CUSTOMER_ID", "78945612") })
        #expect(got.contains { $0 == ("IN_MICR", "560240002") })
        #expect(got.contains { $0 == ("IN_BANK_ACCOUNT", "50100234567890") })
    }
    @Test func chequeReferenceIsNotACard() {
        // Luhn-valid but starts with 0: a statement reference, never a card.
        let got = types("Chq./Ref.No. 0000609490975800 03/04/26 609.00")
        #expect(!got.contains { $0.0 == "CREDIT_CARD" })
        #expect(got.contains { $0.1 == "0000609490975800" })
    }
    @Test func contextWordsAreWholeWords() {
        // "provided" contains "vid"; a 16-digit run with no label must not become an Aadhaar VID.
        let got = types("Services provided under ref 4111 2222 3333 4444 as agreed.")
        #expect(!got.contains { $0.0 == "IN_AADHAAR" })
    }
    @Test func vidOnCardIsAadhaar() {
        let got = types("VID : 9144 1720 6183 2506\n1947\nhelp@uidai.gov.in")
        #expect(got.contains { $0 == ("IN_AADHAAR", "9144 1720 6183 2506") })
        #expect(got.contains { $0 == ("EMAIL", "help@uidai.gov.in") })
    }
    @Test func amountNeverBecomesWrappedHead() {
        let got = types("UPI-RAVI KUMAR-ravi@okaxis 70.00\n0000609172329708")
        #expect(!got.contains { $0.1.contains("70.00") })
    }
}

@Suite("Unlabelled address blocks") struct UnlabelledAddressTests {
    let engine = StridEngine()
    func texts(_ text: String, _ type: PIIEntityType) -> [String] { engine.detect(in: text).filter { $0.type == type }.map(\.text) }

    @Test func statementHeaderBlockAfterHonorific() {
        let text = "MR. RAHUL SHARMA\nA3\nNAVEEN TERRACES APARTMENTS\n4TH BLOCK, 100FT ROAD, KORAMANGALA\nBENGALURU 560034\nKARNATAKA INDIA\nJOINT HOLDERS :"
        let all = engine.detect(in: text)
        let joined = all.map(\.text).joined(separator: "|")
        for part in ["A3", "NAVEEN", "TERRACES APARTMENTS", "4TH BLOCK", "KORAMANGALA", "560034", "KARNATAKA"] {
            #expect(joined.contains(part), "missing \(part)")
        }
        #expect(!joined.contains("JOINT"))
    }
    @Test func aadhaarBackWithCareOfLine() {
        let text = "Address:\nC/O: Ramesh Kulkarni, ward no 12, mahatma\ngandhi ward, kothrud, Pune,\nMaharashtra - 411038.\n5th Floor 12/12"
        let all = engine.detect(in: text)
        let joined = all.map(\.text).joined(separator: "|")
        #expect(all.contains { $0.type == .person && $0.text == "Ramesh Kulkarni" })
        for part in ["ward no 12", "gandhi ward", "kothrud", "411038"] { #expect(joined.contains(part), "missing \(part)") }
        #expect(!joined.contains("5th Floor"))
    }
    @Test func hindiPinAnchoredBlock() {
        let text = "Unique Identification Authority of India\nपता:\nद्वारा: रमेश कुलकर्णी, वॉर्ड न 12,\nकोथरूड, पुणे,\nमहाराष्ट्र - 411038"
        let addr = texts(text, .address)
        #expect(addr.contains { $0.contains("रमेश") && $0.contains("कोथरूड") })
        #expect(!addr.contains { $0.contains("Authority") })
    }
    @Test func pageNumberAfterFooterLabelIsNotAnAddress() {
        // A footer label at the end of one page followed by the next page's header.
        let text = "Registered Office Address:\n\u{0C}Page No .: 2\nHDFC BANK\nWe understand your world"
        let addr = texts(text, .address)
        #expect(!addr.contains { $0.contains("Page") })
    }
    @Test func addressIsSplitAroundNameNotDropped() {
        let text = "Shipping Address :\nFlat 7B, Prestige Lakeside Habitat, Varthur Road\nBENGALURU, KARNATAKA, 560087"
        let joined = engine.detect(in: text).map(\.text).joined(separator: "|")
        for part in ["Flat 7B", "Varthur Road", "560087"] { #expect(joined.contains(part), "missing \(part)") }
    }
}

@Suite("OCR wraps in narrations") struct NarrationWrapTests {
    let engine = StridEngine()
    @Test func oneWordPayeeAtEndOfLine() {
        let got = engine.detect(in: "01/04/26 UPI-PARMANAND\n0000609340742237")
        #expect(got.contains { $0.type == .person && $0.text == "PARMANAND" })
    }
    @Test func upiHandleSplitAcrossLines() {
        let got = engine.detect(in: "UPI-RAHUL\nPAYTM-73734402@\nPTYS-HDFC0000123-512345678901-UPI")
        #expect(got.contains { $0.type == .inUPIID && $0.text == "PAYTM-73734402@\nPTYS" })
        #expect(got.contains { $0.type == .person && $0.text == "RAHUL" })
    }
}
