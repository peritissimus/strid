import SwiftUI

/// Strid color palette - primarily monochrome with accent and semantic colors
extension Color {

    // MARK: - Monochrome

    /// Pure black
    static let stridBlack = Color(red: 0.08, green: 0.08, blue: 0.08)

    /// Dark gray - for secondary text
    static let stridDarkGray = Color(red: 0.25, green: 0.25, blue: 0.25)

    /// Medium gray - for borders and dividers
    static let stridGray = Color(red: 0.55, green: 0.55, blue: 0.55)

    /// Light gray - for subtle backgrounds
    static let stridLightGray = Color(red: 0.85, green: 0.85, blue: 0.85)

    /// Off-white - for cards and surfaces
    static let stridOffWhite = Color(red: 0.97, green: 0.97, blue: 0.97)

    /// Pure white
    static let stridWhite = Color.white

    // MARK: - Accent

    /// Primary accent color - indigo for trust and security
    static let stridAccent = Color(red: 0.34, green: 0.33, blue: 0.84)

    /// Light accent - for backgrounds and subtle highlights
    static let stridAccentLight = Color(red: 0.34, green: 0.33, blue: 0.84).opacity(0.1)

    /// Dark accent - for pressed states
    static let stridAccentDark = Color(red: 0.25, green: 0.24, blue: 0.65)

    // MARK: - Semantic Colors

    /// Error/Danger - for PII detection and warnings
    static let stridError = Color(red: 0.93, green: 0.26, blue: 0.21)

    /// Success - for completed actions
    static let stridSuccess = Color(red: 0.20, green: 0.78, blue: 0.35)

    /// Warning - for caution states
    static let stridWarning = Color(red: 1.0, green: 0.73, blue: 0.0)

    /// Info - for informational states
    static let stridInfo = Color(red: 0.0, green: 0.48, blue: 1.0)

    // MARK: - Gradients

    /// Monochrome gradient for backgrounds
    static let stridMonochromeGradient = LinearGradient(
        colors: [
            Color(red: 0.12, green: 0.12, blue: 0.12),
            Color(red: 0.08, green: 0.08, blue: 0.08)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Subtle gradient for backgrounds
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
    static let stridGlass = Color.white.opacity(0.1)

    /// Glass border color
    static let stridGlassBorder = Color.white.opacity(0.2)
}

// MARK: - Dark Mode Support

extension Color {
    /// Adaptive text color - black in light mode, white in dark mode
    static let stridText = Color.primary

    /// Adaptive secondary text
    static let stridTextSecondary = Color.secondary

    /// Adaptive background
    static let stridBackground = Color(.systemBackground)

    /// Adaptive secondary background
    static let stridBackgroundSecondary = Color(.secondarySystemBackground)
}
