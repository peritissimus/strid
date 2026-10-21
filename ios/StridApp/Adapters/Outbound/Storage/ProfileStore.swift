//
//  ProfileStore.swift
//  StridApp
//
//  Owns the single `RedactionProfile`, loads it at launch and writes it back
//  on every change. Lives on the main actor because the profile screens bind
//  straight to `profile`.
//
//  Stored at Application Support/Strid/profile.json with complete file
//  protection: on iOS it is readable only while the device is unlocked.
//

import Foundation

@MainActor
@Observable
final class ProfileStore {
    /// The live profile. Every mutation is persisted.
    var profile: RedactionProfile {
        didSet { if profile != oldValue { persist() } }
    }

    private let url: URL?

    init() {
        let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Strid", isDirectory: true)
        if let base, !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        url = base?.appendingPathComponent("profile.json")
        if let url, let data = try? Data(contentsOf: url), let p = try? JSONDecoder().decode(RedactionProfile.self, from: data) {
            profile = p
        } else {
            profile = RedactionProfile()
        }
    }

    private func persist() {
        guard let url, let data = try? JSONEncoder().encode(profile) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
