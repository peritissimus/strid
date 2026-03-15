import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Pasteboard

struct PasteboardHelper {
    static func getString() -> String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #elseif os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #endif
    }
}

// MARK: - Share Sheet

#if os(iOS)
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
#elseif os(macOS)
struct ShareSheet: View {
    let activityItems: [Any]

    var body: some View {
        VStack {
            if let url = activityItems.first as? URL {
                HStack(spacing: 16) {
                    Text("File ready to save")
                        .font(.headline)

                    Spacer()

                    Button("Save As...") {
                        let savePanel = NSSavePanel()
                        savePanel.allowedContentTypes = [.plainText]
                        savePanel.nameFieldStringValue = url.lastPathComponent
                        savePanel.canCreateDirectories = true

                        if savePanel.runModal() == .OK {
                            if let destination = savePanel.url {
                                try? FileManager.default.copyItem(at: url, to: destination)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .frame(width: 400, height: 100)
    }
}
#endif
