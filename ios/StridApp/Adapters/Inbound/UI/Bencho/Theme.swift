//
//  Theme.swift
//  StridApp
//
//  Design tokens and reusable styling for the Bencho-flavoured UI (`HomeView`,
//  `RecordDetailView`, `Components.swift`). Everything visual that is not a
//  one-off lives here: colours, radii, animation curves, type ramps, the
//  per-entity tint map, the `.card()` surface modifier, three button styles
//  and the haptics helper. The app forces dark mode (`HomeView` sets
//  `.preferredColorScheme(.dark)`), so these tokens have a single, dark value.
//

import SwiftUI

/// Design tokens lifted from the bencho.dev language: pure black canvas, near-black surfaces,
/// white-at-9% glass, ink in five steps, one cool accent, tight 160 ms transitions.
enum Theme {
    // MARK: Canvas & surfaces

    /// Window background. Pure black so OLED panels switch pixels off.
    static let bg = Color(hex: 0x000000)
    /// Opaque panel used behind previews and the processing overlay card.
    static let surface = Color(hex: 0x0F0F0F)
    /// Slightly lighter opaque surface: toasts, round icon buttons.
    static let surface2 = Color(hex: 0x181818)
    /// Lightest opaque surface: record thumbnails.
    static let surface3 = Color(hex: 0x202020)
    /// Reserved board tone between surface2 and surface3.
    static let board = Color(hex: 0x1A1A1A)
    /// Default translucent "glass" card fill (white at 9%).
    static let card = Color.white.opacity(0.09)
    /// Glass fill for the active/selected state of pills.
    static let cardHi = Color.white.opacity(0.12)
    /// Glass used for small insets inside a card (badges, count bubbles).
    static let inlay = Color.white.opacity(0.07)
    /// Hairline stroke drawn around every glass shape.
    static let edge = Color.white.opacity(0.08)

    // MARK: Ink

    /// Primary text and icons.
    static let ink = Color.white
    /// Secondary text (body copy on cards).
    static let ink2 = Color(hex: 0xB4B4B4)
    /// Tertiary text (captions, descriptions).
    static let ink3 = Color(hex: 0x9A9A9A)
    /// Muted labels and metadata.
    static let ink4 = Color(hex: 0x828282)
    /// Faintest ink: timestamps, chevrons, inactive meter bars.
    static let ink5 = Color(hex: 0x6B6B6B)

    // MARK: Signals

    /// Cool blue accent: info toasts, PERSON tint, stacked-card art.
    static let pick = Color(hex: 0x3AA9FF)
    /// Green: success toasts, "REDACTED" badge, zero-item badge.
    static let ok = Color(hex: 0x34D17A)
    /// Burnt orange: errors, "ORIGINAL" badge, identity-document tint.
    static let ember = Color(hex: 0xB8431C)
    /// Pink: date-of-birth tint and stacked-card art.
    static let guide = Color(hex: 0xFF5C84)

    // MARK: Shape

    /// Outer card radius (continuous curve).
    static let radiusCard: CGFloat = 28
    /// Radius for elements nested inside a card.
    static let radiusInner: CGFloat = 16
    /// Radius for small tiles.
    static let radiusTile: CGFloat = 12

    // MARK: Motion

    /// 160 ms ease-out: press feedback, side toggles, key reveal.
    static let quick = Animation.easeOut(duration: 0.16)
    /// Tight spring: filter changes, list reflow, toast dismissal.
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.82)
    /// Looser spring with overshoot: toast arrival.
    static let bouncy = Animation.spring(response: 0.42, dampingFraction: 0.68)
    /// Slow, heavily damped spring: screen entrance and navigation pushes.
    static let settle = Animation.spring(response: 0.55, dampingFraction: 0.86)

    // MARK: Type

    /// Hero numerals and the app wordmark. Medium weight, tracked tight by callers.
    static func display(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .medium, design: .default) }
    /// Card and row titles.
    static func title(_ size: CGFloat = 20) -> Font { .system(size: size, weight: .medium) }
    /// Body and caption copy.
    static func body(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .regular) }
    /// Button and pill labels.
    static func label(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .medium) }
    /// Monospaced: counts, badges, section labels, vault key, text previews.
    static func mono(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .medium, design: .monospaced) }

    /// Per-entity tint used for chips and highlights.
    ///
    /// Keyed by `PIIEntityType.rawValue` so it can be used from places that
    /// only have the string (persisted `RedactionRecord.counts`). Groups
    /// related types onto one colour: contact details purple, identity
    /// documents ember, money/account identifiers amber, places green,
    /// routing codes grey, DOB pink, PERSON the blue accent. Unknown types
    /// fall back to secondary ink.
    static func tint(for raw: String) -> Color {
        switch raw {
        case "PERSON": pick
        case "EMAIL", "PHONE", "IN_PHONE", "URL": Color(hex: 0x8B7CF6)
        case "IN_AADHAAR", "IN_PAN", "US_SSN": ember
        case "CREDIT_CARD", "IN_BANK_ACCOUNT", "IN_IFSC", "IN_UPI_ID", "IN_MICR", "IN_CUSTOMER_ID": Color(hex: 0xF5A524)
        case "LOCATION", "IN_PIN_CODE": ok
        case "IN_TXN_REF", "IN_BRANCH_CODE": ink3
        case "IN_DOB": guide
        default: ink2
        }
    }
}

extension Color {
    /// Builds an sRGB colour from a `0xRRGGBB` literal, e.g. `Color(hex: 0x3AA9FF)`.
    /// Shifts and masks each 8-bit channel out of the integer.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

// MARK: - Surfaces

/// The standard glass card: padding, continuous rounded fill, hairline edge.
struct CardModifier: ViewModifier {
    /// Corner radius; defaults to the outer card radius.
    var radius: CGFloat = Theme.radiusCard
    /// Background fill; defaults to 9% white glass.
    var fill: Color = Theme.card
    /// Inset applied to the content before the background is drawn.
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            // Stroke is drawn inside the shape so it never bleeds past the fill.
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.edge, lineWidth: 0.5))
    }
}

extension View {
    /// Wraps the view in a `CardModifier`. See that type for parameter meaning.
    func card(radius: CGFloat = Theme.radiusCard, fill: Color = Theme.card, padding: CGFloat = 20) -> some View {
        modifier(CardModifier(radius: radius, fill: fill, padding: padding))
    }
}

// MARK: - Press feel

/// Scale-on-press with the 160 ms ease bencho uses everywhere. Works for any label.
///
/// Used where the label already provides its own background (record cards,
/// round icon buttons, the floating Redact menu).
struct PressableStyle: ButtonStyle {
    /// Scale while pressed.
    var scale: CGFloat = 0.96
    /// Opacity while pressed.
    var dim: Double = 0.85
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? dim : 1)
            .animation(Theme.quick, value: configuration.isPressed)
    }
}

/// Solid white pill, black ink: the primary call to action.
///
/// Used for "Share redacted" in `RecordDetailView`.
struct PrimaryPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(15))
            .foregroundStyle(.black)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Color.white, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
    }
}

/// Glass pill, used for secondary actions and chips.
///
/// `active` brightens both the fill and the ink, which is how the filter
/// pills and the reversible toggle show their selected state.
struct GlassPillStyle: ButtonStyle {
    /// Selected / on state.
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(14))
            .foregroundStyle(active ? Theme.ink : Theme.ink2)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(active ? Theme.cardHi : Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.edge, lineWidth: 0.5))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
    }
}

// MARK: - Haptics

/// Thin wrapper over UIKit feedback generators. Each call is a no-op on
/// macOS so call sites need no `#if`.
enum Haptic {
    /// Light tick for toggles, segment changes and secondary taps.
    static func tap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    /// Success notification: job finished, key copied, original restored.
    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    /// Error notification: job failed, wrong password, restore failed.
    static func error() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
}
