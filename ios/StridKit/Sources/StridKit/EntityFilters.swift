//
// EntityFilters.swift
// StridKit
//
// First post-processing stage in `StridEngine.detect`, run on the raw union of all recognizer
// output *before* threshold filtering and overlap deduplication. Its job is to throw away the
// systematic false positives that machine-learned taggers (NLTagger) and loose regexes produce on
// Indian bank statements, where column headers and field labels ("IFSC", "Narration", "Shri")
// are capitalised exactly like names.
//
// Everything here is a conservative, type-specific rule; anything not explicitly rejected passes.
//
import Foundation

/// Post-detection filters that remove obvious false positives from model-based recognizers.
public enum EntityFilters {
    /// Field labels and table headers that NLTagger likes to tag as names, places or organisations.
    ///
    /// Compared case-insensitively against the trimmed entity text. The list mixes:
    ///   - banking abbreviations and column headers (`ifsc`, `narration`, `closing balance`),
    ///   - payment rails and channels (`neft`, `imps`, `atm`, `pos`),
    ///   - corporate suffixes that NLTagger emits on their own (`ltd`, `pvt`, `limited`),
    ///   - function words and honorifics that get tagged when they lead a capitalised line
    ///     (`the`, `for`, `mr`, `shri`, `smt`).
    static let labels: Set<String> = [
        "ifsc", "micr", "pan", "upi", "dob", "ref", "ref no", "utr", "rrn", "a/c", "ac", "acct", "cif",
        "name", "date", "amount", "balance", "narration", "description", "debit", "credit", "withdrawal", "deposit",
        "particulars", "value date", "chq", "cheque", "branch", "customer id", "account no", "statement",
        "total", "opening balance", "closing balance", "page", "neft", "imps", "rtgs", "atm", "pos", "emi",
        "salary", "ltd", "pvt", "limited", "india", "gst", "tds", "nominee", "mobile", "email", "phone", "address",
        "period", "from", "to", "of", "the", "and", "for", "mr", "mrs", "ms", "shri", "smt",
        // Invoice vocabulary: NLTagger reads these headings as organisations.
        "invoice", "tax invoice", "invoice value", "invoice number", "invoice details", "invoice date",
        "order number", "order date", "bill of supply", "cash memo", "amount in words", "sold by",
        "billing address", "shipping address", "place of supply", "place of delivery", "authorized signatory",
        "authorised signatory", "mode of payment", "credit card", "debit card", "net banking", "shipping charges",
        "cgst", "sgst", "igst", "hsn", "qty", "unit price", "net amount", "tax rate", "tax type", "tax amount",
        "total amount", "state/ut code", "reverse charge", "payment transaction id", "original for recipient",
    ]

    /// Household-name merchants, banks and agencies. Their names and bare domains identify the
    /// counterparty, not the customer, and blacking them out is what makes a redacted invoice
    /// look broken. Matched case-insensitively against the whole entity text.
    static let publicOrganisations: Set<String> = [
        "amazon", "amazon.in", "amazon.com", "amazon seller services", "amazon retail india", "flipkart", "myntra",
        "ajio", "meesho", "nykaa", "bigbasket", "blinkit", "zepto", "swiggy", "zomato", "uber", "ola", "rapido",
        "irctc", "makemytrip", "goibibo", "cleartrip", "redbus", "indigo", "air india", "vistara",
        "hdfc", "hdfc bank", "icici", "icici bank", "sbi", "state bank of india", "axis bank", "kotak",
        "kotak mahindra bank", "yes bank", "idfc first bank", "indusind bank", "punjab national bank", "bank of baroda",
        "canara bank", "union bank of india", "paytm", "phonepe", "google pay", "gpay", "bhim", "cred", "razorpay",
        "lic", "uidai", "nsdl", "income tax department", "reserve bank of india", "rbi", "epfo", "sebi",
        "apple", "google", "microsoft", "netflix", "spotify", "jio", "airtel", "vi", "bsnl", "tata", "reliance",
    ]

    /// Drops entities that match a known false-positive shape for their type.
    ///
    /// - Parameter entities: Raw recognizer output, possibly overlapping.
    /// - Returns: The same entities minus the rejected ones, order preserved.
    public static func apply(_ entities: [PIIEntity]) -> [PIIEntity] {
        entities.filter { e in
            // Strip surrounding whitespace and punctuation so "IFSC:" and "(Ltd)" compare cleanly.
            let t = e.text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            let lower = t.lowercased()
            switch e.type {
            case .person, .location, .organization:
                // Model-derived name-like types: reject known labels outright.
                if labels.contains(lower) { return false }
                // Counterparty brands are not the customer's PII.
                if e.type == .organization, publicOrganisations.contains(lower) { return false }
                // Single short token is almost never a usable name/place.
                // ("Raj" would be lost here, but so would hundreds of "Dr", "Sr", "No" tags.)
                if !t.contains(" ") && t.count <= 3 { return false }
                // No letters at all.
                // NLTagger occasionally tags a bare number or symbol run as an organisation.
                if t.rangeOfCharacter(from: .letters) == nil { return false }
                return true
            case .inBranchCode:
                // Pure alphabetic 4-6 char "codes" are labels (IFSC, MICR) not branch codes.
                // The branch-code regex is `[A-Z0-9]{4,6}`, which happily matches the *word* "IFSC"
                // sitting right next to "branch code"; a real branch code always has a digit.
                return t.rangeOfCharacter(from: .decimalDigits) != nil
            case .url:
                // A brand's bare domain ("amazon.in", "Amazon.in/business") identifies the merchant,
                // not the person. URLs with a query string or a user-ish path segment are kept.
                let host = lower.replacingOccurrences(of: #"^https?://(www\.)?"#, with: "", options: .regularExpression)
                    .split(separator: "/").first.map(String.init) ?? lower
                let pathDepth = lower.split(separator: "/").count - (lower.hasPrefix("http") ? 3 : 1)
                return !(publicOrganisations.contains(host) && pathDepth <= 1 && !lower.contains("?"))
            default:
                // Structured identifiers (PAN, IFSC, Aadhaar, ...) are governed by their own regex
                // shapes, validators and context scoring; no generic filtering applies.
                return true
            }
        }
    }
}
