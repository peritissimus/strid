//
//  RedactionProfile.swift
//  StridApp
//
//  What the user considers private, and how much of a document should go.
//  Persisted by `ProfileStore`; turned into a StridKit `RedactionPolicy` for
//  each job (optionally narrowed further by the review sheet).
//
//  The profile is itself the user's most sensitive data (their own names and
//  account numbers), so it never leaves the app container and is written
//  with complete file protection.
//

import Foundation
import StridKit

/// The user's standing redaction preferences.
struct RedactionProfile: Codable, Equatable {
    /// A literal the user wants redacted every time it appears.
    struct Term: Codable, Equatable, Identifiable, Hashable {
        var id = UUID()
        /// The text to match ("Rahul Sharma", "50100234567890").
        var value: String
        /// Which category it is reported and counted as.
        var type: PIIEntityType
    }

    /// How much of a document to redact.
    enum Sensitivity: String, Codable, CaseIterable, Identifiable {
        /// Every finding of every type.
        case everything
        /// Only what identifies the user: names, contact details, IDs, accounts.
        /// Counterparties, references and codes stay readable.
        case personal
        /// The per-type switches in `disabledTypes`.
        case custom
        var id: String { rawValue }
        var title: String {
            switch self { case .everything: "Everything"; case .personal: "Personal only"; case .custom: "Custom" }
        }
        var blurb: String {
            switch self {
            case .everything: "Every name, number and reference found."
            case .personal: "Your identity, contact details and accounts. Vendors and references stay readable."
            case .custom: "Pick the categories yourself."
            }
        }
    }

    /// Show the review sheet between detection and redaction.
    var reviewBeforeRedacting = true
    var sensitivity: Sensitivity = .everything
    /// Types switched off under `.custom`.
    var disabledTypes: Set<PIIEntityType> = []
    var alwaysRedact: [Term] = []
    var keepVisible: [String] = []

    // MARK: Categories

    /// Types that identify the user rather than a counterparty or a record.
    static let personalTypes: Set<PIIEntityType> = [
        .person, .inDOB, .inAadhaar, .inPAN, .address, .location, .inPINCode, .phone, .inPhone, .email,
        .inBankAccount, .inCustomerID, .inUPIID, .creditCard, .barcode, .inIFSC, .inMICR, .inBranchCode,
    ]

    /// Types the current sensitivity reports. `nil` means all.
    var enabledTypes: Set<PIIEntityType>? {
        switch sensitivity {
        case .everything: nil
        case .personal: Self.personalTypes
        case .custom: Set(PIIEntityType.allCases).subtracting(disabledTypes)
        }
    }

    /// Whether `type` is on under the current sensitivity.
    func isEnabled(_ type: PIIEntityType) -> Bool { enabledTypes?.contains(type) ?? true }

    /// Flips one type. Leaves `.everything` / `.personal` for `.custom`,
    /// seeding the custom set from the preset so nothing else changes.
    mutating func setEnabled(_ type: PIIEntityType, _ on: Bool) {
        if sensitivity != .custom {
            disabledTypes = Set(PIIEntityType.allCases).subtracting(enabledTypes ?? Set(PIIEntityType.allCases))
            sensitivity = .custom
        }
        if on { disabledTypes.remove(type) } else { disabledTypes.insert(type) }
    }

    // MARK: Policy

    /// The engine policy for a job, optionally narrowed by review choices.
    func policy(disabling types: Set<PIIEntityType> = [], excluding values: Set<String> = []) -> RedactionPolicy {
        var enabled = enabledTypes ?? Set(PIIEntityType.allCases)
        enabled.subtract(types)
        let all = enabled.count == PIIEntityType.allCases.count
        return RedactionPolicy(
            enabledTypes: all ? nil : enabled,
            alwaysRedact: alwaysRedact.compactMap { t in
                let v = t.value.trimmingCharacters(in: .whitespacesAndNewlines)
                return v.isEmpty ? nil : RedactionPolicy.Term(v, type: t.type)
            },
            keepVisible: keepVisible.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            excludedValues: values)
    }
}

/// Display grouping of entity types for the profile and review screens.
enum PIICategory: String, CaseIterable, Identifiable {
    case identity, contact, banking, counterparty, references
    var id: String { rawValue }

    var title: String {
        switch self {
        case .identity: "Identity"
        case .contact: "Contact"
        case .banking: "Banking"
        case .counterparty: "Counterparties"
        case .references: "References & codes"
        }
    }

    var types: [PIIEntityType] {
        switch self {
        case .identity: [.person, .inDOB, .inAadhaar, .inPAN, .barcode]
        case .contact: [.address, .location, .inPINCode, .phone, .inPhone, .email]
        // Branch codes are part of the account's identity (IFSC, MICR and branch code are printed
        // beside the account number and name the branch), so they redact with it.
        case .banking: [.inBankAccount, .inCustomerID, .inUPIID, .creditCard, .inIFSC, .inMICR, .inBranchCode]
        case .counterparty: [.organization, .url, .inGSTIN, .ipAddress]
        case .references: [.inTxnRef, .orderID]
        }
    }

    static func category(of type: PIIEntityType) -> PIICategory {
        allCases.first { $0.types.contains(type) } ?? .references
    }
}
