//
//  StridApp.swift
//  StridApp
//
//  Hexagonal architecture role: **application entry point** (outermost
//  inbound edge). The `@main` type owns the SwiftUI scene graph and nothing
//  else; all wiring happens in `DIContainer`, all UI in `ContentView` and
//  below.
//

import SwiftUI

/// SwiftUI app definition for Strid.
@main
struct StridApp: App {
    var body: some Scene {
        // A single window group; the app has no document-based or settings
        // scenes. On iOS this is the one full-screen window.
        WindowGroup {
            ContentView()
        }
        // macOS gets a sidebar + detail window (see `MacRootView`).
        #if os(macOS)
        .defaultSize(width: 1120, height: 760)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { NotificationCenter.default.post(name: .stridOpenFile, object: nil) }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }
        #endif
    }
}

#if os(macOS)
extension Notification.Name {
    /// Posted by the File > Open… menu item; `MacRootView` presents the importer.
    static let stridOpenFile = Notification.Name("strid.openFile")
}
#endif
