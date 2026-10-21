//
// IndianIdentityRecognizers.swift
// StridKit
//
// Identity documents beyond Aadhaar and PAN: passport, voter ID, driving licence, vehicle
// registration, EPF numbers, TAN and CIN, plus the card-security and foreign-account shapes
// that sit next to them (CVV, expiry, IBAN). Same scoring philosophy as the banking file: a
// shape that is distinctive on its own scores above the threshold; a shape that is just letters
// and digits needs its label nearby or a structural check.
//
import Foundation

/// Identity-document recognizers registered by `IndianBankingRecognizers.all()`.
public enum IndianIdentityRecognizers {
    public static func all() -> [Recognizer] {
        [labelledName, declaredName, companyName, passport, passportMRZ, voterID, drivingLicence, vehicleReg, vehicleRegBH, chassis, engineNumber, uan, pfAccount, tan, cin, cardSecurity, iban]
    }

    /// A name printed after its label on an identity card, on the same line or the next
    /// ("Name: ROHAN VENKATESH", "Surname\nVENKATESH", "S/D/W of: SRINIVAS VENKATESH"). The value
    /// is one to four capitalised words taking the rest of the line, so a label followed by prose
    /// ("Name and address of the Employer") does not match. Covers the mixed-case and all-caps
    /// names the name tagger skips on cards.
    public static let labelledName = CaptureRecognizer(
        entityType: .person,
        patterns: [
            #"(?im)(?:^|[\s/(])(?:elector'?s name|father'?s name|mother'?s name|husband'?s name|holder'?s name|owner'?s? name|given names?(?:\(s\))?|surname|name|s/d/w of|s/w/d of|s/o|d/o|w/o)\s*[:\-]?[ \t]*\n?[ \t]*([A-Z][A-Za-z.']*(?:[ \t]+[A-Z][A-Za-z.']*){0,3})[ \t]*$"#,
        ],
        score: 0.85
    )

    /// "I, PRIYA NAIR, son/daughter of ..." in a verification or declaration clause.
    public static let declaredName = CaptureRecognizer(
        entityType: .person,
        patterns: [#"\bI,\s+([A-Z][A-Za-z.']+(?:\s+[A-Z][A-Za-z.']+){1,3}),"#],
        score: 0.85
    )

    /// A company name by its legal suffix ("RZPX PRIVATE LIMITED", "Maruti Suzuki India Ltd").
    public static let companyName = CaptureRecognizer(
        entityType: .organization,
        patterns: [#"(?im)\b((?:[A-Z][A-Za-z&.'\-]*\s+){1,5}(?:PRIVATE|PVT\.?|LIMITED|LTD\.?|LLP|INC\.?|CORPORATION|CORP\.?|PLC)(?:\s+(?:LIMITED|LTD\.?))?)(?=[\s,.)]|$)"#],
        score: 0.8
    )

    /// Passport number: one letter (never Q, X or Z) and seven digits, the first non-zero.
    ///
    /// The shape also fits a few order numbers, so a bare match stays below threshold and the
    /// label ("Passport No.", "पासपोर्ट") lifts it. On the data page the label is always present.
    public static let passport = RegexRecognizer(
        entityType: .inPassport,
        patterns: [#"\b[A-PR-WY][1-9]\d{6}\b"#],
        baseScore: 0.35,
        contextWords: ["passport", "passport no", "passport number", "पासपोर्ट", "travel document", "mrz"],
        contextBoost: 0.55
    )

    /// Machine-readable zone of a passport: two 44-character lines. Line 1 starts `P<IND` and
    /// carries the name; line 2 carries the number, nationality, date of birth, sex, expiry and
    /// personal number. OCR often shortens or lengthens the filler, so the lengths are loose.
    public static let passportMRZ = CaptureRecognizer(
        entityType: .inPassport,
        patterns: [
            #"(?m)^[ \t]*(P[A-Z<][A-Z]{3}[A-Z<]{25,44})[ \t]*$"#,
            #"(?m)^[ \t]*([A-Z0-9<]{8,9}[0-9<][A-Z]{3}\d{7}[MFX<]\d{7}[A-Z0-9<]{8,20})[ \t]*$"#,
        ],
        score: 0.95
    )

    /// Voter ID (EPIC): three letters and seven digits. Needs the label or the card's own words.
    public static let voterID = RegexRecognizer(
        entityType: .inVoterID,
        patterns: [#"\b[A-Z]{3}\d{7}\b"#],
        baseScore: 0.35,
        contextWords: ["epic", "epic no", "voter", "voter id", "elector", "electors", "election commission", "मतदाता", "निर्वाचक", "पहचान पत्र", "identity card"],
        contextBoost: 0.55,
        contextWindow: 200
    )

    /// Driving licence: state code, two-digit RTO, four-digit year (19xx/20xx) and a seven-digit
    /// serial, written with or without spaces and hyphens ("KA01 20150012345", "DL-0420110149646").
    /// The embedded year and the state code make the bare shape reliable.
    public static let drivingLicence = RegexRecognizer(
        entityType: .inDrivingLicence,
        patterns: [#"\b[A-Z]{2}[ -]?\d{2}[ -]?(?:19|20)\d{2}[ -]?\d{7}\b"#],
        baseScore: 0.6,
        contextWords: ["dl", "dl no", "driving licence", "driving license", "licence", "license", "ड्राइविंग", "लाइसेंस", "transport", "rto"],
        contextBoost: 0.35,
        validator: { Checksums.startsWithStateCode($0) },
        validatedScore: 0.75
    )

    /// Vehicle registration mark: state code, district number, series letters, four digits.
    /// ("KA 01 AB 1234", "MH12DE1433"). The state-code check vetoes ordinary words; the shape
    /// with spaces also fits little else, so a validated match sits just above threshold and the
    /// RC labels ("Regn. No", "Vehicle No") take it higher.
    public static let vehicleReg = RegexRecognizer(
        entityType: .inVehicleReg,
        patterns: [#"\b[A-Z]{2}[ -]?\d{1,2}[ -]?[A-Z]{1,3}[ -]?\d{4}\b"#],
        baseScore: 0.3,
        contextWords: ["vehicle", "regn", "regn no", "registration no", "registration number", "reg no", "rc", "chassis", "engine no", "owner", "challan", "वाहन", "पंजीकरण"],
        contextBoost: 0.35,
        validator: { Checksums.startsWithStateCode($0) },
        validatedScore: 0.6
    )

    /// Bharat series mark: year, "BH", four digits, one or two letters ("22 BH 1234 AA").
    public static let vehicleRegBH = RegexRecognizer(
        entityType: .inVehicleReg,
        patterns: [#"\b(?:1[0-9]|2[0-9]|3[0-9])[ -]?BH[ -]?\d{4}[ -]?[A-HJ-NP-Z]{1,2}\b"#],
        baseScore: 0.7,
        contextWords: ["vehicle", "regn", "registration", "bharat series", "rc"]
    )

    /// Chassis number (VIN): seventeen characters without I, O or Q, at least one digit. Needs
    /// the RC label; the shape alone is any long reference.
    public static let chassis = RegexRecognizer(
        entityType: .inVehicleReg,
        patterns: [#"\b(?=[A-HJ-NPR-Z0-9]*\d)[A-HJ-NPR-Z0-9]{17}\b"#],
        baseScore: 0.3,
        contextWords: ["chassis", "chassis no", "vin", "ch no"],
        contextBoost: 0.6,
        contextWindow: 40,
        contextAfter: 10
    )

    /// Engine number as labelled on a registration certificate or insurance policy.
    public static let engineNumber = CaptureRecognizer(
        entityType: .inVehicleReg,
        patterns: [#"(?i)\bengine\s*(?:no|number)\.?\s*[:#]?\s*((?=[A-Z0-9]*\d)[A-Z0-9]{6,17})\b"#],
        score: 0.9
    )

    /// EPF Universal Account Number: twelve digits, always labelled. Below threshold on its own
    /// (it would otherwise claim every 12-digit reference); "UAN" or "EPF" context decides.
    public static let uan = RegexRecognizer(
        entityType: .inUAN,
        patterns: [#"(?<!\d)1\d{11}(?!\d)"#],
        baseScore: 0.2,
        contextWords: ["uan", "universal account", "epf", "epfo", "provident fund", "pf"],
        contextBoost: 0.6,
        contextWindow: 60,
        contextAfter: 20
    )

    /// PF member account number: office code, establishment, extension and member id
    /// ("KA/BNG/0012345/000/0001234", "MHBAN00123450000001234" as printed on slips).
    public static let pfAccount = RegexRecognizer(
        entityType: .inUAN,
        patterns: [
            #"\b[A-Z]{2}/[A-Z]{3}/\d{5,7}/\d{3}/\d{5,7}\b"#,
            #"\b[A-Z]{2}[A-Z]{3}\d{7}\d{3}\d{7}\b"#,
        ],
        baseScore: 0.8,
        contextWords: ["pf", "epf", "provident", "member id", "pf no", "pf a/c"]
    )

    /// TAN: four letters, five digits, one letter ("BLRA12345C"). The fourth letter is the
    /// deductor's initial and the first three the city code, which the regex does not enforce.
    public static let tan = RegexRecognizer(
        entityType: .inTAN,
        patterns: [#"\b[A-Z]{4}\d{5}[A-Z]\b"#],
        baseScore: 0.45,
        contextWords: ["tan", "tan no", "tax deduction", "deductor", "tds", "form 16", "form 16a", "26as"],
        contextBoost: 0.45
    )

    /// CIN: listing status, industry code, state, year, ownership, registration number
    /// ("L17110MH1973PLC019786"). Twenty-one characters in a fixed grammar: no context needed.
    public static let cin = RegexRecognizer(
        entityType: .inCIN,
        patterns: [#"\b[LU]\d{5}[A-Z]{2}(?:19|20)\d{2}[A-Z]{3}\d{6}\b"#],
        baseScore: 0.9,
        contextWords: ["cin", "corporate identity", "corporate identification", "llpin"]
    )

    /// Card security data printed near a card number: CVV/CVC and the expiry month/year.
    public static let cardSecurity = CaptureRecognizer(
        entityType: .creditCard,
        patterns: [
            #"(?i)\b(?:cvv|cvc|cvv2|cvc2|security code)\s*[:#.]?\s*(\d{3,4})\b"#,
            #"(?i)\b(?:valid\s*thru|valid\s*upto|expiry|expires|exp\.?|exp\s*date|good\s*thru)\s*[:#.]?\s*((?:0[1-9]|1[0-2])\s*/\s*(?:\d{2}|20\d{2}))\b(?!\s*/\s*\d)"#,
        ],
        score: 0.9
    )

    /// IBAN for NRI and foreign-remittance documents, verified with the mod-97 check. Reported as
    /// a bank account since that is what it is.
    public static let iban = RegexRecognizer(
        entityType: .inBankAccount,
        patterns: [#"\b[A-Z]{2}\d{2}(?:[ ]?[A-Z0-9]{4}){2,7}(?:[ ]?[A-Z0-9]{1,4})?\b"#],
        baseScore: 0.2,
        contextWords: ["iban", "swift", "bic", "beneficiary", "remittance", "wire"],
        contextBoost: 0.2,
        validator: { Checksums.iban($0) },
        validatedScore: 0.9
    )
}
