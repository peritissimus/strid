//
//  MacRootView.swift
//  StridApp
//
//  The Mac window: a sidebar of completed redactions beside the record
//  detail, with intake in the toolbar. Same view model, same intake flows
//  and the same detail screen as the phone; only the frame around them is
//  different. Files can also be dropped anywhere on the window.
//

#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct MacRootView: View {
    @State var vm: HomeViewModel

    @State private var showFiles = false
    /// Unused on macOS (no camera scanner) but required by the shared flows.
    @State private var showScanner = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingDelete: RedactionRecord?
    @State private var dropping = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 250, ideal: 270, max: 340)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1000, minHeight: 620)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .tint(Theme.ink)
        .toolbarBackground(Theme.bg, for: .windowToolbar)
        .toolbar { toolbarItems }
        .task { await vm.load() }
        .intakeFlows(vm: vm, showFiles: $showFiles, showScanner: $showScanner, photoItem: $photoItem)
        .onReceive(NotificationCenter.default.publisher(for: .stridOpenFile)) { _ in showFiles = true }
        // Drop a file anywhere on the window.
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in vm.redact(url: url) }
            }
            return true
        }
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .strokeBorder(Theme.ink, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(12)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(Theme.quick, value: dropping)
        .overlay(alignment: .bottom) { ToastStack(center: vm.toasts).padding(.bottom, 24) }
        .overlay {
            ProcessingOverlay(stage: stageText, active: vm.isWorking)
                .opacity(vm.isWorking ? 1 : 0)
                .allowsHitTesting(vm.isWorking)
                .animation(Theme.quick, value: vm.isWorking)
        }
        .confirmationDialog("Delete this redaction?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete original and redacted copy", role: .destructive) {
                if let r = pendingDelete { Task { await vm.delete(r) } }
                pendingDelete = nil
            }
        }
    }

    private var stageText: String { if case .working(let s) = vm.phase { return s } else { return "" } }

    /// Sidebar selection, mirrored onto `vm.selected` so a finished job
    /// selects its record and a delete clears the pane.
    private var selection: Binding<UUID?> {
        Binding(get: { vm.selected?.id },
                set: { id in vm.selected = vm.records.first { $0.id == id } })
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar(title: "Strid", display: true) { ProfileButton(vm: vm) }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 10)
            filters
                .padding(.horizontal, 16).padding(.bottom, 10)
            Rectangle().fill(Theme.edge).frame(height: 0.5)
            if vm.records.isEmpty {
                VStack(spacing: 8) {
                    Text("No redactions yet").font(Theme.label()).foregroundStyle(Theme.ink3)
                    Text("Drop a file on the window or press ⌘O.").font(Theme.meta()).foregroundStyle(Theme.ink4)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.top, 40)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(vm.filtered) { r in
                            Button {
                                withAnimation(Theme.quick) { vm.selected = r }
                            } label: {
                                SidebarRow(record: r, selected: vm.selected?.id == r.id)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { NSWorkspace.shared.activateFileViewerSelecting([r.outputURL]) } label: { Label("Show in Finder", systemImage: "folder") }
                                Button { NSWorkspace.shared.open(r.outputURL) } label: { Label("Open redacted file", systemImage: "doc") }
                                Divider()
                                Button(role: .destructive) { pendingDelete = r } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                    .padding(10)
                    .animation(Theme.snappy, value: vm.filtered.map(\.id))
                }
                .scrollIndicators(.hidden)
                .focusable()
                .focusEffectDisabled()
                .onDeleteCommand { pendingDelete = vm.selected }
            }
            Rectangle().fill(Theme.edge).frame(height: 0.5)
            // Mode lives with the list, not in the title bar: it is a setting
            // for the next job, and the sidebar is where jobs start.
            HStack {
                ReversibleToggle(vm: vm)
                Spacer()
                Text(vm.reversible ? "A vault is kept for undo" : "No vault, no undo")
                    .font(Theme.meta()).foregroundStyle(Theme.ink4)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(Theme.surface)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.edge).frame(width: 0.5) }
    }

    private var filters: some View {
        HStack(spacing: 6) {
            ForEach(HomeViewModel.Filter.allCases) { f in
                Button {
                    withAnimation(Theme.snappy) { vm.filter = f }
                } label: { Text(f.rawValue) }
                .buttonStyle(GlassPillStyle(active: vm.filter == f))
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let r = vm.selected {
                RecordDetailView(record: r, vm: vm, embedded: true)
                    .id(r.id)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.badge.ellipsis").font(.system(size: 34, weight: .light)).foregroundStyle(Theme.ink4)
                    Text(vm.records.isEmpty ? "Drop a file here to redact it" : "Select a redaction")
                        .font(Theme.title()).tracking(-0.2).foregroundStyle(Theme.ink2)
                    Text("PDF, images, text and Word files. Everything stays on this Mac.")
                        .font(Theme.meta()).foregroundStyle(Theme.ink4)
                }
            }
        }
        .navigationTitle("")
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                IntakeMenuItems(vm: vm, showFiles: $showFiles, showScanner: $showScanner)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                    Text("Redact").font(Theme.label())
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Color.white, in: Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(PressableStyle())
            .menuIndicator(.hidden)
            .help("Redact a file (⌘O)")
        }
    }
}

/// Compact sidebar row: kind tile, name, kind and count, relative time.
private struct SidebarRow: View {
    let record: RedactionRecord
    let selected: Bool
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Theme.cardHi : Theme.surface3)
                Image(systemName: record.symbol).font(.system(size: 15)).foregroundStyle(selected ? Theme.ink : Theme.ink3)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.name).font(Theme.label(14)).foregroundStyle(selected ? Theme.ink : Theme.ink2)
                        .lineLimit(1).truncationMode(.middle)
                    if record.reversible { Image(systemName: "key.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.ink4) }
                }
                HStack(spacing: 6) {
                    Text("\(record.kindLabel) · \(record.total) item\(record.total == 1 ? "" : "s")")
                        .font(Theme.meta()).foregroundStyle(record.total == 0 ? Theme.ok : Theme.ink4)
                    Text(record.createdAt, format: .relative(presentation: .named))
                        .font(Theme.meta()).foregroundStyle(Theme.ink5).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(selected ? Theme.cardHi : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Color.white.opacity(0.14) : .clear, lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
#endif
