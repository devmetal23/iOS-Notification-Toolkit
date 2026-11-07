// swift-tools-version: 6.0
import PackageDescription

// Platform-independent core: storage, capture rules and pure logic.
// Builds on Linux so `swift test` runs in CI without Xcode.
let package = Package(
    name: "ToolkitCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ToolkitCore", targets: ["ToolkitCore"]),
    ],
    targets: [
        // Apple platforms import the SDK's SQLite3 module; Linux links the system libsqlite3.
        .systemLibrary(
            name: "CSQLite",
            pkgConfig: "sqlite3",
            providers: [.apt(["libsqlite3-dev"])]
        ),
        .target(
            name: "ToolkitCore",
            dependencies: [
                .target(name: "CSQLite", condition: .when(platforms: [.linux])),
            ]
        ),
        .testTarget(
            name: "ToolkitCoreTests",
            dependencies: ["ToolkitCore"]
        ),
    ]
)
