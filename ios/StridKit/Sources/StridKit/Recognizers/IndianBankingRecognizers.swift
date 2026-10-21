//
// IndianBankingRecognizers.swift
// StridKit
//
// Declarative catalogue of every `RegexRecognizer` the engine uses, plus the two non-regex
// recognizers (`NarrationRecognizer`, `IndianPlaceRecognizer`) that round out Indian banking
// coverage. `StridEngine.init` appends `all()` to the NLTagger and NSDataDetector recognizers.
//
// Scoring philosophy, relative to the default engine threshold of 0.5:
//
//   - Shapes that are unambiguous on their own (IFSC, PAN, IPv4) start at 0.85-0.9 and need no
//     context.
//   - Shapes that are just "N digits" (account, MICR, customer ID, PIN) start at 0.2-0.3, *below*
//     threshold, and only surface when a context word (`a/c no`, `micr`, `cust id`, a city name)
//     appears nearby.
//   - Shapes with a checksum (Aadhaar via Verhoeff, cards via Luhn) start low but jump to
//     0.8-0.95 when the checksum passes, and are dropped entirely when it fails.
//
// Overlaps between these (a 12-digit run is simultaneously a candidate txn ref, Aadhaar, phone
// and account) are intentional; `StridEngine.deduplicateOverlaps` keeps the highest score.
//
import Foundation

/// All Indian banking PII regex recognizers.
public enum IndianBankingRecognizers {
    /// Every recognizer in this file, in the order they are registered with the engine.
    /// Order has no effect on results.
    public static func all() -> [Recognizer] {
        [
            bankAccount, ifsc, pan, aadhaar, upiID, micr, phone,
            pinCode, customerID, branchCode, txnRef, dob, creditCard, ipAddress,
            maskedCard, alphaTxnRef, NarrationRecognizer(), IndianPlaceRecognizer(),
        ]
    }

    // MARK: - Indian Banking

    /// Bank account numbers: 9-18 digits near account context
    ///
    /// Pattern `\b\d{9,18}\b`: any word-bounded run of 9 to 18 digits, e.g. `50100123456789`.
    /// Base 0.3 is below threshold; the 0.4 context boost ("account no", "a/c") lifts it to 0.7.
    /// Without context, a bare digit run is left to the txn-ref / phone / Aadhaar recognizers.
    public static let bankAccount = RegexRecognizer(
        entityType: .inBankAccount,
        patterns: [#"\b\d{9,18}\b"#],
        baseScore: 0.3,
        contextWords: [
            "account", "a/c", "acc", "acct", "bank account", "saving", "current",
            "account number", "account no", "acc no", "a/c no",
        ],
        contextBoost: 0.4
    )

    /// IFSC: 4 letters + 0 + 6 alphanumeric (e.g., HDFC0001234)
    ///
    /// Pattern `\b[A-Z]{4}0[A-Z0-9]{6}\b`: the RBI-mandated format is 4-letter bank code,
    /// a reserved `0`, then a 6-character branch code. Shape alone is strong evidence (0.85);
    /// context ("ifsc", "neft") takes it to 1.0 via the default 0.35 boost.
    public static let ifsc = RegexRecognizer(
        entityType: .inIFSC,
        patterns: [#"\b[A-Z]{4}0[A-Z0-9]{6}\b"#],
        baseScore: 0.85,
        contextWords: ["ifsc", "branch", "bank", "neft", "rtgs", "imps", "rtgs/neft"]
    )

    /// PAN: 5 letters + 4 digits + 1 letter (e.g., ABCDE1234F)
    ///
    /// Pattern `\b[A-Z]{5}\d{4}[A-Z]\b`. The fourth letter encodes holder type (P = person,
    /// C = company, ...) and the fifth is the surname initial, but the regex does not enforce
    /// that; the 10-character shape is rare enough in text to score 0.85 on its own.
    public static let pan = RegexRecognizer(
        entityType: .inPAN,
        patterns: [#"\b[A-Z]{5}\d{4}[A-Z]\b"#],
        baseScore: 0.85,
        contextWords: ["pan", "permanent account", "tax", "income tax", "pan card", "pan no"]
    )

    /// Aadhaar: 12 digits, optionally spaced as XXXX XXXX XXXX
    ///
    /// Pattern `\b[2-9]\d{3}\s?\d{4}\s?\d{4}\b`: UIDAI never issues numbers starting with 0 or 1,
    /// so the first digit is restricted; groups may be separated by a single space, as printed on
    /// the card (`2345 6789 0123`). The Verhoeff validator (see `Checksums.verhoeff`) rejects
    /// ~90% of random 12-digit runs; a passing number scores 0.8, and 1.0 with "aadhaar"/"uid"
    /// context. A failing checksum drops the match so the txn-ref recognizer can claim it instead.
    public static let aadhaar = RegexRecognizer(
        entityType: .inAadhaar,
        patterns: [#"\b[2-9]\d{3}\s?\d{4}\s?\d{4}\b"#],
        baseScore: 0.4,
        contextWords: ["aadhaar", "aadhar", "uid", "uidai", "unique id", "aadhaar no"],
        contextBoost: 0.45,
        validator: { Checksums.verhoeff(Checksums.digitsOnly($0)) },
        validatedScore: 0.8
    )

    /// UPI ID: vpa@bankhandle patterns
    ///
    /// Two patterns, both `local-part@handle` where the local part is word chars and dots
    /// (`priya.mehta`, `9876501234`):
    ///   1. A closed list of known PSP / bank handles (`@oksbi`, `@ybl`, `@paytm`, `@axl`, ...).
    ///      Both patterns share the 0.5 base score; the first is simply far less likely to
    ///      false-positive because the handle list is specific.
    ///   2. Any 2-20 letter handle (`name@word`), a fallback for handles not in the list. This
    ///      also matches email addresses, but `.email` from NSDataDetector scores 1.0 and wins
    ///      the overlap, so email-looking strings are not misreported as UPI IDs.
    /// Context ("upi", "vpa", "paid") adds 0.4, lifting either shape to 0.9.
    public static let upiID = RegexRecognizer(
        entityType: .inUPIID,
        patterns: [
            // Known bank handles
            #"[\w.]+@(?:ok(?:sbi|icici|axis|hdfc)|ybl|paytm|upi|apl|ibl|axl|kmbl|barodampay|freecharge|okhdfcbank|ikwik|mahb|indus|sbi|icici|hdfcbank|axisbank|kotak|rbl|federal|idbi|bandhan|pnb|bob|canarabank|indianbank|iob|uboi|unionbankofindia|rxairtel|airtel|jio|slice|cred|jupiter|fi|niyobank|dbs|scb|citi|hsbc|sc|equitas|au0101)\b"#,
            // Generic word@word in UPI context
            #"[\w.]+@[A-Za-z]{2,20}\b"#,
        ],
        baseScore: 0.5,
        contextWords: ["upi", "vpa", "payment", "transfer", "paid", "upi-", "neft", "imps"],
        contextBoost: 0.4
    )

    /// MICR: 9 digits near MICR context
    ///
    /// Pattern `\b\d{9}\b`: a 9-digit MICR code (city-bank-branch, 3 digits each) such as
    /// `400240002`. Nine digits is also a plausible phone fragment or account number, so the
    /// base is 0.3 and only a tight window (30 chars) containing "micr"/"cheque" boosts it, by
    /// a large 0.6 to 0.9 so it beats the 0.75 NSDataDetector phone on the same span.
    public static let micr = RegexRecognizer(
        entityType: .inMICR,
        patterns: [#"\b\d{9}\b"#],
        baseScore: 0.3,
        contextWords: ["micr", "cheque", "check"],
        contextBoost: 0.6,
        contextWindow: 30
    )

    /// Indian phone: +91 or 0 prefix, 10 digits
    ///
    /// Patterns:
    ///   1. `(?:\+91[\s\-]?)?[6-9]\d{4}[\s\-]?\d{5}\b`: optional `+91` (with optional space or
    ///      hyphen), then a 10-digit mobile number starting 6-9, optionally split 5+5
    ///      (`+91 98765 43210`, `9876543210`). No leading `\b` so that `+91` is captured.
    ///   2. `\b0[6-9]\d{4}[\s\-]?\d{5}\b`: the same with a `0` trunk prefix (`09876543210`).
    /// Base 0.6 already clears the threshold; "mobile"/"phone" context lifts it to 0.95.
    public static let phone = RegexRecognizer(
        entityType: .inPhone,
        patterns: [
            #"(?:\+91[\s\-]?)?[6-9]\d{4}[\s\-]?\d{5}\b"#,
            #"\b0[6-9]\d{4}[\s\-]?\d{5}\b"#,
        ],
        baseScore: 0.6,
        contextWords: ["phone", "mobile", "mob", "cell", "contact", "tel", "call", "sms", "whatsapp", "phone no"]
    )

    /// PIN code: 6 digits (postal)
    ///
    /// Pattern `\b[1-9]\d{5}\b`: Indian PIN codes never start with 0. Six digits is an extremely
    /// common shape (amounts, OTPs, partial references), hence the 0.3 base and a deliberately
    /// broad context vocabulary: explicit labels ("pin code"), address nouns ("nagar", "road",
    /// "society"), major city names, and state names. The window is asymmetric: 60 chars before
    /// (where the street and city sit) and 20 after (where "India" or a phone label might sit).
    public static let pinCode = RegexRecognizer(
        entityType: .inPINCode,
        patterns: [#"\b[1-9]\d{5}\b"#],
        baseScore: 0.3,
        contextWords: [
            "pin", "pincode", "pin code", "postal", "zip", "post office", "sector", "city", "address",
            "road", "nagar", "marg", "street", "lane", "colony", "apartments", "residency", "society", "layout",
            "mumbai", "delhi", "bengaluru", "bangalore", "chennai", "kolkata", "hyderabad", "pune", "ahmedabad",
            "jaipur", "lucknow", "surat", "kanpur", "nagpur", "indore", "bhopal", "patna", "kochi", "goa", "noida", "gurugram", "gurgaon",
            "maharashtra", "karnataka", "tamil nadu", "kerala", "gujarat", "rajasthan", "uttar pradesh", "west bengal",
            "telangana", "andhra pradesh", "madhya pradesh", "bihar", "punjab", "haryana", "odisha", "assam", "jharkhand",
            "chhattisgarh", "uttarakhand", "himachal", "delhi",
        ],
        contextBoost: 0.4,
        contextWindow: 60,
        contextAfter: 20
    )

    /// Customer ID (CIF): 7-11 digits near customer context
    ///
    /// Pattern `\b\d{7,11}\b`. Only meaningful next to "customer id" / "cif" / "client id";
    /// the 0.5 boost takes 0.3 to 0.8 so it outranks a bare bank-account or txn-ref match.
    public static let customerID = RegexRecognizer(
        entityType: .inCustomerID,
        patterns: [#"\b\d{7,11}\b"#],
        baseScore: 0.3,
        contextWords: ["cust id", "customer id", "cif", "cust no", "customer no", "client id"],
        contextBoost: 0.5
    )

    /// Branch code: 4-6 alphanumeric near branch context
    ///
    /// Pattern `\b[A-Z0-9]{4,6}\b`: very loose (matches "IFSC", "NEFT", "2024"), so the base is
    /// a mere 0.2 and context must be explicit ("branch code", "br. code") and close (25 before,
    /// 5 after, i.e. the code must follow its label). `EntityFilters` further rejects all-letter
    /// matches, which are labels, not codes.
    public static let branchCode = RegexRecognizer(
        entityType: .inBranchCode,
        patterns: [#"\b[A-Z0-9]{4,6}\b"#],
        baseScore: 0.2,
        contextWords: ["branch code", "branch no", "br code", "br. code"],
        contextBoost: 0.45,
        contextWindow: 25,
        contextAfter: 5
    )

    /// Transaction references: 12-20 digit numbers
    ///
    /// Patterns:
    ///   1. `\b\d{12,20}\b`: long numeric refs such as UPI RRNs (`525412345678`) or IMPS refs.
    ///      Overlaps the Aadhaar shape by design; a Verhoeff-valid Aadhaar (0.8) beats this (0.6).
    ///   2. `(?<=[/\-])\d{6,11}\b(?!@)`: a shorter 6-11 digit run that is *preceded* by `/` or
    ///      `-` (lookbehind), as inside narrations like `BIL/ONL/000123456` or `-0012345678`,
    ///      and *not followed* by `@` (negative lookahead) so the numeric local part of a UPI ID
    ///      (`-9876501234@ybl`) is left to the UPI recognizer.
    /// Base 0.6 clears the threshold unaided; "ref"/"utr"/"chq" context lifts to 0.95.
    public static let txnRef = RegexRecognizer(
        entityType: .inTxnRef,
        patterns: [
            #"\b\d{12,20}\b"#,
            // Slash/hyphen-delimited refs inside narrations: BIL/ONL/000123456, NEFT/N2452.../, -0012345678
            #"(?<=[/\-])\d{6,11}\b(?!@)"#,
        ],
        baseScore: 0.6,
        contextWords: [
            "ref", "ref no", "reference", "chq", "cheque", "txn", "transaction",
            "utr", "rrn", "chq./ref.no", "ref.no", "upi", "imps", "neft", "rtgs", "narration", "emi", "loan",
        ]
    )

    /// Date of birth: dates only near birth context (not transaction dates)
    ///
    /// Patterns:
    ///   1. `\b\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}\b`: numeric dates with `/`, `-` or `.`
    ///      separators (`12/03/1990`, `1-3-90`, `12.03.1990`).
    ///   2. `\b\d{1,2}\s+(?:Jan(?:uary)?|...|Dec(?:ember)?)\s+\d{2,4}\b`: day, English month
    ///      name (abbreviated or full), year (`12 March 1990`, `3 Mar 90`).
    /// A bank statement is full of dates, so the base is 0.3 and the window is tight (20 before,
    /// 3 after): only a date immediately following "DOB"/"Date of Birth" is promoted, to 0.85.
    public static let dob = RegexRecognizer(
        entityType: .inDOB,
        patterns: [
            #"\b\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}\b"#,
            #"\b\d{1,2}\s+(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{2,4}\b"#,
        ],
        baseScore: 0.3,
        contextWords: ["birth", "dob", "born", "date of birth", "d.o.b", "d/o/b", "birthday"],
        contextBoost: 0.55,
        contextWindow: 20,
        contextAfter: 3
    )

    // MARK: - Universal (regex-based)

    /// Credit card numbers: 13-19 digits with separators (dashes/spaces required to distinguish from plain numbers)
    ///
    /// Patterns:
    ///   1. `\b\d{4}[\s\-]\d{4}[\s\-]\d{4}[\s\-]\d{1,7}\b`: three 4-digit groups then a final
    ///      group of 1-7 digits, separated by a space or hyphen (`4111 1111 1111 1111`,
    ///      `3782-8224-6310-005`). Covers 13 to 19 digit PANs in the common grouped layout.
    ///   2. `\b\d{16}\b`: an unseparated 16-digit run.
    /// Both are subject to the Luhn validator (`Checksums.luhn`): a match that fails is dropped,
    /// which is what stops ordinary 16-digit account numbers from being reported as cards. A
    /// passing match scores 0.95, which beats every other numeric recognizer on that span.
    public static let creditCard = RegexRecognizer(
        entityType: .creditCard,
        patterns: [
            // With separators (high confidence)
            #"\b\d{4}[\s\-]\d{4}[\s\-]\d{4}[\s\-]\d{1,7}\b"#,
            // Unseparated 16 digits (validated by Luhn so plain account numbers do not match)
            #"\b\d{16}\b"#,
        ],
        baseScore: 0.5,
        contextWords: ["credit card", "card", "visa", "mastercard", "amex", "debit", "pos"],
        validator: { Checksums.luhn(Checksums.digitsOnly($0)) },
        validatedScore: 0.95
    )

    /// Masked card numbers as printed in statements: 4567XXXXXXXX8901, 4567 **** **** 8901
    ///
    /// Pattern `\b\d{4,6}[\sXx*\-]{4,14}\d{4}\b`: a leading BIN of 4-6 digits, a masked middle
    /// made of 4-14 `X`/`x`/`*`/space/hyphen characters, and the trailing 4 digits. The first and
    /// last four digits are still identifying (and the last four are what fraud checks ask for),
    /// so they are redacted. No Luhn possible; shape scores 0.75, context takes it to 1.0.
    public static let maskedCard = RegexRecognizer(
        entityType: .creditCard,
        patterns: [#"\b\d{4,6}[\sXx*\-]{4,14}\d{4}\b"#],
        baseScore: 0.75,
        contextWords: ["card", "atm", "pos", "debit", "credit"]
    )

    /// Alphanumeric transaction references: UTR / RRN / cheque / loan refs like N245251234567, S98765432, HL6001234
    ///
    /// Patterns:
    ///   1. `\b[A-Z]{1,4}\d{7,16}\b`: 1-4 capital letters then 7-16 digits. NEFT UTRs
    ///      (`N245251234567`), SBI refs (`S98765432`), loan account refs (`HL6001234`).
    ///   2. `\b[A-Z]{4}[A-Z0-9]\d{11,}\b`: bank-code prefixed refs where a fifth character may
    ///      be a letter, e.g. `HDFCN52024010112345` (4 letters, `N`, 11+ digits).
    ///   3. The merchant / gateway blob. Reading the lookaheads left to right:
    ///        `(?=[A-Za-z0-9.\-]{7,}\b)`         at least 7 chars of letters/digits/`.`/`-` ahead
    ///        `(?=(?:[A-Za-z.\-]*\d){4})`        at least 4 digits somewhere in that run
    ///        `(?=(?:[\d.\-]*[A-Za-z]){2})`      at least 2 letters somewhere in that run
    ///      then the run itself, which must start and end on a letter or digit. Matches things
    ///      like `RZP2024ABC123`, `pay_MkL9x2Q-7a3b` style gateway refs and `AMZN.IN.4821` style
    ///      merchant refs, while a plain word (no digits) or a plain number (no letters) fails.
    ///   4. `\b[A-Z]{4,6}[A-Z]?\d{2,6}\b(?=[ \t]*(?:\n|$))`: a bank-ish prefix (4-6 capitals,
    ///      optional extra letter) followed by only 2-6 digits, and then nothing but spaces to the
    ///      end of the line. This is the *head* of a reference that PDF extraction wrapped onto the
    ///      next line (`IDFBH260` + newline + `12345678`); `StridEngine.extendAcrossWraps` later
    ///      grows it over the tail.
    /// Base 0.45 is just under threshold; the 0.3 context boost ("utr", "neft", "ref") is needed
    /// for a bare match to be reported, which keeps model numbers and invoice codes in prose out.
    public static let alphaTxnRef = RegexRecognizer(
        entityType: .inTxnRef,
        patterns: [
            #"\b[A-Z]{1,4}\d{7,16}\b"#,
            #"\b[A-Z]{4}[A-Z0-9]\d{11,}\b"#,
            // Merchant / gateway reference blobs: 7+ chars of [A-Z0-9.-], at least 4 digits and 2 letters.
            #"\b(?=[A-Za-z0-9.\-]{7,}\b)(?=(?:[A-Za-z.\-]*\d){4})(?=(?:[\d.\-]*[A-Za-z]){2})[A-Za-z0-9][A-Za-z0-9.\-]*[A-Za-z0-9]\b"#,
            // Bank-prefixed refs with few digits (the head of a wrapped NEFT/IMPS ref): IDFBH260, HDFCN5..
            #"\b[A-Z]{4,6}[A-Z]?\d{2,6}\b(?=[ \t]*(?:\n|$))"#,
        ],
        baseScore: 0.45,
        contextWords: ["ref", "reference", "utr", "rrn", "txn", "transaction", "chq", "cheque", "neft", "imps", "rtgs", "upi"],
        contextBoost: 0.3
    )

    /// IP addresses: IPv4
    ///
    /// Pattern: four dot-separated octets, each constrained to 0-255 by the alternation
    /// `25[0-5] | 2[0-4]\d | [01]?\d\d?` (250-255, 200-249, 0-199). Rejects `999.1.1.1`.
    /// Scores 0.9 with no context; IPv6 is not handled.
    public static let ipAddress = RegexRecognizer(
        entityType: .ipAddress,
        patterns: [
            #"\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b"#,
        ],
        baseScore: 0.9
    )
}
