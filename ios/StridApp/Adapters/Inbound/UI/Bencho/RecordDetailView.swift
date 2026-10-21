//
//  RecordDetailView.swift
//  StridApp
//
//  Detail screen for one completed `RedactionRecord`. Pushed by `HomeView`
//  via `NavigationStack` (`navigationDestination(for: RedactionRecord.self)`),
//  either from a tapped `RecordCard` or automatically when a job finishes and
//  `HomeViewModel.selected` is set.
//
//  Layout, top to bottom: custom top bar (back, name, Redacted | Original
//  toggle), a tall file preview, the item-count summary with file facts and
//  entity chips, the vault-key card for reversible jobs, any engine warnings, and a
//  floating action row (Share redacted, Delete) pinned to the bottom.
//

import SwiftUI
import StridKit

struct RecordDetailView: View {
    /// The record being shown. Immutable; deletes go through the view model.
    let record: RedactionRecord

    /// Shared home view model for restore, delete, toasts and the one-time key.
    @Bindable var vm: HomeViewModel

    /// Pops this screen (back button, after delete).
    @Environment(\.dismiss) private var dismiss

    /// Which file the preview shows.
    enum Side: Hashable { case redacted, original }

    /// Preview side. Starts on the redacted output since that is the result
    /// the user came to check.
    @State private var side: Side = .redacted

    /// Whether the vault key is shown in clear text or as dots.
    @State private var keyRevealed = false

    /// Presents the "Restore original" alert with its key field.
    @State private var showRestore = false

    /// Key typed into the restore alert. Cleared after each attempt.
    @State private var restoreKey = ""

    /// File to hand to the share sheet. Non-nil presents the sheet; used for
    /// the redacted output, the vault and a restored original.
    @State private var shareURL: URL?

    /// Presents the delete confirmation dialog.
    @State private var confirmDelete = false

    /// Drives the fade-and-rise entrance of the scroll content.
    @State private var appeared = false

    var body: some View {
        // Bottom-aligned ZStack so the action row and toasts float over the
        // scrolling content.
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    topBar
                    preview
                    summary
                    // Key card only makes sense when a vault exists.
                    if record.reversible { keyCard }
                    // Engine warnings (e.g. OCR fallback used) are optional.
                    if !record.warnings.isEmpty { notes }
                    // Room so the last card can scroll above the floating actions.
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                // Entrance: content fades in and rises 12pt once `appeared` flips.
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            }
            .scrollIndicators(.hidden)
            BottomScrim()
            actions
            // Lifted above the action row.
            ToastStack(center: vm.toasts).padding(.bottom, 92)
        }
        // Custom top bar replaces the system navigation bar on iOS.
        .hideNavigationBar()
        .onAppear { withAnimation(Theme.settle) { appeared = true } }
        // `URL` is made Identifiable at the bottom of this file so it can
        // drive `.sheet(item:)` directly.
        .sheet(item: $shareURL) { url in ShareSheet(activityItems: [url]) }
        // Restore flow: ask for the key, run the restore, then share the
        // rebuilt original. The key field is cleared on both paths.
        .alert("Restore original", isPresented: $showRestore) {
            SecureField("Vault key", text: $restoreKey)
            Button("Restore") {
                Task { if let url = await vm.restore(record, key: restoreKey) { shareURL = url } }
                restoreKey = ""
            }
            Button("Cancel", role: .cancel) { restoreKey = "" }
        } message: { Text("Paste the key that was shown when this file was redacted.") }
        // Delete removes both files, then pops back to the home list.
        .confirmationDialog("Delete this redaction?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete original and redacted copy", role: .destructive) {
                Task { await vm.delete(record); dismiss() }
            }
        }
    }

    // MARK: Pieces

    /// Round back button, name, and the side toggle.
    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink).frame(width: 40, height: 40)
                    .background(Theme.card, in: Circle())
            }.buttonStyle(PressableStyle())
            Text(record.name).font(Theme.title()).tracking(-0.2).foregroundStyle(Theme.ink)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            SegmentedPill(options: [(Side.redacted, "Redacted"), (Side.original, "Original")], selection: $side)
                .fixedSize()
        }
    }

    /// Tall file preview with a corner badge naming the side.
    ///
    /// Both sides stay mounted and `side` only sets which one is opaque, so
    /// flipping is a cross-fade between two loaded documents rather than a
    /// reload: no blank frame while the new file decodes, and each side
    /// keeps its own scroll position. The badges work the same way.
    private var preview: some View {
        ZStack {
            DocumentPreview(url: record.inputURL, kind: record.kind)
                .opacity(side == .original ? 1 : 0)
                .allowsHitTesting(side == .original)
            DocumentPreview(url: record.outputURL, kind: record.kind)
                .opacity(side == .redacted ? 1 : 0)
                .allowsHitTesting(side == .redacted)
        }
        .frame(height: 440)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).strokeBorder(Theme.edge, lineWidth: 0.5))
        .overlay(alignment: .topLeading) {
            // Green for the safe copy, ember for the sensitive original.
            ZStack(alignment: .leading) {
                sideBadge("REDACTED", tint: Theme.ok).opacity(side == .redacted ? 1 : 0)
                sideBadge("ORIGINAL", tint: Theme.ember).opacity(side == .original ? 1 : 0)
            }
            .padding(12)
        }
        // Same spring as the segmented thumb, so the flip is one move.
        .animation(Theme.snappy, value: side)
    }

    /// Corner badge on an opaque surface with a hairline edge, so it reads
    /// over a white page without a shadow.
    private func sideBadge(_ text: String, tint: Color) -> some View {
        Badge(text: text, tint: tint)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.edge, lineWidth: 0.5))
    }

    /// Big total plus a wrapping row of per-type chips, or a reassurance
    /// line when nothing was found.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(record.total)").font(Theme.display(40)).tracking(-0.8).foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Text("items redacted").font(Theme.body()).foregroundStyle(Theme.ink3)
                Spacer()
            }
            // File facts live here rather than in the header so the title
            // and the side toggle have the full width. "PDF · 3 pages · 12 Mar 14:05"
            Text("\(record.kindLabel) · \(record.pages) page\(record.pages == 1 ? "" : "s") · \(record.createdAt, format: .dateTime.day().month().hour().minute())")
                .font(Theme.meta()).foregroundStyle(Theme.ink4)
            if record.total == 0 {
                Text("Nothing personal found. The file was copied through unchanged.")
                    .font(Theme.body()).lineSpacing(4).foregroundStyle(Theme.ink3)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(record.sortedCounts, id: \.type) { c in EntityChip(type: c.type, count: c.count) }
                }
            }
        }
        .card()
    }

    /// Vault-key card for reversible records.
    ///
    /// The key itself is only available in memory for the record that was
    /// just created (`vm.lastKey` + `isFreshRecord`); it is shown masked with
    /// reveal and copy buttons. For older records the card explains the key
    /// is gone. Restore and share-vault actions are always offered.
    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Vault key")
                Spacer()
                Image(systemName: "lock.shield").foregroundStyle(Theme.ink4).font(.system(size: 12))
            }
            if let key = vm.lastKey, isFreshRecord {
                HStack(spacing: 10) {
                    // 22 dots approximates the passphrase length without leaking it.
                    Text(keyRevealed ? key : String(repeating: "•", count: 22))
                        .font(Theme.mono()).foregroundStyle(Theme.ink)
                        .lineLimit(1).truncationMode(.middle)
                        .contentTransition(.opacity)
                    Spacer()
                    Button {
                        Haptic.tap(); withAnimation(Theme.quick) { keyRevealed.toggle() }
                    } label: { Image(systemName: keyRevealed ? "eye.slash" : "eye") }
                        .buttonStyle(GlassPillStyle())
                    Button {
                        PasteboardHelper.set(key); Haptic.success()
                        vm.toasts.show("Key copied", "Store it somewhere safe.", kind: .success)
                    } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(GlassPillStyle())
                }
                Text("Shown once. Anyone with this key and the .strid vault can rebuild the original.")
                    .font(Theme.meta()).foregroundStyle(Theme.ink4)
            } else {
                Text("The key was shown when this file was redacted. Strid does not keep it.")
                    .font(Theme.body()).lineSpacing(4).foregroundStyle(Theme.ink3)
            }
            HStack(spacing: 8) {
                Button { showRestore = true } label: { Label("Restore original", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(GlassPillStyle())
                if let v = record.vaultURL {
                    Button { shareURL = v } label: { Label("Share vault", systemImage: "shippingbox") }
                        .buttonStyle(GlassPillStyle())
                }
            }
        }
        .card()
    }

    /// `true` when this record is the newest one, which is the only case in
    /// which `vm.lastKey` belongs to it. Relies on the repository returning
    /// records newest first.
    private var isFreshRecord: Bool { vm.records.first?.id == record.id }

    /// Bulleted list of engine warnings from the redaction report.
    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Notes")
            ForEach(record.warnings, id: \.self) { w in
                HStack(alignment: .top, spacing: 8) {
                    // 4pt bullet nudged down to the first line's x-height.
                    Circle().fill(Theme.ink4).frame(width: 4, height: 4).padding(.top, 7)
                    Text(w).font(Theme.body()).lineSpacing(4).foregroundStyle(Theme.ink3)
                }
            }
        }
        .card(padding: 16)
    }

    /// Copies the redacted file to the pasteboard and opens the assistant,
    /// or its website when the app is not installed, with a toast saying
    /// what to do next.
    private func handOff(to a: Assistant) {
        Haptic.tap()
        guard PasteboardHelper.set(fileAt: record.outputURL, kind: record.kind) else {
            vm.toasts.show("Couldn't copy the file", "Try sharing it instead.", kind: .error)
            return
        }
        // Toast first and a little longer than usual: the app switch happens
        // right after, so a toast shown on completion would play while the
        // other app is in front and be gone by the time the user comes back.
        vm.toasts.show("Copied for \(a.name)", "Paste it into the chat.", kind: .success, seconds: 5)
        AppOpener.open(a.appURL, fallback: a.webURL)
    }

    /// Floating bottom row: primary "Share redacted" pill, two round
    /// assistant hand-off buttons, and a round delete button.
    private var actions: some View {
        HStack(spacing: 10) {
            Button { Haptic.tap(); shareURL = record.outputURL } label: {
                HStack(spacing: 8) { Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .semibold)); Text("Share redacted") }
            }
            .buttonStyle(PrimaryPillStyle())
            ForEach(Assistant.allCases) { a in
                AssistantButton(assistant: a) { handOff(to: a) }
            }
            Button { confirmDelete = true } label: {
                Image(systemName: "trash").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                    .frame(width: 46, height: 46)
                    .background(Theme.surface2, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.edge, lineWidth: 0.5))
            }
            .buttonStyle(PressableStyle())
        }
        .floating()
        .padding(.bottom, 18)
    }
}

/// Lets a `URL` drive `.sheet(item:)` directly. `@retroactive` acknowledges
/// that we are conforming a type we do not own to a protocol we do not own.
extension URL: @retroactive Identifiable { public var id: String { absoluteString } }
