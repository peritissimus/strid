//
//  DocumentScannerView.swift
//  StridApp
//
//  iOS-only camera scanner used by `HomeView`'s "Scan with camera" action.
//  Presented as a full-screen cover; when the user finishes, the captured
//  pages are written to a temp file and handed back as a URL, which
//  `HomeViewModel.redact(url:name:)` then treats like any other input file.
//
//  VisionKit's scanner already does edge detection, perspective correction and
//  multi-page capture, so this file is only glue plus the "pages -> one file"
//  packaging decision described on the type.
//

#if os(iOS)
import SwiftUI
import VisionKit
import PDFKit

/// Wraps VNDocumentCameraViewController. Multi-page scans are written as a single PDF of images,
/// which the OCR path then redacts page by page.
struct DocumentScannerView: UIViewControllerRepresentable {
    /// Called exactly once when the scanner closes: with a temp-file URL on
    /// success, or `nil` on cancel / error. The caller is responsible for
    /// dismissing the cover.
    let completion: (URL?) -> Void

    /// Creates the system scanner and routes its delegate callbacks to the
    /// coordinator.
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    /// The scanner has no SwiftUI-driven configuration; nothing to update.
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    /// Delegate object that turns VisionKit callbacks into a single file URL.
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let completion: (URL?) -> Void
        init(completion: @escaping (URL?) -> Void) { self.completion = completion }

        /// Packages the scan into one file in the temp directory.
        ///
        /// - A single page is saved as a JPEG so it flows through the image
        ///   redaction path (OCR + box painting).
        /// - Multiple pages are stacked into a PDF of full-page images so the
        ///   PDF path can OCR and redact each page while keeping one output file.
        ///
        /// The base name is a fresh UUID so repeated scans never collide.
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            if scan.pageCount == 1 {
                let url = tmp.appendingPathExtension("jpg")
                // 0.9 keeps text crisp for OCR while bounding file size.
                try? scan.imageOfPage(at: 0).jpegData(compressionQuality: 0.9)?.write(to: url)
                completion(url)
                return
            }
            let url = tmp.appendingPathExtension("pdf")
            let doc = PDFDocument()
            for i in 0..<scan.pageCount {
                // PDFPage(image:) can fail for an unusable image; skip it rather than abort.
                if let page = PDFPage(image: scan.imageOfPage(at: i)) { doc.insert(page, at: i) }
            }
            doc.write(to: url)
            completion(url)
        }

        /// User tapped Cancel: report "no file" so the caller just dismisses.
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { completion(nil) }

        /// Camera failure (permissions, hardware): treated the same as cancel.
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { completion(nil) }
    }
}
#endif
