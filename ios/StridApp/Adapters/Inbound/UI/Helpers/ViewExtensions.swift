//
//  ViewExtensions.swift
//  StridApp
//
//  Small shims that let the text-scanner views use iOS navigation-bar APIs
//  without sprinkling `#if os(...)` through every screen. On macOS the iOS
//  types and modifiers do not exist, so this file provides no-op or
//  equivalent stand-ins with the same spelling.
//

import SwiftUI

// MARK: - Platform Compatibility

#if os(macOS)
// Mock types for macOS to match iOS API
//
// `NavigationBarItem.TitleDisplayMode` is UIKit-only. Declaring a shadow enum
// with the same cases lets call sites write `.inline` / `.large` on both
// platforms; the value is simply ignored on macOS.
struct NavigationBarItem {
    enum TitleDisplayMode {
        case inline
        case large
        case automatic
    }
}
#endif

// MARK: - Platform-specific View Modifiers

extension View {
    /// Sets navigation bar title display mode (iOS only, no-op on macOS)
    ///
    /// `@ViewBuilder` so the two branches can return different opaque types
    /// (`some View` from the modifier vs. `Self`).
    @ViewBuilder
    func platformNavigationBarTitleDisplayMode(_ mode: NavigationBarItem.TitleDisplayMode) -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(mode)
        #elseif os(macOS)
        self
        #endif
    }
}

// MARK: - Platform-specific Toolbar Content

extension ToolbarItemPlacement {
    /// Leading edge of the top bar on iOS; the navigation area on macOS.
    static var platformTopBarLeading: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarLeading
        #elseif os(macOS)
        return .navigation
        #endif
    }

    /// Trailing edge of the top bar on iOS; `.automatic` on macOS, which
    /// places the item in the window toolbar's trailing region.
    static var platformTopBarTrailing: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #elseif os(macOS)
        return .automatic
        #endif
    }
}
