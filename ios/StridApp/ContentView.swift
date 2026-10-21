//
//  ContentView.swift
//  StridApp
//
//  Hexagonal architecture role: **inbound adapter root** (UI).
//
//  The root view is intentionally trivial: it asks the composition root for
//  a fully wired `HomeViewModel` and hands it to `HomeView`. Keeping the
//  `DIContainer` reference here, at the very top of the view tree, means no
//  nested view needs to know the container exists.
//

import SwiftUI

/// Root view of the app; hosts the file-redaction home screen.
struct ContentView: View {
    var body: some View {
        // `HomeView` stores the view model in `@State`, so SwiftUI keeps the
        // instance created on the first evaluation of this body for the
        // lifetime of the view.
        HomeView(vm: DIContainer.shared.makeHomeViewModel())
    }
}
