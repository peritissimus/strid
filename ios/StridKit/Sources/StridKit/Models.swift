import Foundation

/// All PII entity types supported by Strid.
public enum PIIEntityType: String, CaseIterable, Codable, Sendable {
    // Universal
    case person = "PERSON"
    case email = "EMAIL"
    case phone = "PHONE"
    case url = "URL"
    case location = "LOCATION"
    case organization = "ORGANIZATION"
    case creditCard = "CREDIT_CARD"
    case ipAddress = "IP_ADDRESS"

    // Indian banking
    case inBankAccount = "IN_BANK_ACCOUNT"
    case inIFSC = "IN_IFSC"
    case inPAN = "IN_PAN"
    case inAadhaar = "IN_AADHAAR"
    case inUPIID = "IN_UPI_ID"
    case inMICR = "IN_MICR"
    case inPhone = "IN_PHONE"
    case inPINCode = "IN_PIN_CODE"
    case inCustomerID = "IN_CUSTOMER_ID"
    case inBranchCode = "IN_BRANCH_CODE"
    case inTxnRef = "IN_TXN_REF"
    case inDOB = "IN_DOB"

    public var displayName: String {
        switch self {
        case .person: "Person"
        case .email: "Email"
        case .phone: "Phone"
        case .url: "URL"
        case .location: "Location"
        case .organization: "Organization"
        case .creditCard: "Credit Card"
        case .ipAddress: "IP Address"
        case .inBankAccount: "Bank Account"
        case .inIFSC: "IFSC Code"
        case .inPAN: "PAN"
        case .inAadhaar: "Aadhaar"
        case .inUPIID: "UPI ID"
        case .inMICR: "MICR Code"
        case .inPhone: "Indian Phone"
        case .inPINCode: "PIN Code"
        case .inCustomerID: "Customer ID"
        case .inBranchCode: "Branch Code"
        case .inTxnRef: "Txn Reference"
        case .inDOB: "Date of Birth"
        }
    }
}

/// A single detected PII entity in the source text.
public struct PIIEntity: Identifiable, Sendable {
    public let id = UUID()
    public let type: PIIEntityType
    public let text: String
    public let range: Range<String.Index>
    public let score: Double

    public init(type: PIIEntityType, text: String, range: Range<String.Index>, score: Double = 1.0) {
        self.type = type
        self.text = text
        self.range = range
        self.score = score
    }
}

/// How redacted text should appear.
public enum RedactionStyle: Sendable {
    /// Replace with type label: `<PERSON>`
    case placeholder
    /// Replace with asterisks: `****`
    case asterisks
    /// Replace with a fixed character repeated to match length
    case charFill(Character)
}
