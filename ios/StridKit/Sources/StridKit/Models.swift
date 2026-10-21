//
// Models.swift
// StridKit
//
// Core value types shared by every layer of Strid:
//
//   - `PIIEntityType`   the closed set of entity categories the engine can report
//   - `PIIEntity`       one detected span (type, matched text, range, confidence)
//   - `RedactionStyle`  how a span is rendered once redacted
//
// These are intentionally plain, `Sendable` value types with no Foundation-specific behaviour so
// they can cross actor boundaries, be encoded to JSON (entity types) and be used from both the
// iOS app and the CLI.
//
import Foundation

/// All PII entity types supported by Strid.
///
/// The raw values are stable, upper-snake-case identifiers that double as:
///   - the `<PLACEHOLDER>` text in `.placeholder` redaction style,
///   - the prefix of reversible tokens such as `[PERSON_1]`,
///   - the `entity_type` field in CLI JSON output,
///   - the values accepted by `strid --entity` and the eval corpus `expected.json` files.
///
/// The `IN_` prefix marks types specific to Indian banking and identity documents. Several of
/// these overlap numerically (a 12-digit run could be an Aadhaar, a transaction reference or a
/// bank account); the engine resolves such ties via scores and `StridEngine.specificity`.
public enum PIIEntityType: String, CaseIterable, Codable, Sendable {
    // MARK: - Universal

    /// A person's name. Produced by NLTagger, the narration parser and honorific patterns.
    case person = "PERSON"
    /// An email address, e.g. `priya.mehta@example.com`.
    case email = "EMAIL"
    /// A generic phone number as found by NSDataDetector (filtered to Indian shapes).
    case phone = "PHONE"
    /// A web URL. Rarely sensitive on its own but may embed usernames or tracking identifiers.
    case url = "URL"
    /// A place name or postal address (NLTagger, NSDataDetector or the Indian gazetteer).
    case location = "LOCATION"
    /// A company or institution name as tagged by NLTagger.
    case organization = "ORGANIZATION"
    /// A payment card number, Luhn-validated or printed masked (`4567XXXXXXXX8901`).
    case creditCard = "CREDIT_CARD"
    /// An IPv4 address.
    case ipAddress = "IP_ADDRESS"

    // MARK: - Indian banking

    /// A bank account number: 9 to 18 digits, scored up when account context words are nearby.
    case inBankAccount = "IN_BANK_ACCOUNT"
    /// Indian Financial System Code identifying a bank branch, e.g. `HDFC0001234`.
    case inIFSC = "IN_IFSC"
    /// Permanent Account Number issued by the Income Tax Department, e.g. `ABCDE1234F`.
    case inPAN = "IN_PAN"
    /// 12-digit Aadhaar identity number, Verhoeff-validated.
    case inAadhaar = "IN_AADHAAR"
    /// Unified Payments Interface virtual payment address, e.g. `name@oksbi`.
    case inUPIID = "IN_UPI_ID"
    /// 9-digit Magnetic Ink Character Recognition code printed on cheques.
    case inMICR = "IN_MICR"
    /// Indian mobile number: 10 digits starting 6-9, optionally with `+91` or `0` prefix.
    case inPhone = "IN_PHONE"
    /// 6-digit Indian postal PIN code.
    case inPINCode = "IN_PIN_CODE"
    /// Bank customer / CIF identifier, 7 to 11 digits near customer context.
    case inCustomerID = "IN_CUSTOMER_ID"
    /// Short alphanumeric branch code near "branch code" context.
    case inBranchCode = "IN_BRANCH_CODE"
    /// Transaction reference: UTR, RRN, cheque number, NEFT/IMPS/UPI reference, gateway ref.
    case inTxnRef = "IN_TXN_REF"
    /// Date of birth. Only dates near birth context, so transaction dates are left alone.
    case inDOB = "IN_DOB"

    /// Human-readable label for UI lists and the `strid entities` table.
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
///
/// Entities are produced by recognizers and refined by `StridEngine`. The `range` is the
/// authoritative location; `text` is a convenience copy of `source[range]` kept so that
/// callers (UI, reports, token maps) do not need the original string to display the match.
///
/// Equality is deliberately *not* synthesised: two entities with the same range but different
/// types are different findings, and the random `id` makes each instance unique for SwiftUI lists.
public struct PIIEntity: Identifiable, Sendable {
    /// Unique per instance; used by SwiftUI `ForEach`, not for semantic identity.
    public let id = UUID()
    /// Category of the finding.
    public let type: PIIEntityType
    /// The matched substring, exactly as it appears in the source (no trimming or normalisation).
    public let text: String
    /// Location of `text` inside the string that was passed to `recognize(in:)` / `detect(in:)`.
    public let range: Range<String.Index>
    /// Confidence in `0...1`. Compared against `StridEngine`'s threshold and used to break
    /// overlap ties. Regex recognizers start from a base score and add context / validator boosts.
    public let score: Double

    /// - Parameters:
    ///   - type: Entity category.
    ///   - text: Matched substring; should equal the source text at `range`.
    ///   - range: Position in the scanned string.
    ///   - score: Confidence, defaulting to certain (`1.0`).
    public init(type: PIIEntityType, text: String, range: Range<String.Index>, score: Double = 1.0) {
        self.type = type
        self.text = text
        self.range = range
        self.score = score
    }
}

/// How redacted text should appear.
///
/// Applies to text-based outputs (plain text, DOCX/RTF, CLI stdout). Rasterised outputs (PDF,
/// images) always paint black boxes and ignore the style. Reversible mode bypasses styles
/// entirely and substitutes stable tokens via `TokenMap`.
public enum RedactionStyle: Sendable {
    /// Replace with type label: `<PERSON>`
    ///
    /// Preserves *what kind* of information was removed, which keeps documents readable
    /// ("paid to `<PERSON>` via `<IN_UPI_ID>`"). Length is not preserved.
    case placeholder
    /// Replace with asterisks: `****`
    ///
    /// One `*` per character of the original, so column alignment in tabular text survives.
    case asterisks
    /// Replace with a fixed character repeated to match length
    ///
    /// Like `.asterisks` but with a caller-chosen character (e.g. `X` or a block glyph).
    case charFill(Character)
}
