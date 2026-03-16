import SwiftUI
import StridKit

// MARK: - PIIEntityType Icon Extension

extension PIIEntityType {
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

/// Sheet displaying detailed PII scan results with categories and individual detections
struct SummarySheet: View {
    let results: ScanResults
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
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

                            Text("\(results.summary[type]!)")
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("By Category")
                }

                Section {
                    ForEach(results.detectedEntities) { entity in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(entity.type.displayName)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.quaternary)
                                    .cornerRadius(6)

                                Spacer()

                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.green)

                                    Text(String(format: "%.0f%%", entity.score * 100))
                                        .font(.caption.monospacedDigit().weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }

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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 600, minHeight: 700)
        #endif
    }
}
