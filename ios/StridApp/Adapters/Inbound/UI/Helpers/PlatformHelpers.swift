//
//  PlatformHelpers.swift
//  StridApp
//
//  Thin wrappers over the UIKit / AppKit APIs the UI layer needs that have
//  no SwiftUI equivalent: the system pasteboard and a "get this file out of
//  the app" sheet. Each helper has one implementation per platform behind
//  `#if os(...)` so callers stay platform-agnostic.
//
//  Used by: `EmptyDetailView`, `DocumentSidebarView` and `HomeView` (paste
//  intake), `RecordDetailView` (copy vault key, share redacted file).
//

import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Pasteboard

/// Read and write plain strings on the general pasteboard.
struct PasteboardHelper {
    /// Replaces the pasteboard contents with `string`.
    ///
    /// On macOS the pasteboard must be cleared first or `setString` fails;
    /// on iOS assignment replaces the contents.
    static func set(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }

    /// The current plain-text pasteboard contents, or `nil` if there is none.
    /// Callers treat an empty string as "nothing to paste".
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
/// SwiftUI wrapper around `UIActivityViewController`, presented with
/// `.sheet(item:)` from `RecordDetailView`. Items are typically file URLs.
struct ShareSheet: UIViewControllerRepresentable {
    /// Items to offer to the activity sheet (URLs, strings, images...).
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }

    /// The activity controller is one-shot; nothing to update.
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#elseif os(macOS)
/// macOS stand-in for the iOS share sheet.
///
/// There is no activity sheet on macOS, so this is a small panel with a
/// "Save As..." button that opens an `NSSavePanel` and copies the first URL
/// item to the chosen destination. Non-URL items render an empty panel.
struct ShareSheet: View {
    /// Items to share. Only the first element, if it is a `URL`, is used.
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
                        // Suggest the temp file's own name (e.g. redacted.pdf).
                        savePanel.nameFieldStringValue = url.lastPathComponent
                        savePanel.canCreateDirectories = true

                        // runModal blocks until the user confirms or cancels.
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
        // Fixed, compact sheet size; the content is a single row.
        .frame(width: 400, height: 100)
    }
}
#endif
