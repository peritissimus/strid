//
//  HomeViewModel.swift
//  StridApp
//
//  View model behind `HomeView` and `RecordDetailView`, the file-based
//  redaction UI that `ContentView` roots. It owns the list of completed
//  `RedactionRecord`s, the kind filter, the in-flight job phase, the
//  reversible/permanent toggle, the password-retry flow for locked PDFs, and
//  a `ToastCenter` for transient feedback. Built by
//  `DIContainer.makeHomeViewModel()`.
//
//  Every intake path (Files, Photos, camera scan, clipboard, open-in URL)
//  funnels into `redact(url:name:password:)`, which builds a `RedactRequest`
//  and runs it through `RedactFileUseCase`.
//

import Foundation
import SwiftUI
import StridKit

/// Drives file intake, redaction jobs and the record list for the home screen.
///
/// `@MainActor` because SwiftUI reads all of it; `@Observable` so views only
/// re-render for the properties they touch.
@MainActor
@Observable
final class HomeViewModel {
    /// Kind filter shown as pills above the record list.
    ///
    /// Raw values are the pill labels; `Identifiable` lets `ForEach` iterate
    /// `allCases` directly.
    enum Filter: String, CaseIterable, Identifiable {
        /// Every record.
        case all = "All"
        /// PDF inputs only.
        case pdf = "PDF"
        /// Image inputs (photos, single-page scans).
        case image = "Images"
        /// Plain text and Word documents, grouped because both are text-like.
        case text = "Text"
        var id: String { rawValue }
    }

    /// Whether a redaction job is running, and which stage it is in.
    ///
    /// The stage string ("Reading", "Detecting", "Saving") comes from the use
    /// case's progress callback and is shown by `ProcessingOverlay`.
    enum Phase: Equatable { case idle, working(String) }

    /// All completed redactions, newest first as returned by the repository.
    var records: [RedactionRecord] = []

    /// Active kind filter. Changing it animates the list (see `HomeView`).
    var filter: Filter = .all

    /// Current job phase. `HomeView` shows `ProcessingOverlay` while working.
    var phase: Phase = .idle

    /// Record to navigate to. Set after a successful job; `HomeView` observes
    /// it and pushes `RecordDetailView`. Cleared when that record is deleted.
    var selected: RedactionRecord?

    /// Whether new jobs should be reversible (write a `.strid` vault keyed by
    /// a generated passphrase). Toggled by the key pill in the header.
    var reversible = true

    /// Key for the current/next reversible job. Generated per job, shown once on the result screen.
    ///
    /// Strid never persists this; `RecordDetailView` only displays it while
    /// the freshly created record is the newest one.
    var lastKey: String?

    // Password flow

    /// The request that failed because the PDF is encrypted. Retried with the
    /// user-supplied password by `submitPassword()`.
    var pendingPasswordRequest: RedactRequest?

    /// Bound to the `SecureField` in the password alert.
    var passwordInput = ""

    /// Presents the "PDF is locked" alert in `HomeView`.
    var showingPasswordPrompt = false

    /// Findings awaiting the user's review before the final redaction.
    /// Non-nil presents `ReviewView`.
    var review: ReviewState?

    /// Presents the "Your data" profile sheet.
    var showProfile = false

    /// A job paused at the review step: the request (now pointing at the
    /// temp copy made during preview) and what was found in it.
    struct ReviewState: Identifiable {
        let id = UUID()
        var request: RedactRequest
        var findings: [Finding]
    }

    /// The user's standing rules: terms, categories, whether to review.
    let profiles: ProfileStore

    /// Transient toasts (success, error, info). Shared with `RecordDetailView`
    /// so both screens render the same queue.
    let toasts = ToastCenter()

    /// Runs a redaction job end to end.
    private let redactUseCase: RedactFileUseCase
    private let previewUseCase: PreviewFindingsUseCase
    /// Rebuilds an original from a redacted file + vault + key.
    private let restoreUseCase: RestoreFileUseCase
    /// Lists and deletes stored records.
    private let repository: RedactionRecordRepositoryPort

    /// Dependency-injected initialiser. In production the same object
    /// implements both use-case protocols (see `DIContainer`).
    init(redactUseCase: RedactFileUseCase, previewUseCase: PreviewFindingsUseCase, restoreUseCase: RestoreFileUseCase,
         repository: RedactionRecordRepositoryPort, profiles: ProfileStore) {
        self.redactUseCase = redactUseCase
        self.previewUseCase = previewUseCase
        self.profiles = profiles
        self.restoreUseCase = restoreUseCase
        self.repository = repository
    }

    /// `records` narrowed by `filter`. `.text` includes `.docx` because the
    /// UI treats Word files as "text documents".
    var filtered: [RedactionRecord] {
        switch filter {
        case .all: records
        case .pdf: records.filter { $0.kind == .pdf }
        case .image: records.filter { $0.kind == .image }
        case .text: records.filter { $0.kind == .text || $0.kind == .docx }
        }
    }

    /// `true` while a job is running, regardless of stage.
    var isWorking: Bool { if case .working = phase { return true } else { return false } }

    /// Reloads `records` from the repository. Called on appear and after
    /// every job or delete.
    func load() async { records = await repository.all() }

    // MARK: Intake

    /// Entry point for every source. Copies security-scoped files immediately.
    ///
    /// Builds the `RedactRequest` with the current `reversible` setting and a
    /// freshly generated vault passphrase when reversible. Security-scoped
    /// access (Files app, open-in URLs) is started here and released by the
    /// `defer` once the job finishes, so the use case can copy the file into
    /// the sandbox before the scope closes. Temp files return `false` from
    /// `startAccessing...`, which is fine; the scope is then simply not released.
    ///
    /// - Parameters:
    ///   - url: Source file.
    ///   - name: Display name; defaults to the filename without extension.
    ///   - password: PDF password, supplied on retry from the password alert.
    func redact(url: URL, name: String? = nil, password: String? = nil) {
        let scoped = url.startAccessingSecurityScopedResource()
        let req = RedactRequest(sourceURL: url, displayName: name ?? url.deletingPathExtension().lastPathComponent,
                                password: password, reversible: reversible,
                                vaultKey: reversible ? Vault.generatePassphrase() : nil,
                                policy: profiles.profile.policy())
        Task {
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            await start(req)
        }
    }

    /// Routes a request to the review step or straight to redaction,
    /// according to the profile.
    private func start(_ request: RedactRequest) async {
        if profiles.profile.reviewBeforeRedacting {
            await preview(request)
        } else {
            await run(request)
        }
    }

    /// Detect-only pass feeding the review sheet.
    ///
    /// The preview ignores the profile's category choices (every type is
    /// detected) so the sheet can offer them back; the profile's terms and
    /// kept phrases still apply. Password errors reuse the same prompt as a
    /// full run, and `submitPassword` re-enters through `start`.
    private func preview(_ request: RedactRequest) async {
        phase = .working("Reading")
        var wide = request
        wide.policy.enabledTypes = nil
        do {
            let p = try await previewUseCase.execute(wide) { [weak self] stage in
                Task { @MainActor in self?.phase = .working(stage) }
            }
            phase = .idle
            var req = request
            req.sourceURL = p.sourceCopy
            Haptic.tap()
            review = ReviewState(request: req, findings: p.findings)
        } catch RedactFileError.passwordRequired {
            phase = .idle
            pendingPasswordRequest = request
            passwordInput = ""
            showingPasswordPrompt = true
        } catch RedactFileError.wrongPassword {
            phase = .idle
            Haptic.error()
            pendingPasswordRequest = request
            passwordInput = ""
            showingPasswordPrompt = true
            toasts.show("Wrong password", "Try again.", kind: .error)
        } catch {
            phase = .idle
            Haptic.error()
            toasts.show("Couldn't read the file", error.localizedDescription, kind: .error, seconds: 4)
        }
    }

    /// Runs the reviewed job with the sheet's choices folded into the policy.
    ///
    /// - Parameters:
    ///   - disabled: Types the user switched off in the sheet. This is the
    ///     whole truth for types, replacing the profile's sensitivity.
    ///   - excluded: Normalised values unticked individually.
    func confirmReview(disabled: Set<PIIEntityType>, excluded: Set<String>) {
        guard let rv = review else { return }
        review = nil
        var req = rv.request
        var policy = profiles.profile.policy(excluding: excluded)
        policy.enabledTypes = disabled.isEmpty ? nil : Set(PIIEntityType.allCases).subtracting(disabled)
        req.policy = policy
        let copy = req.sourceURL
        Task {
            await run(req)
            try? FileManager.default.removeItem(at: copy)
        }
    }

    /// Abandons a reviewed job and removes the temp copy of the original.
    func cancelReview() {
        guard let rv = review else { return }
        review = nil
        try? FileManager.default.removeItem(at: rv.request.sourceURL)
    }

    /// Clipboard intake: writes the text to a temp `.txt` and reuses the URL
    /// path so text goes through the same pipeline as files. A write failure
    /// surfaces as a toast rather than a crash.
    func redact(text: String, name: String = "Pasted text") {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("txt")
        do { try text.write(to: tmp, atomically: true, encoding: .utf8) } catch { toasts.show("Couldn't read clipboard", kind: .error); return }
        redact(url: tmp, name: name)
    }

    /// Executes one request and maps every outcome to UI state.
    ///
    /// Success: remember the vault key, reload the list, haptic, select the
    /// new record (which navigates to it) and toast a summary.
    /// Password required / wrong: stash the request and raise the password
    /// alert; a wrong password additionally buzzes and toasts.
    /// Anything else: error haptic and a longer-lived error toast.
    ///
    /// The progress closure arrives on an arbitrary thread, so it hops back
    /// to the main actor before touching `phase`.
    private func run(_ request: RedactRequest) async {
        phase = .working("Reading")
        do {
            let record = try await redactUseCase.execute(request) { [weak self] stage in
                Task { @MainActor in self?.phase = .working(stage) }
            }
            lastKey = request.vaultKey
            await load()
            phase = .idle
            Haptic.success()
            // Animated so the push into RecordDetailView feels settled, not abrupt.
            withAnimation(Theme.settle) { selected = record }
            toasts.show("\(record.total) items redacted", "\(record.kindLabel) · \(record.pages) page\(record.pages == 1 ? "" : "s")", kind: .success)
        } catch RedactFileError.passwordRequired {
            phase = .idle
            pendingPasswordRequest = request
            passwordInput = ""
            showingPasswordPrompt = true
        } catch RedactFileError.wrongPassword {
            phase = .idle
            Haptic.error()
            pendingPasswordRequest = request
            passwordInput = ""
            showingPasswordPrompt = true
            toasts.show("Wrong password", "Try again.", kind: .error)
        } catch {
            phase = .idle
            Haptic.error()
            toasts.show("Couldn't redact", error.localizedDescription, kind: .error, seconds: 4)
        }
    }

    /// Retries the pending request with the password typed into the alert.
    ///
    /// Dismisses the alert first so a second failure can re-present it, then
    /// re-acquires security-scoped access on the same source URL (the
    /// original scope ended when the first attempt's Task finished).
    func submitPassword() {
        guard var req = pendingPasswordRequest else { return }
        req.password = passwordInput
        pendingPasswordRequest = nil
        showingPasswordPrompt = false
        // The original security scope may have ended; the use case copies before anything else, and
        // the temp copy path is still valid for a password retry because we re-run from the same URL.
        let url = req.sourceURL
        let scoped = url.startAccessingSecurityScopedResource()
        Task {
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            await start(req)
        }
    }

    // MARK: Record actions

    /// Deletes a record (and its files, via the repository), clears the
    /// selection if it pointed at that record, reloads and toasts.
    /// Repository errors are swallowed; the reload reflects the true state.
    func delete(_ record: RedactionRecord) async {
        try? await repository.delete(id: record.id)
        if selected?.id == record.id { selected = nil }
        await load()
        toasts.show("Deleted")
    }

    /// Rebuilds the original file from a reversible record.
    ///
    /// Returns the restored file URL for sharing, or `nil` on failure (wrong
    /// key, missing vault). Feedback is delivered via haptics and toasts so
    /// the caller only needs to handle the URL.
    func restore(_ record: RedactionRecord, key: String) async -> URL? {
        do {
            let url = try await restoreUseCase.execute(record: record, key: key)
            Haptic.success()
            toasts.show("Original restored", kind: .success)
            return url
        } catch {
            Haptic.error()
            toasts.show("Couldn't restore", error.localizedDescription, kind: .error)
            return nil
        }
    }
}
