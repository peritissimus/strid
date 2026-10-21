//
//  PreviewFindingsUseCase.swift
//  StridApp
//
//  The detect-only half of a job, run before the review sheet. Copies the
//  source into the app's temp directory (so the picker's security scope can
//  end), extracts its text the same way the redactor would, and returns the
//  findings under the request's policy. The copy's URL is handed back so the
//  eventual redaction reads the same bytes.
//

import Foundation
import StridKit
import StridDocuments

/// One detected value as the review sheet sees it.
struct Finding: Sendable, Hashable, Identifiable {
    var id: String { "\(type.rawValue)|\(normalised)" }
    let type: PIIEntityType
    /// Text as it appears in the document (first occurrence's spelling).
    let text: String
    /// `RedactionPolicy.normalise(text)`, the key the policy excludes by.
    let normalised: String
    /// How many times it occurs.
    var count: Int
    /// From a profile term: shown but not switchable.
    let locked: Bool
}

/// Result of a preview: where the copy lives, and what was found.
struct Preview: Sendable {
    var sourceCopy: URL
    var findings: [Finding]
}

protocol PreviewFindingsUseCase: Sendable {
    func execute(_ request: RedactRequest, progress: @Sendable @escaping (String) -> Void) async throws -> Preview
}

extension RedactFileUseCaseImpl: PreviewFindingsUseCase {
    func execute(_ request: RedactRequest, progress: @Sendable @escaping (String) -> Void) async throws -> Preview {
        guard DocumentKind.detect(url: request.sourceURL) != nil else {
            throw RedactFileError.unsupported(request.sourceURL.pathExtension)
        }
        progress("Reading")
        let ext = request.sourceURL.pathExtension.isEmpty ? "txt" : request.sourceURL.pathExtension
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-\(UUID().uuidString)").appendingPathExtension(ext)
        try FileManager.default.copyItem(at: request.sourceURL, to: copy)

        progress("Detecting")
        let options = DocumentOptions(password: request.password, ocrFallback: true, policy: request.policy)
        let engine = self.engine
        let entities: [PIIEntity]
        do {
            entities = try await Task.detached(priority: .userInitiated) {
                let text = try DocumentText.extract(from: copy, options: options)
                return engine.detect(in: text, policy: options.policy)
            }.value
        } catch DocumentRedactionError.passwordRequired {
            try? FileManager.default.removeItem(at: copy)
            throw RedactFileError.passwordRequired
        } catch DocumentRedactionError.wrongPassword {
            try? FileManager.default.removeItem(at: copy)
            throw RedactFileError.wrongPassword
        } catch {
            try? FileManager.default.removeItem(at: copy)
            throw RedactFileError.failed(error.localizedDescription)
        }

        // Group by type + normalised value, keeping first-seen order.
        var order: [String] = []
        var byKey: [String: Finding] = [:]
        let lockedKeys = Set(request.policy.alwaysRedact.map { "\($0.type.rawValue)|\(RedactionPolicy.normalise($0.text))" })
        for e in entities {
            let norm = RedactionPolicy.normalise(e.text)
            let key = "\(e.type.rawValue)|\(norm)"
            if var f = byKey[key] {
                f.count += 1
                byKey[key] = f
            } else {
                order.append(key)
                byKey[key] = Finding(type: e.type, text: e.text, normalised: norm, count: 1, locked: lockedKeys.contains(key))
            }
        }
        return Preview(sourceCopy: copy, findings: order.compactMap { byKey[$0] })
    }
}
