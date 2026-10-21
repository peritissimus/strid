//
//  Components.swift
//  StridApp
//
//  Small reusable building blocks for the Bencho UI, shared by `HomeView` and
//  `RecordDetailView`:
//  - `SegmentedPill`: two-option switch with a sliding white thumb.
//  - `EntityChip` + `FlowLayout`: wrapping row of per-type count chips.
//  - `BarMeter` / `SweepMeter`: determinate and indeterminate bar meters.
//  - `ToastCenter` + `ToastStack`: transient bottom toasts.
//  - `StackedCards`: fanned-card illustration for the empty state.
//  - `SectionLabel`, `Badge`: tiny typographic helpers.
//

import SwiftUI
import StridKit

// MARK: - Segmented pill (Day | Week style, sliding thumb)

/// Generic segmented control. Used in `RecordDetailView` to flip between the
/// redacted and original previews.
///
/// The selected segment's white capsule shares a `matchedGeometryEffect`
/// id, so when `selection` changes SwiftUI animates the thumb sliding from
/// the old segment to the new one instead of fading two separate shapes.
struct SegmentedPill<T: Hashable>: View {
    /// `(value, label)` pairs in display order.
    let options: [(T, String)]
    /// Currently selected value.
    @Binding var selection: T
    /// Namespace for the sliding-thumb geometry match.
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                Button {
                    Haptic.tap()
                    withAnimation(Theme.snappy) { selection = value }
                } label: {
                    Text(label)
                        .font(Theme.label(13))
                        .lineLimit(1).fixedSize()
                        // Black on the white thumb, muted ink elsewhere.
                        .foregroundStyle(selection == value ? .black : Theme.ink3)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background {
                            // Only the selected segment draws the thumb; the
                            // shared id makes it slide between segments.
                            if selection == value {
                                Capsule().fill(Color.white).matchedGeometryEffect(id: "thumb", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        // 3pt gutter so the thumb sits inside the outer glass capsule.
        .padding(3)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.edge, lineWidth: 0.5))
    }
}

// MARK: - Entity chip with animated count

/// Pill showing one entity type's colour dot, display name and count.
/// Laid out in a `FlowLayout` on the record detail summary card.
struct EntityChip: View {
    let type: PIIEntityType
    let count: Int
    var body: some View {
        HStack(spacing: 7) {
            Text(type.displayName).font(Theme.label(13)).foregroundStyle(Theme.ink2)
            Text("\(count)")
                .font(Theme.mono(12)).foregroundStyle(Theme.ink)
                // Digits roll rather than cross-fade if the count changes.
                .contentTransition(.numericText())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.inlay, in: Capsule())
        }
        // Asymmetric padding: the count bubble provides its own trailing space.
        .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 6)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.edge, lineWidth: 0.5))
    }
}

/// Wrapping layout for chips.
///
/// Minimal left-to-right flow: place each subview at its ideal size, start a
/// new row when the next one would overflow the available width. Both
/// passes walk the subviews identically so the measured height matches the
/// placed height.
struct FlowLayout: Layout {
    /// Gap between chips, horizontally and between rows.
    var spacing: CGFloat = 8

    /// Simulates the flow at the proposed width and returns the total height.
    /// Falls back to 320pt when no width is proposed (e.g. inside a
    /// horizontal ScrollView).
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            // Wrap only if this is not the first item on the row; an
            // oversized first item is allowed to overflow rather than loop.
            if x + sz.width > w, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        return CGSize(width: w, height: y + rowH)
    }

    /// Same walk as `sizeThatFits`, but offset by `bounds.origin` and
    /// actually placing each subview at its top-left corner.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - Bar meter (||||||||| 50)

/// Determinate meter drawn as a row of thin bars; bars below `progress`
/// light up and grow taller. Not currently used by a screen but kept as the
/// determinate sibling of `SweepMeter`.
struct BarMeter: View {
    /// 0...1
    var progress: Double
    /// Number of bars across the meter.
    var bars = 32
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<bars, id: \.self) { i in
                let on = Double(i) / Double(bars) < progress
                RoundedRectangle(cornerRadius: 1)
                    .fill(on ? Theme.ink : Theme.ink5.opacity(0.5))
                    .frame(width: 3, height: on ? 18 : 12)
                    // Staggered delay makes the bars light up as a ripple
                    // rather than all at once.
                    .animation(Theme.snappy.delay(Double(i) * 0.008), value: on)
            }
        }
    }
}

/// Indeterminate variant: a bright window sweeping across the bars.
///
/// Shown inside `ProcessingOverlay` while a redaction job runs. A single
/// animated scalar `t` sweeps 0 -> 1 -> 0 forever; each bar's brightness and
/// height fall off linearly with its distance from `t`, producing a soft
/// highlight about one sixth of the width wide.
struct SweepMeter: View {
    /// Position of the highlight, 0...1 across the bars. Animated on appear.
    @State private var t: Double = 0
    var bars = 32
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<bars, id: \.self) { i in
                // Distance of this bar from the highlight centre, 0...1.
                let d = abs(Double(i) / Double(bars) - t)
                // 1 at the centre, 0 once d >= 1/6.
                let lit = max(0, 1 - d * 6)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.ink.opacity(0.25 + 0.75 * lit))
                    .frame(width: 3, height: 12 + 8 * lit)
            }
        }
        .onAppear {
            // Autoreverse gives a ping-pong sweep with no jump at the ends.
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: true)) { t = 1 }
        }
    }
}

// MARK: - Toasts

/// Queue of transient messages. Owned by `HomeViewModel` and rendered by a
/// `ToastStack` on both the home and detail screens.
///
/// `@MainActor` because it mutates UI state and schedules its own dismissal
/// on the main actor.
@Observable @MainActor
final class ToastCenter {
    /// One message. `Identifiable` for `ForEach`; `Equatable` for animations.
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        /// Primary line.
        var title: String
        /// Optional secondary line.
        var subtitle: String?
        /// Controls the icon and its colour.
        var kind: Kind = .info
        enum Kind { case info, success, error }
    }

    /// Live toasts, oldest first. `ToastStack` shows at most the last three.
    var toasts: [Toast] = []

    /// Appends a toast with a bouncy entrance and removes it after `seconds`
    /// with a snappy exit. Each toast schedules its own removal task, so
    /// overlapping toasts expire independently.
    func show(_ title: String, _ subtitle: String? = nil, kind: Toast.Kind = .info, seconds: Double = 2.6) {
        let t = Toast(title: title, subtitle: subtitle, kind: kind)
        withAnimation(Theme.bouncy) { toasts.append(t) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            withAnimation(Theme.snappy) { toasts.removeAll { $0.id == t.id } }
        }
    }
}

/// Renders the most recent toasts from a `ToastCenter` as a bottom-anchored
/// stack. Placed in a `ZStack(alignment: .bottom)` by the screens, padded up
/// to clear the floating action bar.
struct ToastStack: View {
    let center: ToastCenter
    var body: some View {
        VStack(spacing: 8) {
            // Only the last three; enumerated so newer toasts get a higher
            // zIndex and overlap correctly during transitions.
            ForEach(Array(center.toasts.suffix(3).enumerated()), id: \.element.id) { i, t in
                HStack(spacing: 10) {
                    Image(systemName: icon(t.kind))
                        .foregroundStyle(color(t.kind))
                        .font(.system(size: 14, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).font(Theme.label(13)).foregroundStyle(Theme.ink)
                        if let s = t.subtitle { Text(s).font(Theme.body(12)).foregroundStyle(Theme.ink3) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.edge, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                // Slide up from the bottom, fade, and grow slightly on entry.
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
                .zIndex(Double(i))
            }
        }
        // Cap the width so toasts do not stretch edge to edge on iPad/macOS.
        .frame(maxWidth: 360)
        .padding(.horizontal, 16)
    }

    /// SF Symbol for each toast kind.
    private func icon(_ k: ToastCenter.Toast.Kind) -> String {
        switch k { case .info: "info.circle.fill"; case .success: "checkmark.circle.fill"; case .error: "xmark.circle.fill" }
    }

    /// Icon colour for each toast kind, drawn from the signal tokens.
    private func color(_ k: ToastCenter.Toast.Kind) -> Color {
        switch k { case .info: Theme.pick; case .success: Theme.ok; case .error: Theme.ember }
    }
}

// MARK: - Stacked cards illustration (empty state)

/// Decorative fan of four tinted cards shown by `EmptyState` on the home
/// screen before any redaction exists.
///
/// All cards start perfectly stacked; on appear they animate into a fan,
/// each rotated and offset a little more than the last. Tapping the fan
/// sends the front card to the back: it sweeps out to the right and down
/// while the others slide forward, then arcs round and tucks in behind.
/// The gradient and the small dark bar in the corner suggest a document
/// without drawing one.
struct StackedCards: View {
    /// One card: a stable identity plus its tint.
    private struct Card: Identifiable {
        let id: Int
        let tint: Color
    }

    /// Drives the stacked -> fanned transition.
    @State private var fanned = false
    /// Cards front to back. Rotated at the start of each flight so every
    /// card springs to its new slot in one motion.
    @State private var cards: [Card] = [Theme.pick, Theme.ok, Theme.guide, Color(hex: 0xF5A524)]
        .enumerated().map { Card(id: $0.offset, tint: $0.element) }
    /// The card in flight; nil when the stack is at rest.
    @State private var flying: Int?
    /// Whether the flying card is pulled out to the side. Its own spring
    /// overlaps the slot spring, and the sum of the two traces the arc.
    @State private var swung = false
    /// Flips once the flying card is out at the edge, so it is drawn under
    /// the stack as it comes back in.
    @State private var behind = false

    var body: some View {
        ZStack {
            ForEach(cards) { card in
                let slot = cards.firstIndex { $0.id == card.id } ?? 0
                let inFlight = flying == card.id
                let out = inFlight && swung
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [card.tint.opacity(0.9), card.tint.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                    .frame(width: 120, height: 150)
                    // A redaction-bar motif in the bottom-left corner.
                    .overlay(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.55)).frame(width: 58, height: 10).padding(12)
                    }
                    .scaleEffect(out ? 1.05 : 1)
                    // Fan: 7 degrees per card centred around -10; the swung
                    // card tilts further out.
                    .rotationEffect(.degrees((fanned ? Double(slot) * 7 - 10 : 0) + (out ? 10 : 0)))
                    // Slot spread: 22pt sideways, 4pt lift per card. The
                    // swing adds a push right and down on top of that.
                    .offset(x: (fanned ? CGFloat(slot) * 22 - 30 : 0) + (out ? 78 : 0),
                            y: (fanned ? CGFloat(slot) * -4 : 0) + (out ? 30 : 0))
                    .shadow(color: .black.opacity(inFlight ? 0.6 : 0.45), radius: inFlight ? 22 : 16, y: inFlight ? 16 : 10)
                    .zIndex(inFlight && !behind ? 10 : Double(cards.count - slot))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: cycle)
        // Short delay so the fan happens after the screen has settled in.
        .onAppear { withAnimation(Theme.settle.delay(0.15)) { fanned = true } }
    }

    /// Send the front card to the back. Two springs overlap: the slot
    /// spring carries every card to its new place over ~0.6s, and a quicker
    /// swing spring pushes the flying card out right, then releases it a
    /// beat later. Their sum is one continuous arc. Z-order flips at the
    /// apex, when the card is clear of the stack.
    private func cycle() {
        guard flying == nil, let front = cards.first else { return }
        Haptic.tap()
        behind = false
        flying = front.id
        withAnimation(.spring(response: 0.65, dampingFraction: 0.86)) {
            cards.append(cards.removeFirst())
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { swung = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            behind = true
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { swung = false }
            try? await Task.sleep(for: .seconds(0.6))
            flying = nil
        }
    }
}

// MARK: - Misc

/// Uppercase, tracked, monospaced caption used as a card section heading
/// ("VAULT KEY", "NOTES").
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(11)).tracking(0.8)
            .foregroundStyle(Theme.ink4)
    }
}

/// Tiny monospaced capsule tag: kind label, item count, REDACTED/ORIGINAL.
struct Badge: View {
    let text: String
    /// Text colour; the inlay background stays constant.
    var tint: Color = Theme.ink3
    var body: some View {
        Text(text)
            .font(Theme.mono(11))
            .foregroundStyle(tint)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.inlay, in: Capsule())
    }
}
