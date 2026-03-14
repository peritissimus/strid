// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StridKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StridKit", targets: ["StridKit"]),
    ],
    targets: [
        .target(name: "StridKit"),
        .testTarget(name: "StridKitTests", dependencies: ["StridKit"]),
    ]
)
