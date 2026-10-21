// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StridKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StridKit", targets: ["StridKit"]),
        .library(name: "StridDocuments", targets: ["StridDocuments"]),
        .executable(name: "strid", targets: ["StridCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(name: "StridKit"),
        .target(name: "StridDocuments", dependencies: ["StridKit"]),
        .executableTarget(
            name: "StridCLI",
            dependencies: [
                "StridKit",
                "StridDocuments",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "StridKitTests", dependencies: ["StridKit"]),
    ]
)
