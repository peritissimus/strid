//
//  ReviewView.swift
//  StridApp
//
//  The pause between detection and redaction. Shows what was found, grouped
//  by category and type, and lets the user switch whole types off, untick
//  single values, or pick a sensitivity preset. Values that come from the
//  profile's always-redact terms are locked on.
//
//  Presented as a sheet from `HomeView` while `HomeViewModel.review` is set.
//  Nothing here touches the engine: the choices are folded into the policy
//  by `HomeViewModel.confirmReview`.
//

import SwiftUI
import StridKit

struct ReviewView: View {
    let state: HomeViewModel.ReviewState
    let profile: RedactionProfile
    let onConfirm: (Set<PIIEntityType>, Set<String>) -> Void
    let onCancel: () -> Void

    /// Types switched off. Seeded from the profile's sensitivity so the sheet
    /// opens showing what would happen with no changes.
    @State private var disabled: Set<PIIEntityType> = []
    /// Normalised values unticked individually.
    @State private var excluded: Set<String> = []
    /// Types whose value list is open.
    @State private var expanded: Set<PIIEntityType> = []

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    presets
                    if state.findings.isEmpty {
                        Text("Nothing personal found. The file will be copied through unchanged.")
                            .font(Theme.body()).lineSpacing(4).foregroundStyle(Theme.ink3)
                            .card()
                    } else {
                        ForEach(PIICategory.allCases) { cat in
                            let types = cat.types.filter { byType[$0] != nil }
                            if !types.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    SectionLabel(text: cat.title)
                                    ForEach(types, id: \.self) { typeCard($0) }
                                }
                            }
                        }
                    }
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
            }
            .scrollIndicators(.hidden)
            BottomScrim()
            actions
        }
        .preferredColorScheme(.dark)
        .onAppear {
            disabled = Set(byType.keys).filter { !profile.isEnabled($0) }
        }
    }

    // MARK: Derived

    /// Findings per type, in first-seen order.
    private var byType: [PIIEntityType: [Finding]] {
        Dictionary(grouping: state.findings, by: \.type)
    }

    /// Occurrences that will actually be redacted.
    private var redactedCount: Int {
        state.findings.reduce(0) { n, f in
            n + (f.locked || (!disabled.contains(f.type) && !excluded.contains(f.normalised)) ? f.count : 0)
        }
    }

    private var totalCount: Int { state.findings.reduce(0) { $0 + $1.count } }

    /// Which preset the current switches amount to, if any.
    private var preset: RedactionProfile.Sensitivity? {
        let present = Set(byType.keys)
        if disabled.isEmpty { return .everything }
        if disabled == present.subtracting(RedactionProfile.personalTypes) { return .personal }
        return nil
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review").font(Theme.title()).tracking(-0.2).foregroundStyle(Theme.ink)
                Text("\(state.request.displayName) · \(totalCount) found").font(Theme.meta()).foregroundStyle(Theme.ink4)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button { Haptic.tap(); onCancel() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink).frame(width: 36, height: 36)
                    .background(Theme.card, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Cancel")
        }
    }

    /// Everything / Personal only / Custom. Custom is a label, not a button:
    /// it lights up as soon as the switches stop matching a preset.
    private var presets: some View {
        HStack(spacing: 8) {
            presetPill(.everything) { disabled = [] }
            presetPill(.personal) { disabled = Set(byType.keys).subtracting(RedactionProfile.personalTypes) }
            Text("Custom").font(Theme.label()).foregroundStyle(preset == nil ? Theme.ink : Theme.ink4)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(preset == nil ? Theme.cardHi : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.edge, lineWidth: 0.5))
        }
    }

    private func presetPill(_ s: RedactionProfile.Sensitivity, _ apply: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            withAnimation(Theme.snappy) { apply() }
        } label: { Text(s.title) }
        .buttonStyle(GlassPillStyle(active: preset == s))
    }

    /// One type: name, occurrence count, switch; tap the name to list values.
    private func typeCard(_ type: PIIEntityType) -> some View {
        let items = byType[type] ?? []
        let count = items.reduce(0) { $0 + $1.count }
        let locked = items.allSatisfy(\.locked)
        let on = locked || !disabled.contains(type)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    Haptic.tap()
                    withAnimation(Theme.snappy) {
                        if expanded.contains(type) { expanded.remove(type) } else { expanded.insert(type) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(type.displayName).font(Theme.label(15)).foregroundStyle(on ? Theme.ink : Theme.ink4)
                        Text("\(count)").font(Theme.meta()).foregroundStyle(Theme.ink4)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.ink5)
                            .rotationEffect(.degrees(expanded.contains(type) ? 180 : 0))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if locked {
                    Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(Theme.ink4)
                        .frame(width: 44, height: 26)
                } else {
                    GlassSwitch(isOn: Binding(
                        get: { on },
                        set: { v in withAnimation(Theme.snappy) { if v { disabled.remove(type) } else { disabled.insert(type) } } }))
                }
            }
            if expanded.contains(type) {
                VStack(spacing: 0) {
                    ForEach(items) { valueRow($0, typeOn: on) }
                }
                .padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .card(radius: Theme.radiusInner, padding: 14)
    }

    /// One value: text, count, and a tick unless locked or the type is off.
    private func valueRow(_ f: Finding, typeOn: Bool) -> some View {
        let on = f.locked || (typeOn && !excluded.contains(f.normalised))
        return Button {
            guard !f.locked, typeOn else { return }
            Haptic.tap()
            withAnimation(Theme.quick) {
                if excluded.contains(f.normalised) { excluded.remove(f.normalised) } else { excluded.insert(f.normalised) }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: f.locked ? "lock.fill" : (on ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(on ? Theme.ok : Theme.ink5)
                    .frame(width: 20)
                Text(f.text).font(Theme.mono()).foregroundStyle(on ? Theme.ink2 : Theme.ink5)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                if f.count > 1 { Text("×\(f.count)").font(Theme.meta()).foregroundStyle(Theme.ink4) }
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var actions: some View {
        Button {
            Haptic.tap()
            onConfirm(disabled, excluded)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                Text(redactedCount == 0 ? "Keep everything" : "Redact \(redactedCount) item\(redactedCount == 1 ? "" : "s")")
                    .contentTransition(.numericText())
            }
        }
        .buttonStyle(PrimaryPillStyle())
        .floating()
        .padding(.bottom, 18)
        .animation(Theme.snappy, value: redactedCount)
    }
}
