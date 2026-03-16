import SwiftUI
import StridKit

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
                    ForEach(results.summary.keys.sorted(by: { results.summary[$0]! > results.summary[$1]! }), id: \.self) { type in
                        HStack(spacing: 14) {
                            Image(systemName: iconForType(type))
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    private func iconForType(_ type: PIIEntityType) -> String {
        switch type {
        case .person: "person"
        case .email: "envelope"
        case .phone, .inPhone: "phone"
        case .url: "link"
        case .location: "mappin"
        case .organization: "building.2"
        case .creditCard: "creditcard"
        case .ipAddress: "network"
        case .inBankAccount: "banknote"
        case .inIFSC: "building.columns"
        case .inPAN: "doc.text"
        case .inAadhaar: "person.text.rectangle"
        case .inUPIID: "indianrupeesign.circle"
        case .inMICR: "barcode"
        case .inPINCode: "mappin.and.ellipse"
        case .inCustomerID: "person.badge.key"
        case .inBranchCode: "number"
        case .inTxnRef: "number.circle"
        case .inDOB: "calendar"
        }
    }

}
