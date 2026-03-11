"""Custom Presidio recognizers for Indian banking PII."""

from presidio_analyzer import Pattern, PatternRecognizer


# Indian bank account numbers: 9-18 digits, sometimes grouped with spaces/hyphens
IN_BANK_ACCOUNT = PatternRecognizer(
    supported_entity="IN_BANK_ACCOUNT",
    name="Indian Bank Account Recognizer",
    patterns=[
        Pattern(
            name="in_bank_account",
            regex=r"\b\d{9,18}\b",
            score=0.3,
        ),
    ],
    context=[
        "account", "a/c", "acc", "acct", "bank account", "saving", "current",
        "account number", "account no", "acc no", "a/c no", "account no",
    ],
)

# IFSC Code: 4 letters + 0 + 6 alphanumeric (e.g., SBIN0012345, HDFC0001234)
IN_IFSC = PatternRecognizer(
    supported_entity="IN_IFSC",
    name="Indian IFSC Code Recognizer",
    patterns=[
        Pattern(
            name="in_ifsc",
            regex=r"\b[A-Z]{4}0[A-Z0-9]{6}\b",
            score=0.85,
        ),
    ],
    context=["ifsc", "branch", "bank", "neft", "rtgs", "imps", "rtgs/neft"],
)

# PAN: 5 letters + 4 digits + 1 letter (e.g., ABCDE1234F)
IN_PAN = PatternRecognizer(
    supported_entity="IN_PAN",
    name="Indian PAN Recognizer",
    patterns=[
        Pattern(
            name="in_pan",
            regex=r"\b[A-Z]{5}\d{4}[A-Z]\b",
            score=0.85,
        ),
    ],
    context=["pan", "permanent account", "tax", "income tax", "pan card", "pan no"],
)

# Aadhaar: 12 digits, often spaced as XXXX XXXX XXXX
IN_AADHAAR = PatternRecognizer(
    supported_entity="IN_AADHAAR",
    name="Indian Aadhaar Recognizer",
    patterns=[
        Pattern(
            name="in_aadhaar_spaced",
            regex=r"\b[2-9]\d{3}\s?\d{4}\s?\d{4}\b",
            score=0.4,
        ),
    ],
    context=["aadhaar", "aadhar", "uid", "uidai", "unique id", "aadhaar no"],
)

# UPI ID in narration: catches VPAs like name@bankhandle including inside UPI- prefixed strings
# Covers all major UPI handles + a generic catch-all for less common ones
IN_UPI_ID = PatternRecognizer(
    supported_entity="IN_UPI_ID",
    name="Indian UPI ID Recognizer",
    patterns=[
        # Specific known bank handles
        Pattern(
            name="in_upi_known",
            regex=r"[\w.\-]+@(?:ok(?:sbi|icici|axis|hdfc)|ybl|paytm|upi|apl|ibl|axl|kmbl|barodampay|freecharge|okhdfcbank|ikwik|mahb|indus|sbi|icici|hdfcbank|axisbank|kotak|rbl|federal|idbi|bandhan|pnb|bob|canarabank|indianbank|iob|uboi|unionbankofindia|rxairtel|airtel|jio|freecharge|slice|cred|jupiter|fi|niyobank|dbs|scb|citi|hsbc|sc|equitas|au0101)\b",
            score=0.9,
        ),
        # Generic UPI-like pattern in narration context (word@word)
        Pattern(
            name="in_upi_generic",
            regex=r"[\w.\-]+@[A-Za-z]{2,20}\b",
            score=0.3,
        ),
    ],
    context=["upi", "vpa", "payment", "transfer", "paid", "upi-", "neft", "imps"],
)

# MICR Code: 9 digits near "MICR" context
IN_MICR = PatternRecognizer(
    supported_entity="IN_MICR",
    name="Indian MICR Code Recognizer",
    patterns=[
        Pattern(
            name="in_micr",
            regex=r"\b\d{9}\b",
            score=0.3,
        ),
    ],
    context=["micr", "cheque", "check"],
)

# Indian phone: +91 or 0 prefix, then 10 digits. Also bare 1800 numbers.
IN_PHONE = PatternRecognizer(
    supported_entity="IN_PHONE",
    name="Indian Phone Number Recognizer",
    patterns=[
        Pattern(
            name="in_phone_plus91",
            regex=r"(?:\+91[\s\-]?)?[6-9]\d{4}[\s\-]?\d{5}\b",
            score=0.6,
        ),
        Pattern(
            name="in_phone_0prefix",
            regex=r"\b0[6-9]\d{4}[\s\-]?\d{5}\b",
            score=0.6,
        ),
    ],
    context=["phone", "mobile", "mob", "cell", "contact", "tel", "call", "sms", "whatsapp", "phone no"],
)

# Indian PIN code: 6 digits (postal)
IN_PIN_CODE = PatternRecognizer(
    supported_entity="IN_PIN_CODE",
    name="Indian PIN Code Recognizer",
    patterns=[
        Pattern(
            name="in_pin",
            regex=r"\b[1-9]\d{5}\b",
            score=0.3,
        ),
    ],
    context=["pin", "pincode", "pin code", "postal", "zip", "post office", "sector", "city"],
)

# Customer ID (CIF): typically 7-11 digit number near "Cust ID" context
IN_CUSTOMER_ID = PatternRecognizer(
    supported_entity="IN_CUSTOMER_ID",
    name="Indian Bank Customer ID Recognizer",
    patterns=[
        Pattern(
            name="in_cust_id",
            regex=r"\b\d{7,11}\b",
            score=0.3,
        ),
    ],
    context=["cust id", "customer id", "cif", "cust no", "customer no", "client id"],
)

# Branch code: typically 4-6 digit/alphanumeric code
IN_BRANCH_CODE = PatternRecognizer(
    supported_entity="IN_BRANCH_CODE",
    name="Indian Bank Branch Code Recognizer",
    patterns=[
        Pattern(
            name="in_branch_code",
            regex=r"\b[A-Z0-9]{4,6}\b",
            score=0.2,
        ),
    ],
    context=["branch code", "branch no", "branch"],
)

# Transaction reference / Chq Ref numbers: long numeric strings (12-20 digits)
IN_TXN_REF = PatternRecognizer(
    supported_entity="IN_TXN_REF",
    name="Indian Transaction Reference Recognizer",
    patterns=[
        Pattern(
            name="in_txn_ref_long",
            regex=r"\b\d{12,20}\b",
            score=0.6,
        ),
    ],
    context=[
        "ref", "ref no", "reference", "chq", "cheque", "txn", "transaction",
        "utr", "rrn", "chq./ref.no", "ref.no",
    ],
)

# UPI narration block: "UPI-MERCHANT-VPA-IFSC-REFNO-DESCRIPTION" pattern
# Catches the full UPI narration string that contains merchant + VPA + ref
IN_UPI_NARRATION = PatternRecognizer(
    supported_entity="IN_UPI_NARRATION",
    name="Indian UPI Narration Recognizer",
    patterns=[
        Pattern(
            name="in_upi_narration",
            regex=r"UPI-[A-Z0-9][\w\s.\-@/]*?-\d{6,20}-[A-Za-z][\w\s]*",
            score=0.85,
        ),
    ],
    context=["upi", "narration"],
)


# Date of birth: only flag dates near birth/dob context, not transaction dates
IN_DOB = PatternRecognizer(
    supported_entity="IN_DOB",
    name="Date of Birth Recognizer",
    patterns=[
        Pattern(
            name="dob_dd_mm_yyyy",
            regex=r"\b\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}\b",
            score=0.3,
        ),
        Pattern(
            name="dob_written",
            regex=r"\b\d{1,2}\s+(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{2,4}\b",
            score=0.3,
        ),
    ],
    context=["birth", "dob", "born", "date of birth", "d.o.b", "d/o/b", "birthday"],
)


ALL_IN_RECOGNIZERS = [
    IN_BANK_ACCOUNT,
    IN_IFSC,
    IN_PAN,
    IN_AADHAAR,
    IN_UPI_ID,
    IN_MICR,
    IN_PHONE,
    IN_PIN_CODE,
    IN_CUSTOMER_ID,
    IN_BRANCH_CODE,
    IN_TXN_REF,
    IN_UPI_NARRATION,
    IN_DOB,
]
