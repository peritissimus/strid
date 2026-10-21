import Testing
@testable import StridKit

/// Passport, voter ID, driving licence, vehicle, EPF, TAN and CIN shapes.
@Suite struct IdentityDocumentTests {
    let engine = StridEngine()
    func types(_ s: String) -> [(PIIEntityType, String)] { engine.detect(in: s).map { ($0.type, $0.text) } }
    func has(_ s: String, _ t: PIIEntityType, _ v: String) -> Bool { types(s).contains { $0.0 == t && $0.1.contains(v) } }

    @Test func passportNumberNeedsLabel() {
        #expect(has("Passport No. M8231456\nDate of Issue 12/04/2021", .inPassport, "M8231456"))
        #expect(!has("Ticket M8231456 confirmed", .inPassport, "M8231456"))
    }

    @Test func passportMRZLines() {
        let mrz = "P<INDVENKATESH<<ROHAN<<<<<<<<<<<<<<<<<<<<<<<<\nM8231456<4IND9008215M3104129<<<<<<<<<<<<<<<4"
        #expect(has(mrz, .inPassport, "P<INDVENKATESH"))
        #expect(has(mrz, .inPassport, "M8231456<4IND"))
    }

    @Test func voterIDWithCardWords() {
        #expect(has("ELECTION COMMISSION OF INDIA\nElector's Photo Identity Card\nRJP2846153", .inVoterID, "RJP2846153"))
        #expect(has("EPIC No: RJP2846153", .inVoterID, "RJP2846153"))
        #expect(!has("Batch ABC1234567 shipped", .inVoterID, "ABC1234567"))
    }

    @Test func drivingLicenceShapes() {
        #expect(has("DL No: KA05 20180012345", .inDrivingLicence, "KA05 20180012345"))
        #expect(has("Licence MH12 20110062821 valid", .inDrivingLicence, "MH12 20110062821"))
        #expect(has("DL-0420110149646", .inDrivingLicence, "DL-0420110149646"))
        // Not a state code.
        #expect(!has("XX01 20180012345", .inDrivingLicence, "XX01"))
    }

    @Test func vehicleRegistration() {
        #expect(has("Regn. No: KA 05 MJ 4821", .inVehicleReg, "KA 05 MJ 4821"))
        #expect(has("Vehicle KA05MJ4821 parked", .inVehicleReg, "KA05MJ4821"))
        #expect(has("Regn No 22 BH 1234 AA", .inVehicleReg, "22 BH 1234 AA"))
        #expect(has("Chassis No: MA3EWDE1S00482915", .inVehicleReg, "MA3EWDE1S00482915"))
        #expect(has("Engine No: K12MN4582113", .inVehicleReg, "K12MN4582113"))
        #expect(!has("Order ZZ 12 AB 1234", .inVehicleReg, "ZZ"))
    }

    @Test func epfNumbers() {
        #expect(has("UAN: 100987654321", .inUAN, "100987654321"))
        #expect(has("PF A/c No: KA/BNG/0012345/000/0001234", .inUAN, "KA/BNG/0012345/000/0001234"))
        #expect(!has("Ref 100987654321 credited", .inUAN, "100987654321"))
    }

    @Test func tanAndCIN() {
        #expect(has("TAN of the Deductor\nBLRR12345F", .inTAN, "BLRR12345F"))
        #expect(!has("Code BLRR12345F", .inTAN, "BLRR12345F"))
        #expect(has("CIN U72200KA2015PTC081234", .inCIN, "U72200KA2015PTC081234"))
        #expect(has("L17110MH1973PLC019786 is listed", .inCIN, "L17110MH1973PLC019786"))
    }

    @Test func cardSecurityAndIBAN() {
        #expect(has("CVV: 123 Valid Thru 09/28", .creditCard, "123"))
        #expect(has("CVV: 123 Valid Thru 09/28", .creditCard, "09/28"))
        #expect(has("IBAN GB82 WEST 1234 5698 7654 32", .inBankAccount, "GB82 WEST"))
        #expect(!has("IBAN GB82 WEST 1234 5698 7654 33", .inBankAccount, "GB82 WEST"))
    }

    @Test func labelsDecideTypeAmongNumbers() {
        // A 12-digit UAN that also passes no Aadhaar check must not be called Aadhaar; a labelled
        // passport number is not a transaction reference.
        let t = types("UAN: 100987654321\nPassport No: M8231456")
        #expect(t.contains { $0.0 == .inUAN })
        #expect(!t.contains { $0.0 == .inTxnRef && $0.1 == "M8231456" })
    }
}
