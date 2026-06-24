// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpellChecker",
    platforms: [.macOS(.v13)],
    products: [
        // Binary name is hyphenated; the target/module name can't be, hence the split.
        .executable(name: "spell-checker", targets: ["SpellChecker"])
    ],
    targets: [
        .executableTarget(
            name: "SpellChecker",
            path: "Sources/SpellChecker"
        )
    ]
)
