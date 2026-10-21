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
//  intake), `RecordDetailView` (copy vault key, share redacted file, hand
//  the redacted file to Claude or ChatGPT).
//

import SwiftUI
import UniformTypeIdentifiers

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

    /// Replaces the pasteboard with the file at `url`, typed by `kind`, so
    /// it pastes as content (an image, a PDF, text) rather than as a path.
    /// Returns `false` if the file could not be read.
    @discardableResult
    static func set(fileAt url: URL, kind: RedactionRecord.Kind) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        #if os(iOS)
        let pb = UIPasteboard.general
        switch kind {
        case .image:
            guard let image = UIImage(data: data) else { return false }
            pb.image = image
        case .text:
            pb.string = String(decoding: data, as: UTF8.self)
        case .pdf:
            pb.setData(data, forPasteboardType: UTType.pdf.identifier)
        case .docx:
            let type = UTType(filenameExtension: "docx")?.identifier ?? "org.openxmlformats.wordprocessingml.document"
            pb.setData(data, forPasteboardType: type)
        }
        return true
        #elseif os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.writeObjects([url as NSURL])
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

// MARK: - Opening another app

/// Opens another app by URL scheme, falling back to its web address when
/// the app is not installed. The completion reports which one opened.
enum AppOpener {
    static func open(_ app: URL, fallback web: URL, completion: @escaping (Bool) -> Void = { _ in }) {
        #if os(iOS)
        UIApplication.shared.open(app) { ok in
            if ok { completion(true); return }
            UIApplication.shared.open(web) { _ in completion(false) }
        }
        #elseif os(macOS)
        if NSWorkspace.shared.open(app) { completion(true) } else { NSWorkspace.shared.open(web); completion(false) }
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
