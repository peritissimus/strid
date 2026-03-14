import Testing
@testable import StridKit

/// Test with a realistic Indian bank statement sample.
@Suite("Indian Bank Statement")
struct SampleStatementTests {
    let sampleStatement = """
    HDFC BANK Ltd.                                     Page No .:   1

                                                                             Account Branch : CYBER CITY
                                                                             Address        : HDFC BANK LTD
                                                                                              SHOP NO. S1 AND S2, GROUND FLOOR,
    MR.     RAHUL SHARMA                                                                      S S PLAZA, SECTOR 47,
    FLAT NO 302, WING B                                                                       City           : GURGAON 122003
    NAVEEN TERRACES APARTMENTS                                                                State          : HARYANA
    SECTOR 56, GOLF COURSE ROAD                                                               Phone no.      : 18002600/18001600
    GURGAON 122011                                                                            Email          : rahul.sharma@gmail.com
    HARYANA                                                                                   OD Limit       :              0.00   Currency : INR
                                                                             Cust ID        : 84729163
    JOINT HOLDERS :                                                          Account No     : 50100248731642
                                                                             A/C Open Date  : 06/05/2023
    Nomination : Registered                                                  Account Status : Regular
    Statement From      : 01/09/2025  To: 28/02/2026                         RTGS/NEFT IFSC : HDFC0001847    MICR : 110240365
                                                                             Branch Code    : 1847    Product Code : 100

    --------  ----------------------------------------  ----------------  --------  ------------------  ------------------  ------------------
    Date      Narration                                 Chq./Ref.No.      Value Dt  Withdrawal Amt.     Deposit Amt.        Closing Balance
    --------  ----------------------------------------  ----------------  --------  ------------------  ------------------  ------------------

    01/09/25  UPI-ETERNAL LIMITED-ZOMATOONLINEORDER.RZ  0000110606687729  01/09/25           1,182.41                             775,113.82
              P@RXAIRTEL-AIRP0000011-110606687729-ZOMA
              TOONLINEORDER

    01/09/25  UPI-SWIGGY-SWIGGYORDERS@OKSBI-SBIN00009  0000983746251834  01/09/25             456.00                             774,657.82
              87-983746251834-SWIGGYORDERS

    02/09/25  NEFT-ACME CORP PVT LTD-SALARY SEP 2025   N123202509021847  02/09/25                              185,000.00        959,657.82

    03/09/25  UPI-PRIYA PATEL-9876543210@OKHDFC-HDFC00  0000567812349012  03/09/25          25,000.00                             934,657.82
              01234-567812349012-RENT SEPT

    05/09/25  ATM-CASH WITHDRAWAL-SECTOR 47 GURGAON    S1AT001923847562  05/09/25          10,000.00                             924,657.82

    07/09/25  EMI-HDFC HOME LOAN-HL/2024/08472916      0000284719305826  07/09/25          42,567.00                             882,090.82

    10/09/25  UPI-AMAZON PAY-AMAZONPAY@AXISBANK-UTIB00  0000741852963074  10/09/25           3,499.00                             878,591.82
              00123-741852963074-PURCHASE

    15/09/25  IMPS-VIKRAM MEHTA-919845672301@PAYTM-PTM  0000192837465012  15/09/25          15,000.00                             863,591.82
              -192837465012-PERSONAL

    20/09/25  PAN: BVMPS4521K VERIFIED                  TAX202509201847   20/09/25                                                863,591.82

    25/09/25  UPI-BIGBASKET-BBORDERS.RZP@HDFCBANK-HDFC  0000384756192038  25/09/25           2,847.50                             860,744.32
              0001234-384756192038-GROCERIES

    28/09/25  Date of Birth verification: 15/08/1992    DOB20250928001    28/09/25                                                860,744.32

    30/09/25  INTEREST CREDIT                           INT202509301847   30/09/25                                4,127.35        864,871.67

    --------  ----------------------------------------  ----------------  --------  ------------------  ------------------  ------------------
    """

    let engine = StridEngine(threshold: 0.5)

    @Test func detectsNames() {
        let entities = engine.detect(in: sampleStatement)
        let persons = entities.filter { $0.type == .person || $0.type == .organization }
        // Apple NLP may detect names differently with all-caps text;
        // verify at least some name/org entity is found in the header area
        #expect(!persons.isEmpty)
    }

    @Test func detectsEmail() {
        let entities = engine.detect(in: sampleStatement)
        let emails = entities.filter { $0.type == .email }
        #expect(emails.contains { $0.text.contains("rahul.sharma@gmail.com") })
    }

    @Test func detectsAccountNumber() {
        let entities = engine.detect(in: sampleStatement)
        let accounts = entities.filter { $0.type == .inBankAccount }
        #expect(accounts.contains { $0.text == "50100248731642" })
    }

    @Test func detectsIFSCCode() {
        let entities = engine.detect(in: sampleStatement)
        let ifscs = entities.filter { $0.type == .inIFSC }
        #expect(ifscs.contains { $0.text == "HDFC0001847" })
    }

    @Test func detectsPAN() {
        let entities = engine.detect(in: sampleStatement)
        let pans = entities.filter { $0.type == .inPAN }
        #expect(pans.contains { $0.text == "BVMPS4521K" })
    }

    @Test func detectsUPIIDs() {
        let entities = engine.detect(in: sampleStatement)
        let upis = entities.filter { $0.type == .inUPIID }
        let upiTexts = upis.map { $0.text }
        // Verify known UPI IDs are found
        #expect(upiTexts.contains { $0.contains("@OKSBI") || $0.contains("@oksbi") })
        #expect(upiTexts.contains { $0.contains("@AXISBANK") || $0.contains("@axisbank") })
    }

    @Test func detectsTxnReferences() {
        let entities = engine.detect(in: sampleStatement)
        let refs = entities.filter { $0.type == .inTxnRef || $0.type == .creditCard }
        // 16-digit ref numbers should be caught (as txn ref or credit card pattern)
        #expect(refs.contains { $0.text.contains("110606687729") })
    }

    @Test func detectsCustomerID() {
        let entities = engine.detect(in: sampleStatement)
        let custIds = entities.filter { $0.type == .inCustomerID }
        #expect(custIds.contains { $0.text == "84729163" })
    }

    @Test func detectsDOBButNotTransactionDates() {
        let entities = engine.detect(in: sampleStatement)
        let dobs = entities.filter { $0.type == .inDOB }
        // Should catch 15/08/1992 (near "Date of Birth" context)
        #expect(dobs.contains { $0.text == "15/08/1992" })
        // Should NOT catch transaction dates like 01/09/25, 02/09/25 etc.
        #expect(!dobs.contains { $0.text == "01/09/25" })
        #expect(!dobs.contains { $0.text == "02/09/25" })
    }

    @Test func detectsLocations() {
        let entities = engine.detect(in: sampleStatement)
        let locations = entities.filter { $0.type == .location || $0.type == .inPINCode }
        let texts = locations.map { $0.text }
        #expect(texts.contains { $0.contains("GURGAON") || $0.contains("122011") || $0.contains("122003") || $0.contains("HARYANA") })
    }

    @Test func redactionReplacesAllPII() {
        let redacted = engine.redact(sampleStatement)
        // Sensitive data should be gone
        #expect(!redacted.contains("rahul.sharma@gmail.com"))
        #expect(!redacted.contains("50100248731642"))
        #expect(!redacted.contains("HDFC0001847"))
        #expect(!redacted.contains("BVMPS4521K"))
        #expect(!redacted.contains("84729163"))
        // Transaction dates should be preserved
        #expect(redacted.contains("01/09/25") || redacted.contains("02/09/25"))
    }

    @Test func printsSummaryAndRedactedOutput() {
        let entities = engine.detect(in: sampleStatement)
        let redacted = engine.redact(sampleStatement)

        // Print summary
        print("\n===== PII DETECTION SUMMARY =====")
        let counts = Dictionary(grouping: entities, by: \.type)
        for (type, items) in counts.sorted(by: { $0.value.count > $1.value.count }) {
            print("  \(type.displayName): \(items.count)")
            for item in items.prefix(3) {
                print("    → \"\(item.text)\" (score: \(String(format: "%.2f", item.score)))")
            }
            if items.count > 3 { print("    ... and \(items.count - 3) more") }
        }
        print("  TOTAL: \(entities.count) entities\n")

        print("===== REDACTED OUTPUT (first 2000 chars) =====")
        print(String(redacted.prefix(2000)))
        print("===============================================\n")

        #expect(entities.count > 10)
    }
}
