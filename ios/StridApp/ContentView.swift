import SwiftUI
import StridKit

struct ContentView: View {
    @State private var viewModel: DocumentViewModel
    @State private var showingFilePicker = false

    init() {
        let vm = DIContainer.shared.makeDocumentViewModel()
        _viewModel = State(initialValue: vm)
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .empty:
                emptyStateView
            case .loaded:
                documentLoadedView
            case .processing:
                processingView
            case .scanned:
                resultsView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.state)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.plainText, .pdf, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - State Views

    private var emptyStateView: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.2, blue: 0.5),
                        Color(red: 0.2, green: 0.1, blue: 0.4)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 40) {
                    Spacer()

                    VStack(spacing: 24) {
                        Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                            .font(.system(size: 80, weight: .light))
                            .foregroundStyle(.white)

                        VStack(spacing: 12) {
                            Text("PII Scanner")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(.white)

                            Text("Detect and redact personal information\nfrom your documents")
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                        }
                    }

                    VStack(spacing: 14) {
                        Button {
                            Task {
                                await loadSampleDocument()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                Text("Try Sample Document")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.white)
                            .foregroundStyle(Color(red: 0.1, green: 0.2, blue: 0.5))
                            .cornerRadius(14)
                        }

                        Button {
                            showingFilePicker = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                Text("Import Document")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.white.opacity(0.2))
                            .foregroundStyle(.white)
                            .cornerRadius(14)
                        }

                        Button {
                            Task {
                                if let clip = UIPasteboard.general.string, !clip.isEmpty {
                                    await viewModel.importDocument(content: clip)
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "doc.on.clipboard")
                                Text("Paste from Clipboard")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.white.opacity(0.2))
                            .foregroundStyle(.white)
                            .cornerRadius(14)
                        }
                    }
                    .padding(.horizontal, 40)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var documentLoadedView: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    Text(viewModel.sourceText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .background(Color(.systemBackground))

                Divider()

                VStack(spacing: 12) {
                    Button {
                        Task {
                            await viewModel.scanDocument()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text("Scan for PII")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }

                    Button {
                        showingFilePicker = true
                    } label: {
                        Text("Replace Document")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(20)
                .background(Color(.secondarySystemBackground))
            }
            .navigationTitle("Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.clearDocument()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                }
            }
        }
    }

    private var processingView: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.2, blue: 0.5),
                        Color(red: 0.2, green: 0.1, blue: 0.4)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 30) {
                    Spacer()

                    ProgressView()
                        .scaleEffect(1.8)
                        .tint(.white)

                    VStack(spacing: 8) {
                        Text("Analyzing Document")
                            .font(.title2.bold())
                            .foregroundStyle(.white)

                        Text("Scanning for personal information...")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var resultsView: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Stats header
                VStack(spacing: 16) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(viewModel.entityCount)")
                                .font(.system(size: 44, weight: .bold))
                                .foregroundStyle(.red)

                            Text("PII Items Found")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            viewModel.toggleSummary()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "list.bullet.rectangle.portrait")
                                    .font(.title2)
                                Text("Details")
                                    .font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    Picker("View Mode", selection: $viewModel.viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .background(Color(.secondarySystemBackground))

                Divider()

                contentForViewMode
            }
            .navigationTitle("Scan Results")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.goBackToDocument()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Document")
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingSummary) {
                summarySheet
            }
        }
    }

    @ViewBuilder
    private var contentForViewMode: some View {
        switch viewModel.viewMode {
        case .original:
            originalTextView
        case .highlighted:
            highlightedTextView
        case .redacted:
            redactedTextView
        }
    }

    private var originalTextView: some View {
        ScrollView {
            Text(viewModel.sourceText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .background(Color(.systemBackground))
    }

    private var highlightedTextView: some View {
        ScrollView {
            Text(buildHighlightedText())
                .font(.system(.body, design: .monospaced))
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .background(Color(.systemBackground))
    }

    private var redactedTextView: some View {
        ScrollView {
            Text(viewModel.redactedText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .background(Color(.systemBackground))
    }

    private var summarySheet: some View {
        NavigationStack {
            List {
                if let results = viewModel.results {
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
                                Image(systemName: viewModel.iconForType(type))
                                    .font(.title3)
                                    .foregroundStyle(viewModel.colorForType(type))
                                    .frame(width: 30)

                                Text(type.displayName)
                                    .font(.body)

                                Spacer()

                                Text("\(results.summary[type]!)")
                                    .font(.title3.bold().monospacedDigit())
                                    .foregroundStyle(viewModel.colorForType(type))
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
                                        .background(viewModel.colorForType(entity.type).opacity(0.12))
                                        .foregroundStyle(viewModel.colorForType(entity.type))
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
                                    .foregroundStyle(.primary)
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.tertiarySystemBackground))
                                    .cornerRadius(10)
                            }
                            .padding(.vertical, 6)
                        }
                    } header: {
                        Text("All Detections")
                    }
                }
            }
            .navigationTitle("PII Details")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.toggleSummary()
                    } label: {
                        Text("Done")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Actions

    private func loadSampleDocument() async {
        let sampleText = """
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
            """
        await viewModel.importDocument(content: sampleText)
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        if let text = try? String(contentsOf: url, encoding: .utf8) {
            Task {
                await viewModel.importDocument(content: text)
            }
        }
    }

    private func buildHighlightedText() -> AttributedString {
        guard let results = viewModel.results else {
            return AttributedString(viewModel.sourceText)
        }

        var attributed = AttributedString(viewModel.sourceText)

        for entity in results.detectedEntities {
            if let range = Range(entity.range, in: attributed) {
                attributed[range].foregroundColor = .red
                attributed[range].font = .body.monospaced().bold()
                attributed[range].backgroundColor = Color.red.opacity(0.1)
            }
        }

        return attributed
    }
}

#Preview {
    ContentView()
}
