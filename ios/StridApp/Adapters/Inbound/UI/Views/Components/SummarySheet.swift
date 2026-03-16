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
                                    .foregroundStyle(Color.stridTextSecondary)

                                Text("\(results.entityCount)")
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundStyle(Color.stridError)
                            }

                            Spacer()

                            Image(systemName: "exclamationmark.shield.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(Color.stridError.opacity(0.15))
                        }
                    }
                    .padding(.vertical, 12)
                }

                Section {
                    ForEach(results.summary.keys.sorted(by: { results.summary[$0]! > results.summary[$1]! }), id: \.self) { type in
                        HStack(spacing: 14) {
                            Image(systemName: iconForType(type))
                                .font(.title3)
                                .foregroundStyle(colorForType(type))
                                .frame(width: 30)

                            Text(type.displayName)
                                .font(.body)
                                .foregroundStyle(Color.stridText)

                            Spacer()

                            Text("\(results.summary[type]!)")
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(colorForType(type))
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
                                    .background(colorForType(entity.type).opacity(0.12))
                                    .foregroundStyle(colorForType(entity.type))
                                    .cornerRadius(6)

                                Spacer()

                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption2)
                                        .foregroundStyle(Color.stridSuccess)

                                    Text(String(format: "%.0f%%", entity.score * 100))
                                        .font(.caption.monospacedDigit().weight(.medium))
                                        .foregroundStyle(Color.stridTextSecondary)
                                }
                            }

                            Text(entity.text)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(Color.stridText)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.stridLightGray.opacity(0.3))
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
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.stridBlack)
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

    private func colorForType(_ type: PIIEntityType) -> Color {
        switch type {
        // Critical PII - Error red
        case .person, .inDOB, .inPAN, .inAadhaar, .creditCard, .inBankAccount:
            .stridError

        // Contact information - Accent teal
        case .email, .url, .phone, .inPhone, .inUPIID:
            .stridAccent

        // Location information - Warning orange
        case .location, .inPINCode:
            .stridWarning

        // Financial/Banking codes - Info blue
        case .inIFSC, .inBranchCode, .inMICR, .inTxnRef:
            .stridInfo

        // Organizational/Generic - Dark gray
        case .organization, .inCustomerID, .ipAddress:
            .stridDarkGray
        }
    }
}
