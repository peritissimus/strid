import SwiftUI

/// View shown when no documents have been scanned yet (welcome screen)
struct EmptyDetailView: View {
    @Bindable var viewModel: DocumentListViewModel
    @State private var showingFilePicker = false

    var body: some View {
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
                    // Primary CTA - accent color
                    Button {
                        viewModel.showingSamplePicker = true
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
                            if let clip = PasteboardHelper.getString(), !clip.isEmpty {
                                await viewModel.createNewDocument(content: clip)
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
