//
//  HomeView.swift
//  StridApp
//
//  Root screen of the app. `ContentView` creates it with
//  `DIContainer.shared.makeHomeViewModel()`. It shows the header with the
//  reversible/permanent toggle, the list of past `RedactionRecord`s behind
//  kind filters, a floating "Redact" menu (Files, camera, clipboard) plus a
//  Photos picker, and a processing overlay while a job runs. Completed jobs
//  push `RecordDetailView` through the `NavigationStack`.
//
//  This file also defines the small views only the home screen uses:
//  `RecordCard`, `Thumb`, `EmptyState`, `ProcessingOverlay`, and the
//  `hideNavigationBar()` helper shared with the detail screen.
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(PhotosUI)
import PhotosUI
#endif

struct HomeView: View {
    /// Owned here as `@State` so the view model lives as long as the root
    /// screen. Injected by `ContentView`.
    @State var vm: HomeViewModel

    /// Presents the Files importer.
    @State private var showFiles = false

    /// Presents the camera scanner cover (iOS only).
    @State private var showScanner = false

    /// Selection from the Photos picker. Reset to nil after it is consumed so
    /// picking the same photo twice still triggers `onChange`.
    @State private var photoItem: PhotosPickerItem?

    /// Navigation path. Holds at most one record; set programmatically when a
    /// job finishes and by `NavigationLink(value:)` taps.
    @State private var path: [RedactionRecord] = []

    var body: some View {
        NavigationStack(path: $path) {
            // Bottom-aligned so the floating bar, toasts and overlay stack on
            // top of the scrolling content.
            ZStack(alignment: .bottom) {
                Theme.bg.ignoresSafeArea()
                content
                BottomScrim()
                floatingBar
                // Lifted above the floating bar.
                ToastStack(center: vm.toasts).padding(.bottom, 78)
                // Always mounted; opacity is a fixed transform of `isWorking`, so the
                // fade never depends on a removal transition firing.
                ProcessingOverlay(stage: stageText, active: vm.isWorking)
                    .opacity(vm.isWorking ? 1 : 0)
                    .allowsHitTesting(vm.isWorking)
                    .animation(Theme.quick, value: vm.isWorking)
            }
            .navigationDestination(for: RedactionRecord.self) { r in
                RecordDetailView(record: r, vm: vm)
            }
            // Custom header replaces the system bar on iOS.
            .hideNavigationBar()
        }
        // The Bencho palette is dark-only.
        .preferredColorScheme(.dark)
        .tint(Theme.ink)
        .task { await vm.load() }
        // Programmatic push: when the view model selects a record (after a
        // job completes) replace the path with that single record.
        .onChange(of: vm.selected) { _, new in
            if let new { path = [new] }
        }
        // "Open in Strid" from other apps / Files.
        .onOpenURL { url in vm.redact(url: url) }
        // Files app. `fileImporter` with a single-URL result variant.
        .fileImporter(isPresented: $showFiles, allowedContentTypes: Self.importTypes) { result in
            if case .success(let url) = result { vm.redact(url: url) }
        }
        // Photos picker: load the bytes, write them to a temp file with the
        // right extension so DocumentKind can detect it, then redact. The
        // selection is cleared afterwards so the same photo can be re-picked.
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let ext = (item.supportedContentTypes.first?.preferredFilenameExtension) ?? "jpg"
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                    try? data.write(to: tmp)
                    vm.redact(url: tmp, name: "Photo")
                }
                photoItem = nil
            }
        }
        #if os(iOS)
        // Camera scanner. VisionKit is iOS-only; the cover is dismissed by
        // the completion before the file is handed to the view model.
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { url in
                showScanner = false
                if let url { vm.redact(url: url, name: "Scan") }
            }
            .ignoresSafeArea()
        }
        #endif
        // Profile and review sheets. The review sheet cannot be swiped away
        // without a decision because a temp copy of the original is waiting.
        .sheet(isPresented: $vm.showProfile) { ProfileView(store: vm.profiles) }
        .sheet(item: $vm.review) { rv in
            ReviewView(state: rv, profile: vm.profiles.profile,
                       onConfirm: { d, x in vm.confirmReview(disabled: d, excluded: x) },
                       onCancel: { vm.cancelReview() })
            .interactiveDismissDisabled()
        }
        // Password prompt for encrypted PDFs. Cancel drops the pending request.
        .alert("PDF is locked", isPresented: $vm.showingPasswordPrompt) {
            SecureField("Password", text: $vm.passwordInput)
            Button("Open") { vm.submitPassword() }
            Button("Cancel", role: .cancel) { vm.pendingPasswordRequest = nil }
        } message: {
            Text("Enter the password the bank gave you. It is used once and never stored.")
        }
    }

    /// File types offered by the Files importer. The Word type is built from
    /// its identifier because `UTType` has no static constant for it; the
    /// `?? .data` fallback keeps the array non-optional if the identifier
    /// were ever unknown.
    static let importTypes: [UTType] = [.pdf, .image, .plainText, .commaSeparatedText, .rtf, .utf8PlainText,
                                        UTType("org.openxmlformats.wordprocessingml.document") ?? .data]

    /// Stage label for the overlay ("Reading", "Detecting", "Saving"); empty when idle.
    private var stageText: String { if case .working(let s) = vm.phase { return s } else { return "" } }

    // MARK: Content

    /// Scrolling body: header, then either the empty state or filters + cards.
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if vm.records.isEmpty {
                    EmptyState().padding(.top, 30)
                } else {
                    filters
                    LazyVStack(spacing: 12) {
                        // Enumerated purely to keep a stable element id; the
                        // index itself is unused.
                        ForEach(Array(vm.filtered.enumerated()), id: \.element.id) { i, r in
                            NavigationLink(value: r) { RecordCard(record: r) }
                                // Gentler press than the default so cards do not shrink much.
                                .buttonStyle(PressableStyle(scale: 0.98, dim: 0.92))
                                // New cards rise in from the bottom; removed cards just fade.
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                                .contextMenu {
                                    Button(role: .destructive) { Task { await vm.delete(r) } } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    }
                    // Animate reflow whenever the set of visible ids changes
                    // (filter switch, insert, delete).
                    .animation(Theme.snappy, value: vm.filtered.map(\.id))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            // Bottom padding clears the floating bar and toasts.
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
    }

    /// Wordmark and reversible toggle.
    private var header: some View {
        HStack {
            Text("Strid").font(Theme.display(34)).tracking(-0.7).foregroundStyle(Theme.ink)
            Spacer()
            reversibleToggle
            profileButton
        }
    }

    /// Round button opening the "Your data" sheet. The symbol fills once the
    /// profile holds any terms, as a hint that rules are in force.
    private var profileButton: some View {
        Button {
            Haptic.tap()
            vm.showProfile = true
        } label: {
            Image(systemName: vm.profiles.profile.alwaysRedact.isEmpty ? "person.crop.circle" : "person.crop.circle.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(Theme.card, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Your data")
    }

    /// Glass pill that flips `vm.reversible`. Filled key = reversible (a
    /// vault will be written), outline key = permanent. The symbol swap is
    /// animated with a replace effect.
    private var reversibleToggle: some View {
        Button {
            Haptic.tap()
            withAnimation(Theme.snappy) { vm.reversible.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: vm.reversible ? "key.fill" : "key")
                    .font(.system(size: 11, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(vm.reversible ? "Reversible" : "Permanent").font(Theme.label())
            }
        }
        .buttonStyle(GlassPillStyle(active: vm.reversible))
    }

    /// Horizontal row of kind-filter pills. Scrolls in case of narrow widths.
    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(HomeViewModel.Filter.allCases) { f in
                    Button {
                        Haptic.tap()
                        withAnimation(Theme.snappy) { vm.filter = f }
                    } label: { Text(f.rawValue) }
                    .buttonStyle(GlassPillStyle(active: vm.filter == f))
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Floating bar

    /// Bottom-pinned controls: a white "Redact" menu with the intake options,
    /// and a round Photos picker button beside it.
    private var floatingBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button { showFiles = true } label: { Label("Files", systemImage: "folder") }
                #if os(iOS)
                Button { showScanner = true } label: { Label("Scan with camera", systemImage: "doc.viewfinder") }
                #endif
                Button {
                    // Whitespace-only clipboard counts as empty.
                    if let s = PasteboardHelper.getString(), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        vm.redact(text: s)
                    } else {
                        vm.toasts.show("Clipboard is empty")
                    }
                } label: { Label("Paste text", systemImage: "doc.on.clipboard") }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                    Text("Redact").font(Theme.label(15))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 22).padding(.vertical, 14)
                .background(Color.white, in: Capsule())
            }
            // `.button` menu style lets the custom label act as the trigger.
            .menuStyle(.button)
            .buttonStyle(PressableStyle())

            PhotosPicker(selection: $photoItem, matching: .images) {
                Image(systemName: "photo")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 48, height: 48)
                    .background(Theme.surface2, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.edge, lineWidth: 0.5))
            }
            .buttonStyle(PressableStyle())
        }
        // The one shadow: these sit over the scrolling list.
        .floating()
        .padding(.bottom, 4)
    }
}

// MARK: - Record card

/// One row in the home list: thumbnail, name (with a key glyph if
/// reversible), kind/count badges, relative time, and a strip of tinted dots
/// summarising which entity types were found.
struct RecordCard: View {
    let record: RedactionRecord
    var body: some View {
        HStack(spacing: 14) {
            Thumb(record: record)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(record.name).font(Theme.title()).tracking(-0.2).foregroundStyle(Theme.ink)
                        .lineLimit(1).truncationMode(.middle)
                    if record.reversible { Image(systemName: "key.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.ink4) }
                }
                HStack(spacing: 6) {
                    Badge(text: record.kindLabel)
                    // Zero items is good news, so it gets the green tint.
                    Badge(text: "\(record.total) items", tint: record.total == 0 ? Theme.ok : Theme.ink2)
                    Text(record.createdAt, format: .relative(presentation: .named))
                        .font(Theme.meta()).foregroundStyle(Theme.ink5).lineLimit(1)
                }
                dots
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink5)
        }
        .card(radius: 22, padding: 14)
    }

    /// Up to six muted capsules, one per entity type (most frequent first).
    /// Width scales with count: 3pt per item, clamped to 8...36pt.
    private var dots: some View {
        HStack(spacing: 4) {
            ForEach(record.sortedCounts.prefix(6), id: \.type) { c in
                Capsule().fill(Theme.ink5)
                    .frame(width: max(8, CGFloat(min(c.count, 12)) * 3), height: 4)
            }
        }
    }
}

/// Square thumbnail showing the record kind's SF Symbol on a soft tile.
struct Thumb: View {
    let record: RedactionRecord
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface3)
            Image(systemName: record.symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Theme.ink2)
        }
        .frame(width: 52, height: 52)
    }
}

// MARK: - Empty state

/// Shown instead of the list when there are no records: fanned-card art plus
/// a short explanation of what the app accepts and that nothing leaves the device.
struct EmptyState: View {
    var body: some View {
        VStack(spacing: 22) {
            StackedCards().frame(height: 190)
            VStack(spacing: 6) {
                Text("Nothing redacted yet").font(Theme.title()).tracking(-0.2).foregroundStyle(Theme.ink)
                Text("Bank statements, Aadhaar, PAN, salary slips.\nPDF in, PDF out. Nothing leaves this device.")
                    .font(Theme.body()).lineSpacing(4).foregroundStyle(Theme.ink3)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

// MARK: - Processing overlay

/// Full-screen dimmed blur with a centred card: sweeping meter, current
/// stage name, and a privacy reassurance. Shown while `HomeViewModel.isWorking`.
struct ProcessingOverlay: View {
    /// Stage label from the use case's progress callback.
    let stage: String
    /// Drives the meter; the overlay itself is always mounted and faded by its parent.
    var active = true
    var body: some View {
        ZStack {
            // Dim + blur everything behind the card, including under the safe areas.
            Rectangle().fill(.black.opacity(0.55)).ignoresSafeArea()
                .background(.ultraThinMaterial)
            VStack(spacing: 18) {
                SweepMeter(active: active)
                Text(stage)
                    .font(Theme.label()).foregroundStyle(Theme.ink)
                    // Stage names cross-fade in place; they are words, not
                    // counters, so no digit roll.
                    .contentTransition(.opacity)
                    .animation(Theme.quick, value: stage)
                Text("On device. Nothing is uploaded.").font(Theme.meta()).foregroundStyle(Theme.ink4)
            }
            .padding(.horizontal, 32).padding(.vertical, 28)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            // On a dimmed, blurred backdrop the hairline edge is enough lift.
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).strokeBorder(Theme.edge, lineWidth: 0.5))
        }
    }
}


extension View {
    /// Hides the system bar on iOS; macOS keeps its window chrome.
    ///
    /// Both Bencho screens draw their own headers, so the iOS navigation bar
    /// would only add an empty strip. `@ViewBuilder` because the two branches
    /// return different opaque types.
    @ViewBuilder
    func hideNavigationBar() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}
