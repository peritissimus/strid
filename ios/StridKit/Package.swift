// swift-tools-version: 5.9
//
// Package.swift
// StridKit
//
// Swift Package manifest for the on-device PII detection and redaction toolkit.
//
// The package is split into three layers so that consumers can depend on only
// what they need:
//
//   StridKit        Pure detection: entity models, recognizers (regex, NLTagger,
//                   NSDataDetector, Indian banking), scoring, dedup, the text
//                   redactor, reversible token maps and the encrypted vault.
//                   No UI, no document formats. Portable to iOS and macOS.
//
//   StridDocuments  Format handlers that sit on top of StridKit: plain text,
//                   DOCX/RTF, images (via Vision OCR) and PDF (via PDFKit, with
//                   OCR fallback). Reads a file, redacts, writes the same format.
//
//   StridCLI        The `strid` command-line tool (redact / restore / detect /
//                   eval / entities). macOS-only in practice because it is an
//                   executable, but it compiles against the same two libraries
//                   the iOS app uses.
//
// The only third-party dependency is swift-argument-parser, used solely by the CLI.
import PackageDescription

let package = Package(
    name: "StridKit",
    // iOS 17 / macOS 14 are required for the `switch` expression syntax used throughout and
    // for the Vision / PDFKit APIs the document layer relies on.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        // Detection-only library; what the iOS app's domain layer imports.
        .library(name: "StridKit", targets: ["StridKit"]),
        // Document-format layer (PDF, image, DOCX, text); depends on StridKit.
        .library(name: "StridDocuments", targets: ["StridDocuments"]),
        // Command-line executable, installed as `strid`.
        .executable(name: "strid", targets: ["StridCLI"]),
    ],
    dependencies: [
        // Declarative CLI parsing for the `strid` executable only.
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        // Core detection engine. Deliberately dependency-free.
        .target(name: "StridKit"),
        // Format handlers; needs StridKit for the engine, entities and token maps.
        .target(name: "StridDocuments", dependencies: ["StridKit"]),
        .executableTarget(
            name: "StridCLI",
            dependencies: [
                "StridKit",
                "StridDocuments",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // Unit tests cover the detection layer only (recognizers, engine, tokenizer, vault).
        .testTarget(name: "StridKitTests", dependencies: ["StridKit", "StridDocuments"]),
    ]
)
