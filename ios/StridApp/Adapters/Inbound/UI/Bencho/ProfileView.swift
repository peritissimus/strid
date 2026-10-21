//
//  ProfileView.swift
//  StridApp
//
//  "Your data": the standing rules every job starts from. Whether to review
//  before redacting, how much to redact (a preset or per-category switches),
//  the literals that must always go, and the names that must stay readable.
//
//  Binds straight to `ProfileStore.profile`, which persists on every change.
//

import SwiftUI
import StridKit

struct ProfileView: View {
    @Bindable var store: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var newTerm = ""
    @State private var newTermType: PIIEntityType = .person
    @State private var newKeep = ""

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    reviewCard
                    sensitivity
                    categories
                    alwaysRedact
                    keepVisible
                    Text("Everything here stays on this device.")
                        .font(Theme.meta()).foregroundStyle(Theme.ink5)
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
    }

    private var profile: Binding<RedactionProfile> { $store.profile }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your data").font(Theme.title()).tracking(-0.2).foregroundStyle(Theme.ink)
                Text("What Strid treats as private").font(Theme.meta()).foregroundStyle(Theme.ink4)
            }
            Spacer()
            Button { Haptic.tap(); dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink).frame(width: 36, height: 36)
                    .background(Theme.card, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Close")
        }
    }

    private var reviewCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Review before redacting").font(Theme.label(15)).foregroundStyle(Theme.ink)
                Text("See what was found and untick anything you want to keep.")
                    .font(Theme.meta()).foregroundStyle(Theme.ink4)
            }
            Spacer()
            GlassSwitch(isOn: profile.reviewBeforeRedacting)
        }
        .card(radius: Theme.radiusInner, padding: 16)
    }

    private var sensitivity: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "How much to redact")
            ForEach(RedactionProfile.Sensitivity.allCases) { s in
                let on = store.profile.sensitivity == s
                Button {
                    Haptic.tap()
                    withAnimation(Theme.snappy) { store.profile.sensitivity = s }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.title).font(Theme.label(15)).foregroundStyle(Theme.ink)
                            Text(s.blurb).font(Theme.meta()).foregroundStyle(Theme.ink4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(on ? Theme.ok : Theme.ink5)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .card(radius: Theme.radiusInner, fill: on ? Theme.cardHi : Theme.card, padding: 16)
            }
        }
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Categories")
            ForEach(PIICategory.allCases) { cat in
                VStack(alignment: .leading, spacing: 0) {
                    Text(cat.title).font(Theme.label()).foregroundStyle(Theme.ink3).padding(.bottom, 6)
                    ForEach(cat.types, id: \.self) { t in
                        HStack {
                            Text(t.displayName).font(Theme.body())
                                .foregroundStyle(store.profile.isEnabled(t) ? Theme.ink : Theme.ink4)
                            Spacer()
                            GlassSwitch(isOn: Binding(
                                get: { store.profile.isEnabled(t) },
                                set: { v in withAnimation(Theme.snappy) { store.profile.setEnabled(t, v) } }))
                        }
                        .padding(.vertical, 7)
                    }
                }
                .card(radius: Theme.radiusInner, padding: 16)
            }
        }
    }

    private var alwaysRedact: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Always redact")
            Text("Your own names, numbers and IDs. Blacked out every time they appear, even where the detector would miss them.")
                .font(Theme.meta()).lineSpacing(3).foregroundStyle(Theme.ink4)
            VStack(spacing: 0) {
                ForEach(store.profile.alwaysRedact) { term in
                    HStack(spacing: 10) {
                        Text(term.value).font(Theme.mono()).foregroundStyle(Theme.ink2)
                            .lineLimit(1).truncationMode(.middle)
                        Text(term.type.displayName).font(Theme.label(12)).foregroundStyle(Theme.ink4)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.inlay, in: Capsule())
                        Spacer()
                        removeButton { store.profile.alwaysRedact.removeAll { $0.id == term.id } }
                    }
                    .padding(.vertical, 7)
                }
                HStack(spacing: 8) {
                    TextField("Name, number or ID", text: $newTerm)
                        .font(Theme.body()).foregroundStyle(Theme.ink)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .onSubmit(addTerm)
                    Menu {
                        ForEach(PIICategory.allCases) { cat in
                            Section(cat.title) {
                                ForEach(cat.types, id: \.self) { t in
                                    Button(t.displayName) { newTermType = t }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(newTermType.displayName)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .buttonStyle(GlassPillStyle())
                    addButton(enabled: !newTerm.trimmingCharacters(in: .whitespaces).isEmpty, addTerm)
                }
                .padding(.top, store.profile.alwaysRedact.isEmpty ? 0 : 8)
            }
            .card(radius: Theme.radiusInner, padding: 16)
        }
    }

    private var keepVisible: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Keep visible")
            Text("Names that should stay readable, like your employer, a vendor or your own bank.")
                .font(Theme.meta()).lineSpacing(3).foregroundStyle(Theme.ink4)
            VStack(spacing: 0) {
                ForEach(store.profile.keepVisible, id: \.self) { k in
                    HStack(spacing: 10) {
                        Text(k).font(Theme.body()).foregroundStyle(Theme.ink2).lineLimit(1)
                        Spacer()
                        removeButton { store.profile.keepVisible.removeAll { $0 == k } }
                    }
                    .padding(.vertical, 7)
                }
                HStack(spacing: 8) {
                    TextField("Vendor or organisation", text: $newKeep)
                        .font(Theme.body()).foregroundStyle(Theme.ink)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .onSubmit(addKeep)
                    addButton(enabled: !newKeep.trimmingCharacters(in: .whitespaces).isEmpty, addKeep)
                }
                .padding(.top, store.profile.keepVisible.isEmpty ? 0 : 8)
            }
            .card(radius: Theme.radiusInner, padding: 16)
        }
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            withAnimation(Theme.snappy, action)
        } label: {
            Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ink4)
                .frame(width: 28, height: 28).background(Theme.inlay, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Remove")
    }

    private func addButton(enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? .black : Theme.ink5)
                .frame(width: 32, height: 32)
                .background(enabled ? Color.white : Theme.inlay, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .accessibilityLabel("Add")
    }

    private func addTerm() {
        let v = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        Haptic.success()
        withAnimation(Theme.snappy) { store.profile.alwaysRedact.append(.init(value: v, type: newTermType)) }
        newTerm = ""
    }

    private func addKeep() {
        let v = newKeep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty, !store.profile.keepVisible.contains(v) else { return }
        Haptic.success()
        withAnimation(Theme.snappy) { store.profile.keepVisible.append(v) }
        newKeep = ""
    }
}

/// Bencho-style switch: a 42×26 capsule with a sliding knob, filled green
/// when on. Used instead of `Toggle` so it matches the glass surfaces.
struct GlassSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        Button {
            Haptic.tap()
            withAnimation(Theme.snappy) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Theme.ok : Theme.inlay)
                    .overlay(Capsule().strokeBorder(Theme.edge, lineWidth: 0.5))
                Circle().fill(isOn ? Color.black : Theme.ink3)
                    .frame(width: 20, height: 20)
                    .padding(3)
            }
            .frame(width: 42, height: 26)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
    }
}
