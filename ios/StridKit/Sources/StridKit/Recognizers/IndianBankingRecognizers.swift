import Foundation

/// All Indian banking PII regex recognizers.
public enum IndianBankingRecognizers {
    public static func all() -> [Recognizer] {
        [
            bankAccount, ifsc, pan, aadhaar, upiID, micr, phone,
            pinCode, customerID, branchCode, txnRef, dob, creditCard, ipAddress,
        ]
    }

    // MARK: - Indian Banking

    /// Bank account numbers: 9-18 digits near account context
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
    public static let ifsc = RegexRecognizer(
        entityType: .inIFSC,
        patterns: [#"\b[A-Z]{4}0[A-Z0-9]{6}\b"#],
        baseScore: 0.85,
        contextWords: ["ifsc", "branch", "bank", "neft", "rtgs", "imps", "rtgs/neft"]
    )

    /// PAN: 5 letters + 4 digits + 1 letter (e.g., ABCDE1234F)
    public static let pan = RegexRecognizer(
        entityType: .inPAN,
        patterns: [#"\b[A-Z]{5}\d{4}[A-Z]\b"#],
        baseScore: 0.85,
        contextWords: ["pan", "permanent account", "tax", "income tax", "pan card", "pan no"]
    )

    /// Aadhaar: 12 digits, optionally spaced as XXXX XXXX XXXX
    public static let aadhaar = RegexRecognizer(
        entityType: .inAadhaar,
        patterns: [#"\b[2-9]\d{3}\s?\d{4}\s?\d{4}\b"#],
        baseScore: 0.4,
        contextWords: ["aadhaar", "aadhar", "uid", "uidai", "unique id", "aadhaar no"],
        contextBoost: 0.45
    )

    /// UPI ID: vpa@bankhandle patterns
    public static let upiID = RegexRecognizer(
        entityType: .inUPIID,
        patterns: [
            // Known bank handles
            #"[\w.\-]+@(?:ok(?:sbi|icici|axis|hdfc)|ybl|paytm|upi|apl|ibl|axl|kmbl|barodampay|freecharge|okhdfcbank|ikwik|mahb|indus|sbi|icici|hdfcbank|axisbank|kotak|rbl|federal|idbi|bandhan|pnb|bob|canarabank|indianbank|iob|uboi|unionbankofindia|rxairtel|airtel|jio|slice|cred|jupiter|fi|niyobank|dbs|scb|citi|hsbc|sc|equitas|au0101)\b"#,
            // Generic word@word in UPI context
            #"[\w.\-]+@[A-Za-z]{2,20}\b"#,
        ],
        baseScore: 0.5,
        contextWords: ["upi", "vpa", "payment", "transfer", "paid", "upi-", "neft", "imps"],
        contextBoost: 0.4
    )

    /// MICR: 9 digits near MICR context
    public static let micr = RegexRecognizer(
        entityType: .inMICR,
        patterns: [#"\b\d{9}\b"#],
        baseScore: 0.3,
        contextWords: ["micr", "cheque", "check"],
        contextBoost: 0.5
    )

    /// Indian phone: +91 or 0 prefix, 10 digits
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
    public static let pinCode = RegexRecognizer(
        entityType: .inPINCode,
        patterns: [#"\b[1-9]\d{5}\b"#],
        baseScore: 0.3,
        contextWords: ["pin", "pincode", "pin code", "postal", "zip", "post office", "sector", "city"],
        contextBoost: 0.35
    )

    /// Customer ID (CIF): 7-11 digits near customer context
    public static let customerID = RegexRecognizer(
        entityType: .inCustomerID,
        patterns: [#"\b\d{7,11}\b"#],
        baseScore: 0.3,
        contextWords: ["cust id", "customer id", "cif", "cust no", "customer no", "client id"],
        contextBoost: 0.5
    )

    /// Branch code: 4-6 alphanumeric near branch context
    public static let branchCode = RegexRecognizer(
        entityType: .inBranchCode,
        patterns: [#"\b[A-Z0-9]{4,6}\b"#],
        baseScore: 0.2,
        contextWords: ["branch code", "branch no", "branch"],
        contextBoost: 0.45
    )

    /// Transaction references: 12-20 digit numbers
    public static let txnRef = RegexRecognizer(
        entityType: .inTxnRef,
        patterns: [#"\b\d{12,20}\b"#],
        baseScore: 0.6,
        contextWords: [
            "ref", "ref no", "reference", "chq", "cheque", "txn", "transaction",
            "utr", "rrn", "chq./ref.no", "ref.no",
        ]
    )

    /// Date of birth: dates only near birth context (not transaction dates)
    public static let dob = RegexRecognizer(
        entityType: .inDOB,
        patterns: [
            #"\b\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}\b"#,
            #"\b\d{1,2}\s+(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{2,4}\b"#,
        ],
        baseScore: 0.3,
        contextWords: ["birth", "dob", "born", "date of birth", "d.o.b", "d/o/b", "birthday"],
        contextBoost: 0.55
    )

    // MARK: - Universal (regex-based)

    /// Credit card numbers: 13-19 digits with separators (dashes/spaces required to distinguish from plain numbers)
    public static let creditCard = RegexRecognizer(
        entityType: .creditCard,
        patterns: [
            // With separators (high confidence)
            #"\b\d{4}[\s\-]\d{4}[\s\-]\d{4}[\s\-]\d{1,7}\b"#,
        ],
        baseScore: 0.8,
        contextWords: ["credit card", "card", "visa", "mastercard", "amex", "debit"]
    )

    /// IP addresses: IPv4
    public static let ipAddress = RegexRecognizer(
        entityType: .ipAddress,
        patterns: [
            #"\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b"#,
        ],
        baseScore: 0.9
    )
}
