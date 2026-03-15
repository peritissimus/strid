import Foundation

/// Predefined sample documents for demonstration
struct SampleDocument: Identifiable {
    let id: UUID
    let title: String
    let description: String
    let content: String
    let category: SampleCategory

    enum SampleCategory: String, CaseIterable {
        case banking = "Banking"
        case medical = "Medical"
        case employment = "Employment"
        case personal = "Personal"

        var icon: String {
            switch self {
            case .banking: return "banknote"
            case .medical: return "cross.case"
            case .employment: return "briefcase"
            case .personal: return "person.text.rectangle"
            }
        }
    }

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
    static let samples: [SampleDocument] = [
        .indianBankingLetter,
        .medicalReport,
        .employmentOffer,
        .personalEmail
    ]

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
