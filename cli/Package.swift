// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mynah",
    platforms: [.macOS(.v13)],
    products: [
        // Binary names are lowercase (mynah-bar hyphenated); module names are CamelCase
        // and can't contain hyphens, hence the split.
        .executable(name: "mynah", targets: ["Mynah"]),
        .executable(name: "mynah-bar", targets: ["MynahBar"])
    ],
    dependencies: [
        // Pinned exactly, not `from:`. packaging/strip-preview-macros.sh edits this
        // dependency's Recorder.swift to remove #Preview blocks that only Xcode can expand,
        // and it verifies the file's checksum first — so the version has to be deterministic
        // for every user, not just for whoever resolved it last. Bumping this means
        // re-checking that script. See mynah-vault/Findings/preview-macro-needs-xcode.md.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "1.17.0")
    ],
    targets: [
        .target(
            name: "MynahCore",
            path: "Sources/MynahCore"
        ),
        .target(
            name: "MynahUI",
            dependencies: ["MynahCore"],
            path: "Sources/MynahUI"
        ),
        .executableTarget(
            name: "Mynah",
            dependencies: ["MynahCore"],
            path: "Sources/Mynah"
        ),
        .executableTarget(
            name: "MynahBar",
            dependencies: [
                "MynahCore",
                "MynahUI",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/MynahBar"
        ),
        .testTarget(
            name: "MynahCoreTests",
            dependencies: ["MynahCore", "MynahUI"],
            path: "Tests/MynahCoreTests"
        )
    ]
)
