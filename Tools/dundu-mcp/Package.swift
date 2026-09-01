// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "dundu-mcp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "dundu-mcp",
            path: "Sources/dundu-mcp",
            exclude: ["Info.plist"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                // A command line tool has no bundle, so TCC has nothing to
                // attribute a Reminders prompt to and the request fails
                // silently. Embedding the plist in __TEXT,__info_plist gives
                // the binary its own identity and usage string.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/dundu-mcp/Info.plist",
                ])
            ]
        )
    ]
)
