//
//  SampleDocument.swift
//  StridApp
//
//  Hexagonal architecture role: **domain entity** plus static fixture data.
//
//  Sample documents let a first-time user try the detector without importing
//  anything sensitive of their own. They are deliberately dense with varied,
//  entirely fictional PII (Indian banking identifiers, US SSNs, emails, phone
//  numbers, dates of birth, addresses) so a single sample exercises many
//  recognizers at once. When a sample is loaded it becomes an ordinary
//  `Document` with `DocumentSource.sample`.
//
//  None of the identifiers below belong to real people; they follow the
//  *format* of real identifiers (e.g. PAN `ABCDE1234F`, IFSC `HDFC0001234`)
//  only so the pattern-based recognizers fire.
//

import Foundation

/// Predefined sample documents for demonstration
///
/// Not `Codable`: samples live in code, never on disk. Once loaded, the text
/// is copied into a persistable `Document` / `ScannedDocument`.
struct SampleDocument: Identifiable {
    /// Identifier for list rendering. Regenerated on every launch because the
    /// statics below call `UUID()`; nothing persists a sample's id.
    let id: UUID

    /// Short name shown in the sample picker, e.g. "Bank Account Letter".
    let title: String

    /// One-line explanation of what kind of PII the sample contains.
    let description: String

    /// The full sample text that will be scanned.
    let content: String

    /// Grouping used by the picker to section and icon the samples.
    let category: SampleCategory

    /// Thematic grouping of samples. The raw value doubles as the section
    /// header text in the picker.
    enum SampleCategory: String, CaseIterable {
        /// Indian bank correspondence (account numbers, IFSC, UPI, PAN, Aadhaar).
        case banking = "Banking"
        /// Lab/medical reports (MRN, SSN, insurance policy numbers).
        case medical = "Medical"
        /// HR / offer letters (salary, bank routing, employee ids).
        case employment = "Employment"
        /// Casual email (passport, flight confirmations, driver's licence).
        case personal = "Personal"

        /// SF Symbol name used as the category's icon in the picker.
        var icon: String {
            switch self {
            case .banking: return "banknote"
            case .medical: return "cross.case"
            case .employment: return "briefcase"
            case .personal: return "person.text.rectangle"
            }
        }
    }

    /// Creates a sample.
    ///
    /// - Parameters:
    ///   - id: Identifier; a fresh `UUID` by default.
    ///   - title: Picker display name.
    ///   - description: One-line summary of the sample's contents.
    ///   - content: Full text to scan.
    ///   - category: Grouping for the picker.
    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        content: String,
        category: SampleCategory
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.content = content
        self.category = category
    }
}

// MARK: - Predefined Samples

extension SampleDocument {
    /// All bundled samples in the order the picker should present them.
    static let samples: [SampleDocument] = [
        .indianBankingLetter,
        .medicalReport,
        .employmentOffer,
        .personalEmail
    ]

    /// Indian banking welcome letter. Targets the Indian-specific recognizers:
    /// 16-digit account number, IFSC code, UPI handle, PAN, Aadhaar (with the
    /// conventional 4-4-4 spacing), +91 phone, customer id, transaction ref
    /// and a DD/MM/YYYY date of birth.
    static let indianBankingLetter = SampleDocument(
        title: "Bank Account Letter",
        description: "Indian banking document with account details",
        content: """
            Dear Rajesh Kumar,

            Thank you for opening your savings account with us. Here are your account details:

            Account Number: 1234567890123456
            IFSC Code: HDFC0001234
            Branch: Mumbai Central
            Customer ID: CUST8765432

            Your registered email is rajesh.kumar@gmail.com and phone number is +91-9876543210.

            For UPI payments, use: rajesh@upi
            PAN Number: ABCDE1234F
            Aadhaar: 1234 5678 9012

            Please keep this information confidential.

            Transaction Reference: TXN2024031500123
            Date of Birth: 15/03/1985

            Best regards,
            Mumbai Bank
            """,
        category: .banking
    )

    /// US-style laboratory report. Mixes patient identifiers (MRN, SSN,
    /// address, US phone format) with physician licence and insurance policy
    /// numbers, and includes non-PII clinical values (glucose, cholesterol)
    /// that the detector should leave untouched.
    static let medicalReport = SampleDocument(
        title: "Medical Test Report",
        description: "Laboratory test results with patient information",
        content: """
            MEDICAL LABORATORY REPORT

            Patient Name: Sarah Johnson
            Date of Birth: 07/15/1990
            Patient ID: MRN-789456
            Address: 123 Oak Street, San Francisco, CA 94102

            Phone: (415) 555-0123
            Email: sarah.johnson@email.com
            SSN: 123-45-6789

            Test Date: March 15, 2024
            Report Date: March 16, 2024

            RESULTS:
            - Complete Blood Count: Normal
            - Glucose Level: 95 mg/dL
            - Cholesterol: 180 mg/dL

            Physician: Dr. Michael Chen
            License: CA-MD-456789
            Contact: drmchen@hospital.org

            Insurance: Blue Cross - Policy #HC-9876543210
            """,
        category: .medical
    )

    /// Employment offer letter. Covers a US bank account + routing number,
    /// salary figure (should not be flagged as PII), employee id, SSN, and a
    /// second person's name/phone in the emergency-contact block.
    static let employmentOffer = SampleDocument(
        title: "Employment Offer Letter",
        description: "Job offer with compensation and personal details",
        content: """
            CONFIDENTIAL EMPLOYMENT OFFER

            Date: March 15, 2024

            Dear Emily Rodriguez,

            We are pleased to offer you the position of Senior Software Engineer at TechCorp Inc.

            Personal Information:
            Email: emily.rodriguez@personal.com
            Phone: +1-555-234-5678
            Address: 456 Market Street, Apt 12B, Seattle, WA 98101
            SSN: 987-65-4321
            Date of Birth: 03/22/1988

            Compensation:
            Base Salary: $145,000 per year
            Bank Account (for direct deposit):
              - Account Number: 9876543210
              - Routing Number: 123456789

            Start Date: April 1, 2024
            Employee ID: EMP-2024-1234

            Emergency Contact:
            Name: Robert Rodriguez
            Phone: +1-555-876-5432

            Please sign and return by March 20, 2024.

            Sincerely,
            TechCorp Inc.
            HR Department
            hr@techcorp.com
            """,
        category: .employment
    )

    /// Informal email with travel details. Exercises email headers, passport
    /// and frequent-flyer numbers, booking confirmations, a truncated credit
    /// card ("last 4"), multiple phone numbers, a signature-block SSN and a
    /// US driver's licence.
    static let personalEmail = SampleDocument(
        title: "Personal Correspondence",
        description: "Email with travel and contact information",
        content: """
            From: john.smith@email.com
            To: mary.williams@company.com
            Date: March 15, 2024
            Subject: Travel Plans & Contact Info

            Hi Mary,

            Here are my travel details for next week:

            Flight: AA1234
            Confirmation: XYZ789ABC
            Passport: P12345678
            Frequent Flyer: 987654321

            Hotel Reservation:
            Confirmation: HTL-456789
            Address: 789 Park Avenue, New York, NY 10021
            Phone: +1-212-555-9876

            My contact info during the trip:
            Mobile: +1-555-123-4567
            Backup Email: j.smith.backup@email.com
            Credit Card (last 4): 5678

            In case of emergency, contact:
            Jane Smith (spouse)
            Phone: +1-555-765-4321
            DOB: 05/12/1985

            See you soon!
            John

            --
            John Smith
            SSN: 456-78-9012
            Driver's License: NY-D1234567
            """,
        category: .personal
    )
}
