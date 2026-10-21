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
        // On macOS give the window a tall, phone-like default so the layout
        // designed for iOS reads well without resizing.
        #if os(macOS)
        .defaultSize(width: 520, height: 900)
        #endif
    }
}
