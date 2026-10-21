//
//  ColorPalette.swift
//  StridApp
//
//  Hexagonal architecture role: **design system** (shared by inbound UI
//  adapters; no domain dependencies).
//
//  Palette rationale
//  -----------------
//  Strid is a privacy tool, and the visual language is meant to feel calm and
//  clinical rather than playful. The base is a near-monochrome ramp from
//  almost-black to off-white; colour is reserved for two jobs:
//
//    * one teal accent for interactive elements and brand moments, and
//    * a small set of semantic colours (red / green / amber / blue) whose
//      meaning never changes, so a red highlight always means "this is PII
//      or a problem".
//
//  All constants are namespaced with a `strid` prefix on `Color` so they
//  autocomplete together and never collide with SwiftUI's own colours.
//  Fixed-RGB colours below do not adapt to dark mode; the adaptive ones live
//  in the second extension at the bottom of the file.
//

import SwiftUI

/// Strid color palette - primarily monochrome with accent and semantic colors
extension Color {

    // MARK: - Monochrome

    /// Pure black
    ///
    /// Actually a very dark grey (8% white). True `#000000` looks harsh next
    /// to the off-white surfaces and causes smearing on OLED scrolling.
    static let stridBlack = Color(red: 0.08, green: 0.08, blue: 0.08)

    /// Dark gray - for secondary text
    static let stridDarkGray = Color(red: 0.25, green: 0.25, blue: 0.25)

    /// Medium gray - for borders and dividers
    static let stridGray = Color(red: 0.55, green: 0.55, blue: 0.55)

    /// Light gray - for subtle backgrounds
    static let stridLightGray = Color(red: 0.85, green: 0.85, blue: 0.85)

    /// Off-white - for cards and surfaces
    ///
    /// Slightly below pure white so cards still read as surfaces when placed
    /// on a white page background.
    static let stridOffWhite = Color(red: 0.97, green: 0.97, blue: 0.97)

    /// Pure white
    static let stridWhite = Color.white

    // MARK: - Accent

    /// Primary accent color - teal for modern, tech-focused feel
    ///
    /// Teal was chosen because it is distinct from every semantic colour
    /// below (not red, green, amber or blue), so an accented button is never
    /// mistaken for a status indicator.
    static let stridAccent = Color(red: 0.0, green: 0.69, blue: 0.63)

    /// Light accent - for backgrounds and subtle highlights
    ///
    /// The accent at 10% opacity; used as a tint behind selected rows and
    /// chips so it composes over either light or dark surfaces.
    static let stridAccentLight = Color(red: 0.0, green: 0.69, blue: 0.63).opacity(0.1)

    /// Dark accent - for pressed states
    static let stridAccentDark = Color(red: 0.0, green: 0.55, blue: 0.50)

    // MARK: - Semantic Colors

    /// Error/Danger - for PII detection and warnings
    ///
    /// Also the colour used to highlight detected PII spans in the editor,
    /// so "red = sensitive" is consistent across the app.
    static let stridError = Color(red: 0.93, green: 0.26, blue: 0.21)

    /// Success - for completed actions
    static let stridSuccess = Color(red: 0.20, green: 0.78, blue: 0.35)

    /// Warning - for caution states
    static let stridWarning = Color(red: 1.0, green: 0.73, blue: 0.0)

    /// Info - for informational states
    static let stridInfo = Color(red: 0.0, green: 0.48, blue: 1.0)

    // MARK: - Gradients

    /// Monochrome gradient for backgrounds
    ///
    /// A barely-there diagonal fade between two near-blacks; it adds depth to
    /// dark hero areas without introducing a visible banding edge.
    static let stridMonochromeGradient = LinearGradient(
        colors: [
            Color(red: 0.12, green: 0.12, blue: 0.12),
            Color(red: 0.08, green: 0.08, blue: 0.08)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Subtle gradient for backgrounds
    ///
    /// Light-mode counterpart of `stridMonochromeGradient`: off-white fading
    /// to a slightly darker grey, top to bottom.
    static let stridSubtleGradient = LinearGradient(
        colors: [
            Color(red: 0.97, green: 0.97, blue: 0.97),
            Color(red: 0.94, green: 0.94, blue: 0.94)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Glass Effects

    /// Glass surface color - translucent white
    ///
    /// Intended to be layered over `.ultraThinMaterial` or a dark gradient to
    /// produce a frosted-glass card.
    static let stridGlass = Color.white.opacity(0.1)

    /// Glass border color
    ///
    /// Slightly more opaque than `stridGlass` so a 1pt stroke remains visible
    /// at the card edge.
    static let stridGlassBorder = Color.white.opacity(0.2)
}

// MARK: - Dark Mode Support

/// Colours that follow the system appearance. Prefer these over the fixed
/// monochrome constants for text and page backgrounds.
extension Color {
    /// Adaptive text color - black in light mode, white in dark mode
    static let stridText = Color.primary

    /// Adaptive secondary text
    static let stridTextSecondary = Color.secondary

    /// Adaptive background
    ///
    /// Maps to the platform's primary window background. Computed (not
    /// stored) because the platform colour initialisers differ between
    /// UIKit and AppKit.
    static var stridBackground: Color {
        #if os(iOS)
        return Color(.systemBackground)
        #elseif os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// Adaptive secondary background
    ///
    /// Grouped/inset background on iOS; control background on macOS. Used
    /// behind cards so they lift off `stridBackground`.
    static var stridBackgroundSecondary: Color {
        #if os(iOS)
        return Color(.secondarySystemBackground)
        #elseif os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
