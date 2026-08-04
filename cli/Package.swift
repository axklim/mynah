// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpellChecker",
    platforms: [.macOS(.v13)],
    products: [
        // Binary names are hyphenated; target/module names can't be, hence the split.
        .executable(name: "spell-checker", targets: ["SpellChecker"]),
        .executable(name: "spell-checker-bar", targets: ["SpellCheckerBar"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "1.9.0")
    ],
    targets: [
        .target(
            name: "SpellCheckerCore",
            path: "Sources/SpellCheckerCore"
        ),
        .target(
            name: "SpellCheckerUI",
            dependencies: ["SpellCheckerCore"],
            path: "Sources/SpellCheckerUI"
        ),
        .executableTarget(
            name: "SpellChecker",
            dependencies: ["SpellCheckerCore"],
            path: "Sources/SpellChecker"
        ),
        .executableTarget(
            name: "SpellCheckerBar",
            dependencies: [
                "SpellCheckerCore",
                "SpellCheckerUI",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/SpellCheckerBar"
        ),
        .testTarget(
            name: "SpellCheckerCoreTests",
            dependencies: ["SpellCheckerCore", "SpellCheckerUI"],
            path: "Tests/SpellCheckerCoreTests"
        )
    ]
)
