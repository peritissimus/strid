import Foundation

/// Post-detection filters that remove obvious false positives from model-based recognizers.
public enum EntityFilters {
    /// Field labels and table headers that NLTagger likes to tag as names, places or organisations.
    static let labels: Set<String> = [
        "ifsc", "micr", "pan", "upi", "dob", "ref", "ref no", "utr", "rrn", "a/c", "ac", "acct", "cif",
        "name", "date", "amount", "balance", "narration", "description", "debit", "credit", "withdrawal", "deposit",
        "particulars", "value date", "chq", "cheque", "branch", "customer id", "account no", "statement",
        "total", "opening balance", "closing balance", "page", "neft", "imps", "rtgs", "atm", "pos", "emi",
        "salary", "ltd", "pvt", "limited", "india", "gst", "tds", "nominee", "mobile", "email", "phone", "address",
        "period", "from", "to", "of", "the", "and", "for", "mr", "mrs", "ms", "shri", "smt",
    ]

    public static func apply(_ entities: [PIIEntity]) -> [PIIEntity] {
        entities.filter { e in
            let t = e.text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            let lower = t.lowercased()
            switch e.type {
            case .person, .location, .organization:
                if labels.contains(lower) { return false }
                // Single short token is almost never a usable name/place.
                if !t.contains(" ") && t.count <= 3 { return false }
                // No letters at all.
                if t.rangeOfCharacter(from: .letters) == nil { return false }
                return true
            case .inBranchCode:
                // Pure alphabetic 4-6 char "codes" are labels (IFSC, MICR) not branch codes.
                return t.rangeOfCharacter(from: .decimalDigits) != nil
            default:
                return true
            }
        }
    }
}
