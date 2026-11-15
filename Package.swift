// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnippetStudio",
    platforms: [.macOS(.v15)], // v15: text editor that reports the cursor, for Insert buttons
    dependencies: [
        // Pinned exactly: a new version is adopted only on purpose, after review.
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    ],
    targets: [
        .target(name: "SnippetCore", dependencies: ["Yams"]),
        .executableTarget(name: "SnippetStudio", dependencies: ["SnippetCore"]),
        .testTarget(name: "SnippetCoreTests", dependencies: ["SnippetCore"]),
    ]
)
