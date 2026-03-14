import SwiftUI
import StridKit

struct ContentView: View {
    @State private var sourceText = ""
    @State private var entities: [PIIEntity] = []
    @State private var redactedText = ""
    @State private var showingFilePicker = false
    @State private var showingResults = false
    @State private var isProcessing = false
    @State private var selectedTab: Tab = .input

    private let engine = StridEngine()

    enum Tab {
        case input, detected, redacted
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("View", selection: $selectedTab) {
                    Text("Input").tag(Tab.input)
                    Text("Detected (\(entities.count))").tag(Tab.detected)
                    Text("Redacted").tag(Tab.redacted)
                }
                .pickerStyle(.segmented)
                .padding()

                // Content
                switch selectedTab {
                case .input:
                    inputView
                case .detected:
                    detectedView
                case .redacted:
                    redactedView
                }
            }
            .navigationTitle("Strid")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Import File", systemImage: "doc") {
                            showingFilePicker = true
                        }
                        Button("Paste from Clipboard", systemImage: "clipboard") {
                            if let clip = UIPasteboard.general.string {
                                sourceText = clip
                            }
                        }
                        if !sourceText.isEmpty {
                            Button("Clear", systemImage: "trash", role: .destructive) {
                                sourceText = ""
                                entities = []
                                redactedText = ""
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !sourceText.isEmpty {
                        Button("Scan") {
                            processText()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isProcessing)
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.plainText, .pdf, .commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
    }

    // MARK: - Tab Views

    private var inputView: some View {
        Group {
            if sourceText.isEmpty {
                ContentUnavailableView {
                    Label("No Document", systemImage: "doc.text")
                } description: {
                    Text("Import a file or paste text to scan for PII.")
                }
            } else {
                ScrollView {
                    Text(sourceText)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var detectedView: some View {
        Group {
            if entities.isEmpty {
                ContentUnavailableView {
                    Label("No PII Found", systemImage: "checkmark.shield")
                } description: {
                    Text(sourceText.isEmpty
                         ? "Import a document and tap Scan."
                         : "No PII was detected. Try lowering the threshold.")
                }
            } else {
                List {
                    // Summary section
                    Section("Summary") {
                        let counts = Dictionary(grouping: entities, by: \.type)
                        ForEach(counts.keys.sorted(by: { counts[$0]!.count > counts[$1]!.count }), id: \.self) { type in
                            HStack {
                                Label(type.displayName, systemImage: iconForType(type))
                                Spacer()
                                Text("\(counts[type]!.count)")
                                    .foregroundStyle(.secondary)
                                    .fontDesign(.monospaced)
                            }
                        }
                    }

                    // Detail section
                    Section("All Findings (\(entities.count))") {
                        ForEach(entities) { entity in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entity.type.displayName)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(colorForType(entity.type), in: Capsule())
                                    Spacer()
                                    Text(String(format: "%.0f%%", entity.score * 100))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(entity.text)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.red)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }

    private var redactedView: some View {
        Group {
            if redactedText.isEmpty {
                ContentUnavailableView {
                    Label("Not Yet Redacted", systemImage: "eye.slash")
                } description: {
                    Text("Tap Scan to detect and redact PII.")
                }
            } else {
                VStack {
                    ScrollView {
                        Text(redactedText)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }

                    // Action bar
                    HStack(spacing: 16) {
                        ShareLink(item: redactedText) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            UIPasteboard.general.string = redactedText
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - Actions

    private func processText() {
        isProcessing = true
        Task.detached {
            let detected = engine.detect(in: sourceText)
            let redacted = engine.redact(sourceText)
            await MainActor.run {
                entities = detected
                redactedText = redacted
                isProcessing = false
                selectedTab = .detected
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        if let text = try? String(contentsOf: url, encoding: .utf8) {
            sourceText = text
            entities = []
            redactedText = ""
            selectedTab = .input
        }
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
        case .person, .inDOB: .red
        case .email, .url: .blue
        case .phone, .inPhone: .green
        case .location, .inPINCode: .orange
        case .creditCard, .inBankAccount: .purple
        case .inIFSC, .inBranchCode, .inMICR: .brown
        case .inPAN, .inAadhaar, .inCustomerID: .red
        case .inUPIID, .inTxnRef: .indigo
        case .organization: .teal
        case .ipAddress: .gray
        }
    }
}

#Preview {
    ContentView()
}
