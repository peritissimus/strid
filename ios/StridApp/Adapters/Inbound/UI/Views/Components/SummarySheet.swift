//
//  SummarySheet.swift
//  StridApp
//
//  "PII Details" sheet presented from the Details toolbar button in
//  `ScannedDocumentResultsView`. Three sections: a big total, a per-type
//  breakdown sorted by count, and every individual detection with its
//  confidence score and matched text. Also hosts the `PIIEntityType.iconName`
//  extension used for the per-type rows.
//

import SwiftUI
import StridKit

// MARK: - PIIEntityType Icon Extension

extension PIIEntityType {
    /// SF Symbol that stands in for the entity type in lists and badges.
    ///
    /// Chosen to read at a glance: contact types get communication glyphs,
    /// Indian banking identifiers get finance glyphs, and codes that have no
    /// natural icon fall back to number symbols.
    var iconName: String {
        switch self {
        case .person: return "person"
        case .email: return "envelope"
        case .phone, .inPhone: return "phone"
        case .url: return "link"
        case .location: return "mappin"
        case .organization: return "building.2"
        case .creditCard: return "creditcard"
        case .ipAddress: return "network"
        case .inBankAccount: return "banknote"
        case .inIFSC: return "building.columns"
        case .inPAN: return "doc.text"
        case .inAadhaar: return "person.text.rectangle"
        case .inUPIID: return "indianrupeesign.circle"
        case .inMICR: return "barcode"
        case .inPINCode: return "mappin.and.ellipse"
        case .inCustomerID: return "person.badge.key"
        case .inBranchCode: return "number"
        case .inTxnRef: return "number.circle"
        case .inDOB: return "calendar"
        }
    }
}

// MARK: - SummarySheet

/// Sheet displaying detailed PII scan results with categories and individual detections
struct SummarySheet: View {
    /// Results to summarise. Passed by value from the selected document.
    let results: ScanResults

    /// Dismisses the sheet from the Done button.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Own NavigationStack so the sheet gets a title bar and toolbar.
        NavigationStack {
            List {
                // Section 1: headline total with a faded shield as backdrop.
                Section {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Total Found")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Text("\(results.entityCount)")
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundStyle(.red)
                            }

                            Spacer()

                            Image(systemName: "exclamationmark.shield.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(.red.opacity(0.15))
                        }
                    }
                    .padding(.vertical, 12)
                }

                // Section 2: one row per entity type, most frequent first.
                // Force-unwraps are safe: every key comes from the same
                // dictionary being indexed.
                Section {
                    ForEach(
                        results.summary.keys.sorted(by: { results.summary[$0]! > results.summary[$1]! }),
                        id: \.self
                    ) { type in
                        HStack(spacing: 14) {
                            Image(systemName: type.iconName)
                                .font(.title3)
                                .frame(width: 30)

                            Text(type.displayName)
                                .font(.body)

                            Spacer()

                            // Monospaced digits keep counts right-aligned.
                            Text("\(results.summary[type]!)")
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("By Category")
                }

                // Section 3: every detection in detector order, with its type
                // tag, confidence score and the exact matched text.
                Section {
                    ForEach(results.detectedEntities) { entity in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                // Type tag styled as a small pill.
                                Text(entity.type.displayName)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.quaternary)
                                    .cornerRadius(6)

                                Spacer()

                                // Confidence as a whole-number percentage.
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.green)

                                    Text(String(format: "%.0f%%", entity.score * 100))
                                        .font(.caption.monospacedDigit().weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            // The matched text itself, monospaced like the
                            // document views so it is recognisable.
                            Text(entity.text)
                                .font(.system(.body, design: .monospaced))
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary)
                                .cornerRadius(10)
                        }
                        .padding(.vertical, 6)
                    }
                } header: {
                    Text("All Detections")
                }
            }
            .navigationTitle("PII Details")
            // Large title on iOS; no-op on macOS (see ViewExtensions).
            .platformNavigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .platformTopBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        #if os(iOS)
        // Half-height by default, expandable to full, with a grab handle.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #else
        // macOS sheets size to content; give the list room for three sections.
        .frame(minWidth: 600, minHeight: 700)
        #endif
    }
}
