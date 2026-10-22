//
//  Components.swift
//  StridApp
//
//  Small reusable building blocks for the Bencho UI, shared by `HomeView` and
//  `RecordDetailView`:
//  - `SegmentedPill`: two-option switch with a sliding white thumb.
//  - `EntityChip` + `FlowLayout`: wrapping row of per-type count chips.
//  - `SweepMeter`: indeterminate bar meter for the processing overlay.
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
/// One white thumb lives behind the row; each segment publishes its frame
/// under its value through `matchedGeometryEffect`, and the thumb follows
/// whichever frame `selection` names. The selection is the only state and
/// the thumb's place is a fixed function of it, so a change is one slide
/// on `Theme.snappy` rather than one capsule leaving and another arriving.
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
                        .font(Theme.label())
                        .lineLimit(1).fixedSize()
                        // Black on the white thumb, muted ink elsewhere.
                        .foregroundStyle(selection == value ? .black : Theme.ink3)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        // Source frame for the thumb, keyed by this segment's value.
                        .matchedGeometryEffect(id: value, in: ns)
                }
                .buttonStyle(.plain)
            }
        }
        // The thumb: one capsule that takes the selected segment's frame.
        .background {
            Capsule().fill(Color.white)
                .matchedGeometryEffect(id: selection, in: ns, isSource: false)
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
            Text(type.displayName).font(Theme.label()).foregroundStyle(Theme.ink2)
            Text("\(count)")
                .font(Theme.label()).foregroundStyle(Theme.ink)
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

// MARK: - Bottom scrim

/// Fades the scroll content out beneath a floating bar so cards never read
/// through the gaps between its buttons. Pure paint: no hit testing.
struct BottomScrim: View {
    var height: CGFloat = 170
    var body: some View {
        // Fully opaque from just above the bar down, and painted through the
        // bottom safe area: the scroll content runs under the home indicator,
        // so a scrim that stops at the safe-area edge leaves chips readable
        // beneath the buttons.
        LinearGradient(stops: [
            .init(color: Theme.bg.opacity(0), location: 0),
            .init(color: Theme.bg.opacity(0.92), location: 0.45),
            .init(color: Theme.bg, location: 0.65),
            .init(color: Theme.bg, location: 1),
        ], startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
    }
}

// MARK: - Sweep meter

/// A bright window sweeping across a row of thin bars.
///
/// Shown inside `ProcessingOverlay` while a redaction job runs. A single
/// animated scalar `t` sweeps 0 -> 1 -> 0 forever; each bar's brightness and
/// height fall off linearly with its distance from `t`, producing a soft
/// highlight about one sixth of the width wide.
struct SweepMeter: View {
    /// Position of the highlight, 0...1 across the bars. Sweeps while `active`.
    @State private var t: Double = 0
    var bars = 32
    /// False parks the highlight so a hidden meter costs nothing.
    var active = true
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
        .onAppear { if active { sweep() } }
        .onChange(of: active) { _, on in
            if on { sweep() } else { withAnimation(nil) { t = 0 } }
        }
    }

    /// Autoreverse gives a ping-pong sweep with no jump at the ends.
    private func sweep() {
        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: true)) { t = 1 }
    }
}

// MARK: - Toasts

/// Queue of transient messages. Owned by `HomeViewModel` and rendered by a
/// `ToastStack` on both the home and detail screens.
///
/// `@MainActor` because it mutates UI state and expires its own toasts on
/// the main actor.
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

    /// Live toasts, newest first. `ToastStack` shows the first `shown`.
    var toasts: [Toast] = []

    /// How many a `ToastStack` keeps on screen: the front one and two
    /// slivers behind it.
    static let shown = 3

    /// Puts a toast at the front and lets it expire after `seconds`. The
    /// arrival and every other toast's step back ride the one spring; the
    /// expiry is a timer on state, not a step in a choreography, so each
    /// toast's lifetime is independent of the others.
    func show(_ title: String, _ subtitle: String? = nil, kind: Toast.Kind = .info, seconds: Double = 2.6) {
        let t = Toast(title: title, subtitle: subtitle, kind: kind)
        withAnimation(Theme.snappy) { toasts.insert(t, at: 0) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            dismiss(t.id)
        }
    }

    /// Removes one toast. The spring carries the rest forward; the leaving
    /// toast's own exit is set by its transition in `ToastStack`.
    func dismiss(_ id: Toast.ID) {
        withAnimation(Theme.snappy) { toasts.removeAll { $0.id == id } }
    }
}

/// Renders a `ToastCenter` as a bottom-anchored stack after Bencho's
/// "Toast stack": the newest toast in front, the two before it tucked
/// behind with a sliver of each showing above it, a step smaller each.
/// Placed in a `ZStack(alignment: .bottom)` by the screens, padded up to
/// clear the floating action bar.
///
/// A toast's place is a fixed transform of how far back it is: `peek`
/// higher and 5% smaller per step, hanging from its top edge. Arriving,
/// stepping back, stepping forward when one leaves: all the same move on
/// `Theme.snappy`. Only the front toast is read; the rest are slivers.
/// Depth is the stack and a hairline edge, not a shadow. Tap the front one
/// to dismiss it early.
struct ToastStack: View {
    let center: ToastCenter
    /// How much of each tucked toast shows above the one in front.
    private let peek: CGFloat = 10
    /// Fixed height so the slivers line up whatever the text.
    private let height: CGFloat = 56

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(Array(center.toasts.prefix(ToastCenter.shown).enumerated()), id: \.element.id) { k, t in
                row(t, read: k == 0)
                    .frame(height: height)
                    .scaleEffect(1 - CGFloat(k) * 0.05, anchor: .top)
                    .offset(y: -CGFloat(k) * peek)
                    // Paint order is the place: the front toast is on top at once.
                    .zIndex(Double(ToastCenter.shown - k))
                    .transition(.asymmetric(
                        // A new one rises in from just below the front.
                        insertion: .offset(y: 24).combined(with: .opacity),
                        // A dismissed one slides off to the right on the short ease-in.
                        removal: .offset(x: 60).combined(with: .opacity).animation(Theme.exit)))
                    .onTapGesture { if k == 0 { center.dismiss(t.id) } }
            }
        }
        // Cap the width so toasts do not stretch edge to edge on iPad/macOS.
        .frame(maxWidth: 360)
        .padding(.horizontal, 16)
    }

    /// One toast surface. `read` is false for the tucked ones, whose
    /// content fades out so only the front toast's text is on screen.
    private func row(_ t: ToastCenter.Toast, read: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(t.kind))
                .foregroundStyle(color(t.kind))
                .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(t.title).font(Theme.label()).foregroundStyle(Theme.ink).lineLimit(1)
                if let s = t.subtitle { Text(s).font(Theme.meta()).foregroundStyle(Theme.ink3).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .opacity(read ? 1 : 0)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.edge, lineWidth: 0.5))
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

/// Decorative stack of four tinted cards shown by `EmptyState` on the home
/// screen before any redaction exists, after Bencho's "Card swap".
///
/// A card is its slot. The order of `cards` is the only state; a slot is a
/// fixed transform (a step back and up to the right, scaled for depth, with
/// a slight skew), so moving a card is changing its slot and letting one
/// ease-out curve carry it. Tapping sends the front card to the back: it
/// takes the back slot's paint order at once and travels there behind the
/// others while the rest step forward. No lift, no swing, no phases.
struct StackedCards: View {
    /// One card: a stable identity plus its tint.
    private struct Card: Identifiable {
        let id: Int
        let tint: Color
    }

    /// Cards front to back.
    @State private var cards: [Card] = [Theme.pick, Theme.ok, Theme.guide, Color(hex: 0xF5A524)]
        .enumerated().map { Card(id: $0.offset, tint: $0.element) }
    /// Drives the stacked -> in-depth entrance on appear.
    @State private var placed = false

    /// Slot geometry, a 0.6 scale of Bencho's 34/26/70 steps. The depth
    /// step is turned into scale as a 1000pt perspective would.
    private let stepX: CGFloat = 20, stepY: CGFloat = 16, stepZ: CGFloat = 42
    private let cardW: CGFloat = 120, cardH: CGFloat = 150

    private func scale(_ k: Int) -> CGFloat { placed ? 1000 / (1000 + CGFloat(k) * stepZ) : 1 }
    /// Offsets are centred on the stack's middle slot so it sits centred.
    private func x(_ k: Int) -> CGFloat { placed ? (CGFloat(k) - 1.5) * stepX : 0 }
    private func y(_ k: Int) -> CGFloat { placed ? -(CGFloat(k) - 1.5) * stepY : 0 }

    var body: some View {
        ZStack {
            ForEach(cards) { card in
                let k = cards.firstIndex { $0.id == card.id } ?? 0
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [card.tint.opacity(0.95), card.tint.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    // Depth is the stack and a hairline edge; no shadows.
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                    .frame(width: cardW, height: cardH)
                    // A redaction-bar motif in the bottom-left corner.
                    .overlay(alignment: .bottomLeading) {
                        Capsule().fill(.black.opacity(0.6)).frame(width: 56, height: 10).padding(12)
                    }
                    // Bencho's skewY(6deg), applied about the card's centre.
                    .transformEffect(skew)
                    .scaleEffect(scale(k))
                    .offset(x: x(k), y: y(k))
                    // Paint order is the slot: the card sent back goes
                    // behind at once and travels there.
                    .zIndex(Double(cards.count - k))
            }
        }
        .frame(width: cardW + 3 * stepX, height: cardH + 3 * stepY)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptic.tap()
            withAnimation(Theme.slide) { cards.append(cards.removeFirst()) }
        }
        // The stack steps into depth on the same curve a swap uses, as soon
        // as it is on screen: the empty state has no entrance of its own to
        // wait for, so a delay here would be a pause before nothing.
        .onAppear { withAnimation(Theme.slide) { placed = true } }
    }

    /// Constant 6 degree vertical skew about the card centre.
    private var skew: CGAffineTransform {
        let t = CGFloat(tan(6 * Double.pi / 180))
        return CGAffineTransform(translationX: 0, y: -cardW / 2 * t)
            .concatenating(CGAffineTransform(a: 1, b: t, c: 0, d: 1, tx: 0, ty: 0))
    }
}

// MARK: - Hand-off to an assistant

/// A chat app the redacted file can be handed to. Neither app documents a
/// "send a file" link, so the hand-off copies the file to the pasteboard,
/// opens the app by scheme (its website if it is not installed) and asks
/// the user to paste.
enum Assistant: String, CaseIterable, Identifiable {
    case claude, chatgpt
    var id: String { rawValue }

    var name: String {
        switch self { case .claude: "Claude"; case .chatgpt: "ChatGPT" }
    }
    /// The app's URL scheme. A bare scheme opens the app on its last screen.
    var appURL: URL {
        switch self { case .claude: URL(string: "claude://")!; case .chatgpt: URL(string: "chatgpt://")! }
    }
    /// Web fallback when the app is not installed.
    var webURL: URL {
        switch self { case .claude: URL(string: "https://claude.ai/new")!; case .chatgpt: URL(string: "https://chatgpt.com/")! }
    }
    /// Asset-catalog name of the brand mark, a template SVG tinted by the
    /// button (Claude's spark, OpenAI's knot).
    var mark: String {
        switch self { case .claude: "ClaudeMark"; case .chatgpt: "ChatGPTMark" }
    }
}

/// Small round button that hands the file to one assistant. Same size and
/// surface as the delete button in `RecordDetailView.actions`.
struct AssistantButton: View {
    let assistant: Assistant
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(assistant.mark)
                .resizable().scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(Theme.ink)
                .frame(width: 46, height: 46)
                .background(Theme.surface2, in: Circle())
                .overlay(Circle().strokeBorder(Theme.edge, lineWidth: 0.5))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Send to \(assistant.name)")
    }
}

// MARK: - Misc

/// Uppercase, tracked, monospaced caption used as a card section heading
/// ("VAULT KEY", "NOTES").
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.eyebrow()).tracking(0.66)
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
            .font(Theme.label(12))
            .foregroundStyle(tint)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.inlay, in: Capsule())
    }
}

// MARK: - Swipe to delete

/// Drag a card left to reveal a trash button behind it; tap the button to
/// delete. Built by hand because the record list is a `LazyVStack` in a
/// `ScrollView`, not a `List`, so `swipeActions` is unavailable.
///
/// A horizontal drag past `revealWidth / 2` snaps the card open; anything
/// shorter snaps it shut. Only one card is open at a time: `openID` is shared
/// by the list, so opening one closes the others.
struct SwipeToDelete<Content: View>: View {
    let id: UUID
    @Binding var openID: UUID?
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @GestureState private var drag: CGFloat = 0
    private let revealWidth: CGFloat = 72

    private var isOpen: Bool { openID == id }
    private var offset: CGFloat {
        let base: CGFloat = isOpen ? -revealWidth : 0
        // Rubber-band past the reveal, and never past the right edge.
        return min(0, max(base + drag, -revealWidth - 24))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                Haptic.tap()
                onDelete()
            } label: {
                Image(systemName: "trash").font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: revealWidth - 12, height: 52)
                    .background(Theme.guide.opacity(0.85), in: RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Delete")
            .opacity(min(1, -offset / revealWidth))
            .scaleEffect(0.8 + 0.2 * min(1, -offset / revealWidth))

            content()
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24, coordinateSpace: .local)
                        .updating($drag) { v, state, _ in
                            // Horizontal intent only; a vertical drag belongs to the scroll view.
                            guard abs(v.translation.width) > abs(v.translation.height) else { return }
                            state = v.translation.width
                        }
                        .onEnded { v in
                            guard abs(v.translation.width) > abs(v.translation.height) else { return }
                            let open = isOpen ? v.translation.width < revealWidth / 2 : v.translation.width < -revealWidth / 2
                            withAnimation(Theme.snappy) { openID = open ? id : nil }
                        })
        }
        .animation(Theme.snappy, value: isOpen)
        .animation(Theme.quick, value: drag == 0)
    }
}
