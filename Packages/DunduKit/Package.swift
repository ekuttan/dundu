// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DunduKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
    ],
    products: [
        .library(name: "DunduKit", targets: ["DunduKit"])
    ],
    targets: [
        .target(name: "DunduKit"),
        .testTarget(name: "DunduKitTests", dependencies: ["DunduKit"]),
    ]
)
