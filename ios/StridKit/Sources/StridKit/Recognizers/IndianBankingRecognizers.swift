import Foundation

/// All Indian banking PII regex recognizers.
public enum IndianBankingRecognizers {
    public static func all() -> [Recognizer] {
        [
            bankAccount, ifsc, pan, aadhaar, upiID, micr, phone,
            pinCode, customerID, branchCode, txnRef, dob, creditCard, ipAddress,
            maskedCard, alphaTxnRef, NarrationRecognizer(), IndianPlaceRecognizer(),
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
        contextBoost: 0.45,
        validator: { Checksums.verhoeff(Checksums.digitsOnly($0)) },
        validatedScore: 0.8
    )

    /// UPI ID: vpa@bankhandle patterns
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
    public static let micr = RegexRecognizer(
        entityType: .inMICR,
        patterns: [#"\b\d{9}\b"#],
        baseScore: 0.3,
        contextWords: ["micr", "cheque", "check"],
        contextBoost: 0.6,
        contextWindow: 30
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
        contextWords: ["branch code", "branch no", "br code", "br. code"],
        contextBoost: 0.45,
        contextWindow: 25,
        contextAfter: 5
    )

    /// Transaction references: 12-20 digit numbers
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
    public static let maskedCard = RegexRecognizer(
        entityType: .creditCard,
        patterns: [#"\b\d{4,6}[\sXx*\-]{4,14}\d{4}\b"#],
        baseScore: 0.75,
        contextWords: ["card", "atm", "pos", "debit", "credit"]
    )

    /// Alphanumeric transaction references: UTR / RRN / cheque / loan refs like N245251234567, S98765432, HL6001234
    public static let alphaTxnRef = RegexRecognizer(
        entityType: .inTxnRef,
        patterns: [
            #"\b[A-Z]{1,4}\d{7,16}\b"#,
            #"\b[A-Z]{4}[A-Z0-9]\d{11,}\b"#,
        ],
        baseScore: 0.45,
        contextWords: ["ref", "reference", "utr", "rrn", "txn", "transaction", "chq", "cheque", "neft", "imps", "rtgs", "upi"],
        contextBoost: 0.3
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
