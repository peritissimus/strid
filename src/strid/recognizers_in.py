"""Custom Presidio recognizers for Indian banking PII.

Presidio ships with US/EU-centric recognizers. This module adds regex-based
``PatternRecognizer`` instances for identifiers that show up on Indian bank
statements, KYC forms and payment narrations: account numbers, IFSC, PAN,
Aadhaar, UPI VPAs, MICR, phone numbers, PIN codes, customer IDs, branch codes,
transaction references, full UPI narration blocks and dates of birth.

How scoring works
-----------------
Every ``Pattern`` carries a base ``score`` (0.0-1.0) that Presidio assigns to
a raw regex hit. Two kinds of pattern are used here:

* **Structurally distinctive** formats (IFSC, PAN, known UPI handles, UPI
  narrations) get a high base score (0.85-0.9) because the shape alone is
  strong evidence.
* **Bare digit runs** (account numbers, MICR, PIN codes, customer IDs, branch
  codes, DOB) get a deliberately low base score (0.2-0.4). On their own they
  would match invoice numbers, amounts and dates, so they are meant to be
  *boosted* by Presidio's context enhancer: when one of the recognizer's
  ``context`` words (e.g. "a/c no", "micr", "pincode") appears in the text
  shortly before the match, Presidio adds a context bonus (0.35 by default)
  so the result clears the CLI's default 0.5 threshold. Without a context
  word these weak matches stay below threshold and are dropped.

Overlaps between recognizers (a 12-digit number matches account, Aadhaar
and txn-ref patterns at once) are resolved by Presidio after scoring: the
highest-scoring span for a given region wins.

Note that none of these recognizers validate checksums. Aadhaar numbers use
the Verhoeff algorithm and PAN encodes holder type in its 4th letter, but
these recognizers are purely syntactic; a checksum-aware recognizer would be
a reasonable future refinement to cut false positives.

All recognizers are collected in :data:`ALL_IN_RECOGNIZERS`, which
:class:`strid.engine.StridEngine` registers with the analyzer at start-up.
"""

from presidio_analyzer import Pattern, PatternRecognizer


# Indian bank account numbers: 9-18 digits, sometimes grouped with spaces/hyphens
#
# Regex ``\b\d{9,18}\b``: a run of 9 to 18 digits bounded by word boundaries,
# e.g. "123456789012" or "50100123456789". Indian banks use anything from 9
# digits (some PSU banks) to 18 (e.g. older ICICI/SBI formats). The regex
# does NOT accept internal spaces/hyphens despite the comment above; grouped
# numbers like "1234 5678 9012" will not match as a single span.
#
# Base score 0.3 is intentionally low: this pattern also matches phone
# numbers, reference numbers and Aadhaar. It relies on context words such as
# "a/c no" appearing nearby to be boosted over the threshold.
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
    # Common statement labels. Both "account no" entries are harmless
    # duplicates. "saving"/"current" cover "Savings A/c" / "Current A/c".
    context=[
        "account", "a/c", "acc", "acct", "bank account", "saving", "current",
        "account number", "account no", "acc no", "a/c no", "account no",
    ],
)

# IFSC Code: 4 letters + 0 + 6 alphanumeric (e.g., SBIN0012345, HDFC0001234)
#
# Regex ``\b[A-Z]{4}0[A-Z0-9]{6}\b``:
#   [A-Z]{4}   bank code, e.g. "SBIN", "HDFC", "ICIC"
#   0          the 5th character is always the reserved digit zero
#   [A-Z0-9]{6} branch code, usually digits but can be alphanumeric
# Uppercase only: Presidio does not compile patterns case-insensitively and
# IFSC codes are printed in caps on statements.
#
# Base score 0.85: the fixed "0" in position 5 plus the 4+7 shape makes
# accidental matches rare, so a bare hit is trusted even without context.
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
    # IFSC appears next to branch details and in NEFT/RTGS/IMPS narrations.
    context=["ifsc", "branch", "bank", "neft", "rtgs", "imps", "rtgs/neft"],
)

# PAN: 5 letters + 4 digits + 1 letter (e.g., ABCDE1234F)
#
# Regex ``\b[A-Z]{5}\d{4}[A-Z]\b``:
#   [A-Z]{5}  five letters (4th letter is holder type, e.g. P=person,
#             C=company; 5th is the first letter of the surname/name)
#   \d{4}     four-digit sequence number
#   [A-Z]     alphabetic check letter (not validated here)
# Base score 0.85 for the same reason as IFSC: the 5-4-1 shape is distinctive.
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
#
# Regex ``\b[2-9]\d{3}\s?\d{4}\s?\d{4}\b``:
#   [2-9]\d{3}  first group of 4; Aadhaar never starts with 0 or 1 (those
#               prefixes are reserved), which filters out many random numbers
#   \s?\d{4}    optional single whitespace, then 4 digits
#   \s?\d{4}    optional single whitespace, then the last 4 digits
# Matches "2345 6789 0123", "234567890123" and mixed spacing, e.g.
# "2345 67890123". Hyphen-separated forms are not matched.
#
# Base score 0.4: a 12-digit run is ambiguous (account/txn numbers), and the
# last digit is a Verhoeff checksum that this regex does not verify. Context
# words ("aadhaar", "uid") push it over the threshold.
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
    # "aadhar" is the common misspelling; "uid"/"uidai" appear on e-KYC docs.
    context=["aadhaar", "aadhar", "uid", "uidai", "unique id", "aadhaar no"],
)

# UPI ID in narration: catches VPAs like name@bankhandle including inside UPI- prefixed strings
# Covers all major UPI handles + a generic catch-all for less common ones
#
# Two patterns with very different confidence:
#
# 1. ``in_upi_known`` (score 0.9):
#    ``[\w.\-]+@(?:ok(?:sbi|icici|axis|hdfc)|ybl|paytm|upi|...)\b``
#      [\w.\-]+  the user part: letters, digits, underscore, dot, hyphen,
#                e.g. "rahul.sharma", "9876543210", "merchant-123"
#      @         literal separator
#      (?:...)   an explicit alternation of real PSP/bank handles:
#                  ok(?:sbi|icici|axis|hdfc)  -> Google Pay handles (oksbi, okicici...)
#                  ybl                         -> PhonePe (Yes Bank)
#                  paytm, apl (Amazon Pay), ibl (PhonePe/ICICI), axl (PhonePe/Axis),
#                  kmbl (Kotak), barodampay, freecharge, ikwik (MobiKwik),
#                  mahb (Maharashtra Bank), indus, sbi, icici, hdfcbank, ...
#                  plus fintech handles (slice, cred, jupiter, fi, niyobank)
#                  and foreign banks (dbs, scb, citi, hsbc, sc).
#      \b        handle must end at a word boundary so "name@sbi" does not
#                swallow the rest of a longer token.
#    Note there is deliberately no leading ``\b``: VPAs embedded in narration
#    strings like "UPI-RAHUL-rahul@ybl-..." must still match mid-token.
#    "freecharge" appears twice in the alternation; harmless.
#
# 2. ``in_upi_generic`` (score 0.3):
#    ``[\w.\-]+@[A-Za-z]{2,20}\b``: anything that looks like user@word with a
#    2-20 letter handle, e.g. "shop@newbank". Low score because it also
#    matches e-mail-like fragments; it needs "upi"/"vpa"/"paid" context to
#    be reported. Presidio's EMAIL_ADDRESS recognizer will usually outscore
#    it on real e-mail addresses (which have a dot in the domain).
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
    # "upi-" catches the narration prefix; neft/imps because VPAs sometimes
    # appear in those remarks too.
    context=["upi", "vpa", "payment", "transfer", "paid", "upi-", "neft", "imps"],
)

# MICR Code: 9 digits near "MICR" context
#
# Regex ``\b\d{9}\b``: exactly nine digits, e.g. "400002001". A MICR code is
# 3-digit city + 3-digit bank + 3-digit branch, printed at the bottom of
# cheques. Nine digits alone is far too generic (it overlaps the account
# number pattern), hence base score 0.3 and reliance on "micr"/"cheque"
# context to be surfaced.
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
# (Despite the note above, neither pattern below matches 1800 toll-free
# numbers: both require the subscriber number to start with 6-9.)
#
# 1. ``in_phone_plus91``: ``(?:\+91[\s\-]?)?[6-9]\d{4}[\s\-]?\d{5}\b``
#      (?:\+91[\s\-]?)?  optional "+91" country code followed by an optional
#                        space or hyphen, e.g. "+91 ", "+91-", "+91"
#      [6-9]\d{4}        first 5 digits; Indian mobiles start with 6, 7, 8 or 9
#      [\s\-]?           optional separator in the middle ("98765 43210")
#      \d{5}\b           last 5 digits
#    Matches "+91 98765 43210", "+91-9876543210" and bare "9876543210".
#    No leading ``\b`` so the "+" is captured as part of the span.
#
# 2. ``in_phone_0prefix``: ``\b0[6-9]\d{4}[\s\-]?\d{5}\b``
#    Same shape with a domestic trunk "0" prefix, e.g. "09876543210" or
#    "098765 43210".
#
# Score 0.6: above the default 0.5 threshold on its own, since a 10-digit
# number starting with 6-9 is a strong signal in Indian documents, and
# context ("mobile", "whatsapp") boosts it further.
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
#
# Regex ``\b[1-9]\d{5}\b``: six digits whose first digit is 1-9 (Indian PIN
# codes never start with 0; the first digit is the postal region), e.g.
# "400001" (Mumbai), "110001" (Delhi). Six-digit numbers are common in
# amounts and IDs, so base score 0.3 plus address-related context words.
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
    # "zip" for forms that use US terminology; "sector"/"city" because PIN
    # codes usually sit at the end of an address line.
    context=["pin", "pincode", "pin code", "postal", "zip", "post office", "sector", "city"],
)

# Customer ID (CIF): typically 7-11 digit number near "Cust ID" context
#
# Regex ``\b\d{7,11}\b``: 7 to 11 digits, e.g. "12345678" or "87654321098".
# Overlaps heavily with account numbers and phone numbers, so base score 0.3
# and it only becomes meaningful next to "cust id" / "cif" labels, which is
# where banks print it on statement headers.
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
#
# Regex ``\b[A-Z0-9]{4,6}\b``: 4-6 uppercase letters and/or digits, e.g.
# "0123", "MUM01", "004567". This is the loosest pattern in the file (it
# matches many ordinary uppercase words and short numbers), so it has the
# lowest base score, 0.2, and is effectively only reported when "branch
# code" / "branch no" appears right before it.
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
#
# Regex ``\b\d{12,20}\b``: 12 to 20 digits, e.g. a 12-digit UTR/RRN
# "123456789012" or a 16-digit NEFT reference. Score 0.6 so bare long digit
# runs in a statement are flagged even without context; the "ref"/"utr"/"rrn"
# words boost it further. Overlaps with IN_BANK_ACCOUNT and IN_AADHAAR for
# 12-18 digit numbers; Presidio keeps the higher-scored interpretation.
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
    # "chq./ref.no" and "ref.no" mirror the literal column headings used by
    # HDFC/ICICI-style statements.
    context=[
        "ref", "ref no", "reference", "chq", "cheque", "txn", "transaction",
        "utr", "rrn", "chq./ref.no", "ref.no",
    ],
)

# UPI narration block: "UPI-MERCHANT-VPA-IFSC-REFNO-DESCRIPTION" pattern
# Catches the full UPI narration string that contains merchant + VPA + ref
#
# Regex ``UPI-[A-Z0-9][\w\s.\-@/]*?-\d{6,20}-[A-Za-z][\w\s]*``:
#   UPI-            literal prefix used by most Indian banks in narrations
#   [A-Z0-9]        payee name must start with an uppercase letter or digit
#   [\w\s.\-@/]*?   lazily consume the payee name, VPA ("name@ybl"), IFSC and
#                   any other hyphen/slash-separated middle fields
#   -\d{6,20}-      the numeric reference number (6-20 digits) between hyphens;
#                   the lazy quantifier before it stops at the first such group
#   [A-Za-z][\w\s]* the trailing free-text description, e.g. "Payment from
#                   PhonePe" or "UPI" -- greedy, so it runs to the end of the
#                   line (or until a non-word, non-space character)
# Example match: "UPI-SWIGGY-swiggy@ybl-HDFC0000001-123456789012-Food order".
#
# Score 0.85: the whole block is PII (payee + VPA + ref) and the structure is
# unmistakable. Because this span covers the embedded VPA and ref number,
# it typically wins the overlap resolution against IN_UPI_ID / IN_TXN_REF.
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
#
# Bank statements are full of dates (every transaction row), and redacting
# all of them would destroy the document. Both patterns therefore carry a low
# 0.3 score so a date is only reported when a birth-related context word
# precedes it.
#
# 1. ``dob_dd_mm_yyyy``: ``\b\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}\b``
#      1-2 digit day, separator (/, - or .), 1-2 digit month, same separator
#      class, 2- or 4-digit year. Matches "15/08/1990", "5-8-90", "15.08.1990".
#      Day/month order is not enforced, so US-style dates match too.
#
# 2. ``dob_written``: ``\b\d{1,2}\s+(?:Jan(?:uary)?|Feb(?:ruary)?|...)\s+\d{2,4}\b``
#      day, whitespace, a month name in full or 3-letter abbreviation (the
#      ``(?:uary)?`` style makes the suffix optional), whitespace, year.
#      Matches "15 August 1990" and "15 Aug 1990". Case-sensitive: month
#      must be capitalised as written ("august" will not match).
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
    # Various spellings of "date of birth" found on KYC forms.
    context=["birth", "dob", "born", "date of birth", "d.o.b", "d/o/b", "birthday"],
)


# Every recognizer defined above, in registration order. StridEngine iterates
# this list and calls ``analyzer.registry.add_recognizer`` for each. Order
# does not affect results; Presidio runs all applicable recognizers and
# resolves overlaps by score.
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
