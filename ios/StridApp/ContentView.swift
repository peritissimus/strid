import SwiftUI
import StridKit

struct ContentView: View {
    @State private var viewModel: DocumentViewModel
    @State private var showingFilePicker = false
    @State private var exportedFileURL: URL?
    @State private var showingShareSheet = false
    @State private var exportError: Error?
    @State private var showingExportError = false

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
                Color.stridMonochromeGradient
                    .ignoresSafeArea()

                VStack(spacing: 40) {
                    Spacer()

                    VStack(spacing: 24) {
                        Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                            .font(.system(size: 80, weight: .light))
                            .foregroundStyle(Color.stridWhite)

                        VStack(spacing: 12) {
                            Text("PII Scanner")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(Color.stridWhite)

                            Text("Detect and redact personal information\nfrom your documents")
                                .font(.body)
                                .foregroundStyle(Color.stridWhite.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                        }
                    }

                    VStack(spacing: 14) {
                        // Primary CTA - only place using accent color
                        Button {
                            viewModel.toggleSamplePicker()
                        } label: {
                            HStack {
                                Image(systemName: "doc.text.magnifyingglass")
                                Text("Browse Sample Documents")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.stridAccent)
                            .foregroundStyle(Color.stridWhite)
                            .cornerRadius(14)
                        }

                        // Glass buttons
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
                            .background(Color.stridGlass)
                            .foregroundStyle(Color.stridWhite)
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.stridGlassBorder, lineWidth: 1)
                            )
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
                            .background(Color.stridGlass)
                            .foregroundStyle(Color.stridWhite)
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.stridGlassBorder, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 40)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.toggleHistory()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Color.stridWhite)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingHistory) {
                historySheet
            }
            .sheet(isPresented: $viewModel.showingSamplePicker) {
                samplePickerSheet
            }
        }
    }

    private var documentLoadedView: some View {
        NavigationStack {
            ZStack {
                Color.stridBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        Text(viewModel.sourceText)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Color.stridText)
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }

                    VStack(spacing: 12) {
                        // Primary action - uses accent
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
                            .background(Color.stridAccent)
                            .foregroundStyle(Color.stridWhite)
                            .cornerRadius(12)
                        }

                        // Secondary action - monochrome
                        Button {
                            showingFilePicker = true
                        } label: {
                            Text("Replace Document")
                                .font(.subheadline)
                                .foregroundStyle(Color.stridTextSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.stridGray)
                    }
                    .padding(20)
                    .background(
                        Color.stridGlass
                            .overlay(
                                Rectangle()
                                    .fill(Color.stridGlassBorder)
                                    .frame(height: 1),
                                alignment: .top
                            )
                    )
                }
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
                        .foregroundStyle(Color.stridDarkGray)
                    }
                }
            }
        }
    }

    private var processingView: some View {
        NavigationStack {
            ZStack {
                Color.stridMonochromeGradient
                    .ignoresSafeArea()

                VStack(spacing: 30) {
                    Spacer()

                    ProgressView()
                        .scaleEffect(1.8)
                        .tint(Color.stridWhite)

                    VStack(spacing: 8) {
                        Text("Analyzing Document")
                            .font(.title2.bold())
                            .foregroundStyle(Color.stridWhite)

                        Text("Scanning for personal information...")
                            .font(.subheadline)
                            .foregroundStyle(Color.stridWhite.opacity(0.7))
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
                // Stats header with glass effect
                VStack(spacing: 16) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(viewModel.entityCount)")
                                .font(.system(size: 44, weight: .bold))
                                .foregroundStyle(Color.stridError)

                            Text("PII Items Found")
                                .font(.subheadline)
                                .foregroundStyle(Color.stridTextSecondary)
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
                            .foregroundStyle(Color.stridText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.stridGray)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    Picker("View Mode", selection: $viewModel.viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(Color.stridBlack)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .background(Color.stridBackgroundSecondary)

                Divider()
                    .background(Color.stridLightGray)

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
                        .foregroundStyle(Color.stridDarkGray)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await exportRedactedDocument()
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(Color.stridAccent)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingSummary) {
                summarySheet
            }
            .sheet(isPresented: $showingShareSheet, onDismiss: {
                exportedFileURL = nil
            }) {
                if let url = exportedFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .alert("Export Error", isPresented: $showingExportError) {
                Button("OK", role: .cancel) {}
            } message: {
                if let error = exportError {
                    Text(error.localizedDescription)
                }
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
                .foregroundStyle(Color.stridText)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .background(Color.stridBackground)
    }

    private var highlightedTextView: some View {
        ScrollView {
            Text(buildHighlightedText())
                .font(.system(.body, design: .monospaced))
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .background(Color.stridBackground)
    }

    private var redactedTextView: some View {
        ScrollView {
            Text(viewModel.redactedText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Color.stridText)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .background(Color.stridBackground)
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
                                Image(systemName: viewModel.iconForType(type))
                                    .font(.title3)
                                    .foregroundStyle(viewModel.colorForType(type))
                                    .frame(width: 30)

                                Text(type.displayName)
                                    .font(.body)
                                    .foregroundStyle(Color.stridText)

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
                            .foregroundStyle(Color.stridBlack)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var samplePickerSheet: some View {
        NavigationStack {
            List {
                ForEach(SampleDocument.SampleCategory.allCases, id: \.self) { category in
                    Section {
                        ForEach(viewModel.sampleDocuments.filter { $0.category == category }) { sample in
                            Button {
                                Task {
                                    await viewModel.loadSampleDocument(sample)
                                }
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: category.icon)
                                        .font(.title2)
                                        .foregroundStyle(Color.stridAccent)
                                        .frame(width: 40)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(sample.title)
                                            .font(.headline)
                                            .foregroundStyle(Color.stridText)

                                        Text(sample.description)
                                            .font(.caption)
                                            .foregroundStyle(Color.stridTextSecondary)
                                            .lineLimit(2)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(Color.stridGray)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    } header: {
                        Text(category.rawValue)
                    }
                }
            }
            .navigationTitle("Sample Documents")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.toggleSamplePicker()
                    } label: {
                        Text("Cancel")
                            .foregroundStyle(Color.stridBlack)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var historySheet: some View {
        NavigationStack {
            List {
                if viewModel.redactionHistory.isEmpty {
                    ContentUnavailableView {
                        Label("No Redaction History", systemImage: "clock.badge.questionmark")
                    } description: {
                        Text("Your redaction operations will appear here")
                    }
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Total Redactions")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.stridTextSecondary)

                                    Text("\(viewModel.totalRedactionCount)")
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundStyle(Color.stridAccent)
                                }

                                Spacer()

                                Image(systemName: "clock.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(Color.stridAccent.opacity(0.15))
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    Section {
                        ForEach(viewModel.redactionHistory) { entry in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.formattedDate)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(Color.stridText)

                                        Text("\(entry.entitiesFound) PII items found")
                                            .font(.caption)
                                            .foregroundStyle(Color.stridTextSecondary)
                                    }

                                    Spacer()

                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.stridSuccess)
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(entry.entityTypes, id: \.self) { type in
                                            Text(type.displayName)
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(viewModel.colorForType(type).opacity(0.12))
                                                .foregroundStyle(viewModel.colorForType(type))
                                                .cornerRadius(4)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("Recent Activity")
                    }
                }
            }
            .navigationTitle("Redaction History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.toggleHistory()
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

    // MARK: - Actions

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
                attributed[range].foregroundColor = Color.stridError
                attributed[range].font = .body.monospaced().bold()
                attributed[range].backgroundColor = Color.stridError.opacity(0.1)
            }
        }

        return attributed
    }

    private func exportRedactedDocument() async {
        do {
            let url = try await viewModel.exportRedactedDocument()
            exportedFileURL = url
            showingShareSheet = true
        } catch {
            exportError = error
            showingExportError = true
        }
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ContentView()
}
