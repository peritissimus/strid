import SwiftUI

/// View shown when no documents have been scanned yet (welcome screen)
struct EmptyDetailView: View {
    @Bindable var viewModel: DocumentListViewModel
    @State private var showingFilePicker = false

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    Text("PII Scanner")
                        .font(.largeTitle.bold())

                    Text("Detect and redact personal information\nfrom your documents")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            VStack(spacing: 14) {
                Button {
                    viewModel.showingSamplePicker = true
                } label: {
                    Label("Browse Sample Documents", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    showingFilePicker = true
                } label: {
                    Label("Import Document", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    Task {
                        if let clip = PasteboardHelper.getString(), !clip.isEmpty {
                            await viewModel.createNewDocument(content: clip)
                        }
                    }
                } label: {
                    Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.plainText, .pdf, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        if let text = try? String(contentsOf: url, encoding: .utf8) {
            Task {
                await viewModel.createNewDocument(content: text)
            }
        }
    }
}
