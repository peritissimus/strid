import SwiftUI

// MARK: - Platform Compatibility

#if os(macOS)
// Mock types for macOS to match iOS API
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
    static var platformTopBarLeading: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarLeading
        #elseif os(macOS)
        return .navigation
        #endif
    }

    static var platformTopBarTrailing: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #elseif os(macOS)
        return .automatic
        #endif
    }
}
