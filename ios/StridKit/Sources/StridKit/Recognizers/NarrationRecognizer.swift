//
// NarrationRecognizer.swift
// StridKit
//
// Template-based name extraction for the one place NLTagger consistently fails: the "Narration"
// or "Particulars" column of an Indian bank statement. Narrations are upper-case, delimiter
// separated strings assembled by core-banking systems from a handful of fixed layouts
// (UPI-NAME-VPA-IFSC-REF, IMPS-P2A-NAME-..., NEFT CR-IFSC-NAME-UTR, CHQ DEP nnn NAME, ...).
// Because the layout is fixed, the position of the counterparty name is predictable, and a
// regex anchored on the rail keyword can capture it far more reliably than a statistical model.
//
// Each pattern captures the candidate name in a group; `trimStopWords` then peels off tokens
// that are not part of a person's name ("SALARY", "LTD") and rejects spans that turn out to be
// organisations or pure boilerplate.
//
import Foundation

/// Finds counterparty names inside Indian bank transaction narrations, which are printed in
/// ALL CAPS and follow fixed templates that general NER models handle poorly, e.g.
///   UPI-PRIYA MEHTA-priya.mehta@oksbi-UTIB0001234-525412345678
///   IMPS-P2A-ANIL KUMAR-9876501234@ybl-HDFC0000123
///   NEFT CR-ICIC0000456-TCS LTD SALARY-N245251234567
///   CHQ DEP 000123 SUNITA SHARMA
///   MR RAHUL SHARMA / SMT SUNITA DEVI
public struct NarrationRecognizer: Recognizer {
    public init() {}

    /// Tokens that look like names but are not.
    ///
    /// Compared against each captured word upper-cased with dots removed. Grouped roughly as:
    /// payment rails and channel codes, transaction nouns, corporate suffixes and well-known
    /// companies/banks/merchants, product and column-header words, major cities and address
    /// words, and honorifics (which the honorific pattern matches *before* the name, so they must
    /// not survive inside the captured span either).
    static let stopWords: Set<String> = [
        "UPI", "IMPS", "NEFT", "RTGS", "ATM", "POS", "ACH", "ECS", "NACH", "CHQ", "CHEQUE", "DEP", "WDL", "CASH",
        "P2A", "P2P", "P2M", "CR", "DR", "TO", "BY", "FROM", "TRANSFER", "TRF", "PAYMENT", "PAY", "PAID", "REF",
        "SALARY", "SAL", "EMI", "LOAN", "INTEREST", "INT", "CHARGES", "CHG", "FEE", "GST", "TAX", "TDS",
        "LTD", "LIMITED", "PVT", "PRIVATE", "INDIA", "BANK", "HDFC", "ICICI", "SBI", "AXIS", "KOTAK", "YES", "IDFC",
        "PAYTM", "PHONEPE", "GPAY", "GOOGLE", "AMAZON", "FLIPKART", "SWIGGY", "ZOMATO", "UBER", "OLA", "IRCTC",
        "JIO", "AIRTEL", "VODAFONE", "BSNL", "TATA", "RELIANCE", "INFOSYS", "TCS", "WIPRO",
        "ONLINE", "ONL", "BIL", "BILL", "RECHARGE", "MOBILE", "ELECTRICITY", "RENT", "HOME", "CAR", "PERSONAL",
        "SAVINGS", "CURRENT", "ACCOUNT", "A/C", "AC", "NO", "DATE", "AMOUNT", "BALANCE", "NARRATION", "DESCRIPTION",
        "MUMBAI", "DELHI", "BANGALORE", "BENGALURU", "CHENNAI", "KOLKATA", "HYDERABAD", "PUNE", "AHMEDABAD",
        "BANDRA", "ANDHERI", "WEST", "EAST", "NORTH", "SOUTH", "ROAD", "NAGAR", "MARG", "BRANCH",
        "MR", "MRS", "MS", "SHRI", "SMT", "KUMARI", "DR", "M/S",
    ]

    /// A name: 2 to 4 capitalised words, each 2+ letters, allowing a trailing initial with a dot.
    ///
    /// Two alternatives:
    ///   - `(?:[A-Z]{2,}(?:\.?\s+|\.)){1,3}[A-Z]{2,}\.?`: 2-4 upper-case words of 2+ letters,
    ///     separated by whitespace or a dot (`PRIYA MEHTA`, `A.K. SHARMA` style runs where the
    ///     dot acts as the separator), optional trailing dot.
    ///   - `[A-Z]{2,}(?:\s+[A-Z]\.?){1,2}`: a surname followed by one or two single-letter
    ///     initials (`SHARMA R K`, `KUMAR S.`).
    /// Substituted for the literal `NAME` in the first group of patterns below.
    private static let nameCore = #"(?:[A-Z]{2,}(?:\.?\s+|\.)){1,3}[A-Z]{2,}\.?|[A-Z]{2,}(?:\s+[A-Z]\.?){1,2}"#

    /// Compiled narration templates. The first block uses the `NAME` placeholder (replaced by
    /// `nameCore`); the second block has its own capture groups and is compiled verbatim.
    ///
    /// Common building blocks in the first block:
    ///   - `[-/ ]`               rail separator: hyphen, slash or space depending on the bank
    ///   - `(?:\w{6,}[-/])?`     an optional reference token (6+ word chars) before the name
    ///   - `(?=\s*[-/@]|\s*$)`   lookahead: the name must be followed by a separator, an `@`
    ///                           (start of the VPA) or end of text, so the capture cannot run on
    ///                           into the next field
    private static let patterns: [NSRegularExpression] = [
        // UPI-NAME-vpa  /  UPI/ref/NAME/  /  UPI-NAME@... (name precedes a VPA or separator)
        #"\bUPI[-/ ](?:\w{6,}[-/])?(NAME)(?=\s*[-/@]|\s*$)"#,
        // IMPS-P2A-NAME-  /  IMPS/P2P/ref/NAME
        // `P2[APM]` = person-to-account / person-to-person / person-to-merchant mode flag.
        #"\bIMPS[-/ ](?:P2[APM][-/])?(?:\w{6,}[-/])?(NAME)(?=\s*[-/]|\s*$)"#,
        // NEFT CR-IFSC-NAME-ref  /  NEFT-ref-NAME  /  RTGS ...
        // Optional CR/DR direction, optional IFSC (`[A-Z]{4}0[A-Z0-9]{6}`), optional ref, then the name.
        #"\b(?:NEFT|RTGS)[-/ ](?:CR|DR)?[-/ ]?(?:[A-Z]{4}0[A-Z0-9]{6}[-/])?(?:\w{6,}[-/])?(NAME)(?=\s*[-/]|\s*$)"#,
        // CHQ DEP 000123 NAME  /  CHQ PAID NAME  /  CHQ NO 123 NAME
        #"\bCHQ(?:\s+(?:DEP|PAID|NO|ISSUED))?\s+(?:\d+\s+)?(NAME)\b"#,
        // BY TRANSFER-NAME  /  TO TRANSFER-NAME  /  TRF TO NAME  /  TRF FROM NAME
        // Two alternatives, hence two capture groups; `recognize` takes the first non-empty one.
        #"\b(?:BY|TO)\s+TRANSFER[-/ ](NAME)\b|\bTRF\s+(?:TO|FROM)\s+(NAME)\b"#,
        // Honorifics
        // "MR RAHUL SHARMA", "SMT. SUNITA DEVI", "DR ANIL KUMAR"; the honorific itself is outside the group.
        #"\b(?:MR|MRS|MS|SHRI|SMT|KUMARI|DR)\.?\s+(NAME)\b"#,
    ].compactMap { try? NSRegularExpression(pattern: $0.replacingOccurrences(of: "NAME", with: nameCore)) }
    + [
        // Single-word counterparty after UPI-/IMPS-: "UPI-SHANAWAZ-9876@ybl", "IMPS-P2A-VIDYANAND-"
        // (HDFC and SBI print only the beneficiary's registered name, often one word).
        // Captures one 4+ letter word optionally followed by up to three more words; `nameCore`
        // above requires at least two words, so this pattern exists specifically for the one-word case.
        #"\b(?:UPI|IMPS)[-/](?:P2[APM][-/])?([A-Z]{4,}(?:\s[A-Z]{2,}){0,3})(?=\s*[-/@]|\s*$)"#,
        // Relation lines on ID documents: "S/O: Mahendra Singh Rathore", "W/O Sunita Devi", "C/O ..."
        // Son/Daughter/Wife/Care/Husband of. The captured name may be Title Case (2-4 words,
        // `[A-Z][a-z]+`) or ALL CAPS (2-4 words, `[A-Z]{2,}`); mixed casing is not accepted.
        #"\b(?:S/O|D/O|W/O|C/O|H/O|Son of|Daughter of|Wife of|Care of)\s*:?\s+((?:[A-Z][a-z]+\.?\s+){1,3}[A-Z][a-z]+|(?:[A-Z]{2,}\s+){1,3}[A-Z]{2,})"#,
        // "Name: Ananya Krishnan" / "Customer Name : RAHUL SHARMA" / "Employee Name: ..."
        // Same Title Case / ALL CAPS name body as above, after an optional qualifier and "Name:".
        #"\b(?:Employee |Customer |Account Holder |Applicant |Beneficiary |Nominee )?Name\s*:\s*((?:[A-Z][a-z]+\.?\s+){1,3}[A-Z][a-z]+|(?:[A-Z]{2,}\s+){1,3}[A-Z]{2,})"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    /// Runs every template and emits a `.person` entity per distinct captured name span.
    ///
    /// Score `0.92` is above NLTagger's `0.85`: when both fire on the same text the template
    /// match wins, because the template has already proven the surrounding structure.
    ///
    /// - Parameter text: Full statement text (or a single narration).
    /// - Returns: Person entities, deduplicated by exact range.
    public func recognize(in text: String) -> [PIIEntity] {
        var out: [PIIEntity] = []
        // Several templates can capture the same span (e.g. the UPI two-word template and the
        // UPI single-word template on "UPI-PRIYA MEHTA-..."); `seen` suppresses the duplicate.
        var seen = Set<Range<String.Index>>()
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        for regex in Self.patterns {
            for m in regex.matches(in: text, range: full) {
                // First non-empty capture group is the name.
                // (Only the BY/TO TRANSFER | TRF pattern has more than one group.)
                for g in 1..<m.numberOfRanges {
                    let r = m.range(at: g)
                    guard r.location != NSNotFound, r.length > 0 else { continue }
                    // A span that trims to nothing usable, or one already emitted, ends this match.
                    guard let span = Self.trimStopWords(r, in: text), !seen.contains(span) else { break }
                    seen.insert(span)
                    out.append(PIIEntity(type: .person, text: String(text[span]), range: span, score: 0.92))
                    break
                }
            }
        }
        return out
    }

    /// Drops leading/trailing stop words (e.g. "SALARY", "LTD") and rejects spans with no name words left.
    ///
    /// Steps:
    ///   1. Split the captured span on spaces.
    ///   2. Pop stop words off both ends (`"TCS LTD SALARY"` -> `"TCS"` after trailing pops;
    ///      `"PAYMENT PRIYA MEHTA"` -> `"PRIYA MEHTA"` after leading pops).
    ///   3. Require 2+ words, or a single word of 4+ letters (single registered names).
    ///   4. Reject if any stop word remains *inside* the span (`"ANIL BANK KUMAR"`, `"PRIYA PVT MEHTA"`):
    ///      that marks an organisation or boilerplate line rather than a person.
    ///   5. Locate the trimmed text inside the original span to produce the narrowed range.
    ///
    /// - Parameters:
    ///   - r: Capture-group range (UTF-16) from the regex match.
    ///   - text: The scanned text.
    /// - Returns: The narrowed `String.Index` range, or `nil` if nothing name-like remains.
    static func trimStopWords(_ r: NSRange, in text: String) -> Range<String.Index>? {
        guard var range = Range(r, in: text) else { return nil }
        var words = text[range].split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var leading = 0, trailing = 0
        // Dots are removed so "SMT." and "LTD." compare equal to their stop-word forms.
        func isStop(_ w: String) -> Bool { stopWords.contains(w.replacingOccurrences(of: ".", with: "").uppercased()) }
        while let f = words.first, isStop(f) { words.removeFirst(); leading += 1 }
        while let l = words.last, isStop(l) { words.removeLast(); trailing += 1 }
        // One word is acceptable when it is long enough to be a name (HDFC/SBI print single registered names).
        guard words.count >= 2 || (words.count == 1 && words[0].count >= 4) else { return nil }
        // Any remaining stop word inside (e.g. "TCS LTD SALARY") means this is an organisation line, not a person.
        if words.contains(where: isStop) { return nil }
        // Recompute range without the trimmed words.
        // Searching for the re-joined string within the original span (rather than arithmetic on
        // word offsets) stays correct when the original had runs of multiple spaces.
        let joined = words.joined(separator: " ")
        guard let sub = text.range(of: joined, range: range) else { return nil }
        range = sub
        return range
    }
}
