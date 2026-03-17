import Foundation
import StridKit
@testable import StridApp

/// Factory methods for creating test data instances
enum TestFactories {

    // MARK: - Document

    static func makeDocument(
        id: UUID = UUID(),
        content: String = "Test document content",
        createdAt: Date = Date()
    ) -> Document {
        Document(id: id, content: content, createdAt: createdAt)
    }

    // MARK: - DetectedPII

    static func makeDetectedPII(
        id: UUID = UUID(),
        type: PIIEntityType = .email,
        text: String = "test@example.com",
        score: Double = 0.95
    ) -> DetectedPII {
        let range = text.startIndex..<text.endIndex
        let entity = PIIEntity(type: type, text: text, range: range, score: score)
        return DetectedPII(id: id, entity: entity)
    }

    // MARK: - ScanResults

    static func makeScanResults(
        entityCount: Int = 2,
        types: [PIIEntityType]? = nil
    ) -> ScanResults {
        let piiTypes = types ?? [.email, .phone]
        let entities = (0..<entityCount).map { i in
            let type = piiTypes[i % piiTypes.count]
            return makeDetectedPII(
                type: type,
                text: sampleTextFor(type: type, index: i)
            )
        }

        let redacted = RedactedDocument(
            originalDocumentId: UUID(),
            redactedContent: "Redacted: " + entities.map { "<\($0.type.displayName)>" }.joined(separator: ", ")
        )

        return ScanResults(detectedEntities: entities, redactedDocument: redacted)
    }

    // MARK: - ScannedDocument

    static func makeScannedDocument(
        id: UUID = UUID(),
        content: String = "Test document with test@example.com",
        scannedAt: Date = Date(),
        source: DocumentSource = .clipboard,
        entityCount: Int = 1,
        fileURL: URL? = nil
    ) -> ScannedDocument {
        let doc = makeDocument(content: content)
        let results = makeScanResults(entityCount: entityCount)
        return ScannedDocument(
            id: id,
            originalDocument: doc,
            scanResults: results,
            scannedAt: scannedAt,
            source: source,
            originalFileURL: fileURL
        )
    }

    // MARK: - RedactedDocument

    static func makeRedactedDocument(
        originalDocumentId: UUID = UUID(),
        redactedContent: String = "Redacted content: <EMAIL>, <PHONE>"
    ) -> RedactedDocument {
        RedactedDocument(
            originalDocumentId: originalDocumentId,
            redactedContent: redactedContent
        )
    }

    // MARK: - Sample Documents

    static var sampleEmailDocument: String {
        "Contact us at support@example.com for help"
    }

    static var samplePhoneDocument: String {
        "Call us at +1-555-123-4567 or (555) 987-6543"
    }

    static var sampleIndianPIIDocument: String {
        """
        Customer Details:
        Name: Rajesh Kumar
        PAN: ABCDE1234F
        Aadhaar: 1234 5678 9012
        IFSC: HDFC0001234
        Phone: +91-9876543210
        Email: rajesh.kumar@email.com
        UPI: rajesh@paytm
        """
    }

    static var sampleUSPIIDocument: String {
        """
        Employee Information:
        Name: John Doe
        Email: john.doe@company.com
        Phone: 555-123-4567
        Location: San Francisco, CA
        Credit Card: 4532-1234-5678-9010
        Organization: Tech Corp Inc.
        """
    }

    static var sampleMultiPIIDocument: String {
        """
        Transaction Record:
        From: alice@example.com (+1-555-111-2222)
        To: bob@example.com (+1-555-333-4444)
        Amount: $1,234.56
        Location: New York, NY
        IP Address: 192.168.1.100
        Website: https://secure-payment.com
        """
    }

    // MARK: - Helper Methods

    private static func sampleTextFor(type: PIIEntityType, index: Int) -> String {
        switch type {
        case .email:
            return "test\(index)@example.com"
        case .phone, .inPhone:
            return "+1-555-\(String(format: "%03d", index))-\(String(format: "%04d", index))"
        case .person:
            return "Person Name \(index)"
        case .url:
            return "https://example\(index).com"
        case .location:
            return "City \(index), State"
        case .organization:
            return "Company \(index) Inc"
        case .creditCard:
            return "4532-\(String(format: "%04d", index))-\(String(format: "%04d", index))-\(String(format: "%04d", index))"
        case .ipAddress:
            return "192.168.1.\(index)"
        case .inBankAccount:
            return "123456789012\(String(format: "%04d", index))"
        case .inIFSC:
            return "HDFC000\(String(format: "%04d", index))"
        case .inPAN:
            return "ABCDE\(String(format: "%04d", index))F"
        case .inAadhaar:
            return "\(String(format: "%04d", index)) 5678 9012"
        case .inUPIID:
            return "user\(index)@paytm"
        case .inMICR:
            return "400240\(String(format: "%03d", index))"
        case .inPINCode:
            return "4000\(String(format: "%02d", index))"
        case .inCustomerID:
            return "CUST\(String(format: "%010d", index))"
        case .inBranchCode:
            return "00\(String(format: "%04d", index))"
        case .inTxnRef:
            return "TXN202603\(String(format: "%06d", index))"
        case .inDOB:
            return "15/08/1990"
        }
    }
}
