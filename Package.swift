// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VibeWhisper",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "VibeWhisper", targets: ["VibeWhisper"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/jaywcjlove/PermissionFlow.git",
            revision: "3c5ae16337d3448e8561e00352a01b68f92fe974"
        ),
        .package(
            url: "https://github.com/sparkle-project/Sparkle.git",
            exact: "2.9.4"
        ),
    ],
    targets: [
        .executableTarget(
            name: "VibeWhisper",
            dependencies: [
                .product(name: "PermissionFlow", package: "PermissionFlow"),
                .product(name: "SystemSettingsKit", package: "PermissionFlow"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/VibeWhisper",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "VibeWhisperTests",
            dependencies: ["VibeWhisper"],
            path: "Tests/VibeWhisperTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
