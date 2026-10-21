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
    private static let nameCore = #"(?:[A-Z]{2,}(?:\.?\s+|\.)){1,3}[A-Z]{2,}\.?|[A-Z]{2,}(?:\s+[A-Z]\.?){1,2}"#

    private static let patterns: [NSRegularExpression] = [
        // UPI-NAME-vpa  /  UPI/ref/NAME/  /  UPI-NAME@... (name precedes a VPA or separator)
        #"\bUPI[-/ ](?:\w{6,}[-/])?(NAME)(?=\s*[-/@]|\s*$)"#,
        // IMPS-P2A-NAME-  /  IMPS/P2P/ref/NAME
        #"\bIMPS[-/ ](?:P2[APM][-/])?(?:\w{6,}[-/])?(NAME)(?=\s*[-/]|\s*$)"#,
        // NEFT CR-IFSC-NAME-ref  /  NEFT-ref-NAME  /  RTGS ...
        #"\b(?:NEFT|RTGS)[-/ ](?:CR|DR)?[-/ ]?(?:[A-Z]{4}0[A-Z0-9]{6}[-/])?(?:\w{6,}[-/])?(NAME)(?=\s*[-/]|\s*$)"#,
        // CHQ DEP 000123 NAME  /  CHQ PAID NAME  /  CHQ NO 123 NAME
        #"\bCHQ(?:\s+(?:DEP|PAID|NO|ISSUED))?\s+(?:\d+\s+)?(NAME)\b"#,
        // BY TRANSFER-NAME  /  TO TRANSFER-NAME  /  TRF TO NAME  /  TRF FROM NAME
        #"\b(?:BY|TO)\s+TRANSFER[-/ ](NAME)\b|\bTRF\s+(?:TO|FROM)\s+(NAME)\b"#,
        // Honorifics
        #"\b(?:MR|MRS|MS|SHRI|SMT|KUMARI|DR)\.?\s+(NAME)\b"#,
    ].compactMap { try? NSRegularExpression(pattern: $0.replacingOccurrences(of: "NAME", with: nameCore)) }
    + [
        // Relation lines on ID documents: "S/O: Mahendra Singh Rathore", "W/O Sunita Devi", "C/O ..."
        #"\b(?:S/O|D/O|W/O|C/O|H/O|Son of|Daughter of|Wife of|Care of)\s*:?\s+((?:[A-Z][a-z]+\.?\s+){1,3}[A-Z][a-z]+|(?:[A-Z]{2,}\s+){1,3}[A-Z]{2,})"#,
        // "Name: Ananya Krishnan" / "Customer Name : RAHUL SHARMA" / "Employee Name: ..."
        #"\b(?:Employee |Customer |Account Holder |Applicant |Beneficiary |Nominee )?Name\s*:\s*((?:[A-Z][a-z]+\.?\s+){1,3}[A-Z][a-z]+|(?:[A-Z]{2,}\s+){1,3}[A-Z]{2,})"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    public func recognize(in text: String) -> [PIIEntity] {
        var out: [PIIEntity] = []
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        for regex in Self.patterns {
            for m in regex.matches(in: text, range: full) {
                // First non-empty capture group is the name.
                for g in 1..<m.numberOfRanges {
                    let r = m.range(at: g)
                    guard r.location != NSNotFound, r.length > 0 else { continue }
                    guard let span = Self.trimStopWords(r, in: text) else { break }
                    out.append(PIIEntity(type: .person, text: String(text[span]), range: span, score: 0.92))
                    break
                }
            }
        }
        return out
    }

    /// Drops leading/trailing stop words (e.g. "SALARY", "LTD") and rejects spans with no name words left.
    static func trimStopWords(_ r: NSRange, in text: String) -> Range<String.Index>? {
        guard var range = Range(r, in: text) else { return nil }
        var words = text[range].split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var leading = 0, trailing = 0
        func isStop(_ w: String) -> Bool { stopWords.contains(w.replacingOccurrences(of: ".", with: "").uppercased()) }
        while let f = words.first, isStop(f) { words.removeFirst(); leading += 1 }
        while let l = words.last, isStop(l) { words.removeLast(); trailing += 1 }
        guard words.count >= 2 || (words.count == 1 && words[0].count >= 4 && leading + trailing > 0) else { return nil }
        // Any remaining stop word inside (e.g. "TCS LTD SALARY") means this is an organisation line, not a person.
        if words.contains(where: isStop) { return nil }
        // Recompute range without the trimmed words.
        let joined = words.joined(separator: " ")
        guard let sub = text.range(of: joined, range: range) else { return nil }
        range = sub
        return range
    }
}
