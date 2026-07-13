// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "OpenWhisper",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "OpenWhisper", targets: ["OpenWhisper"]),
        .library(
            name: "OpenWhisperLicensing",
            targets: ["OpenWhisperLicensing"]
        ),
        .executable(
            name: "OpenWhisperLicenseTool",
            targets: ["OpenWhisperLicenseTool"]
        ),
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
            name: "OpenWhisper",
            dependencies: [
                "OpenWhisperLicensing",
                .product(name: "PermissionFlow", package: "PermissionFlow"),
                .product(name: "SystemSettingsKit", package: "PermissionFlow"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/OpenWhisper",
            exclude: ["Resources"]
        ),
        .target(
            name: "OpenWhisperLicensing",
            path: "Sources/OpenWhisperLicensing"
        ),
        .executableTarget(
            name: "OpenWhisperLicenseTool",
            dependencies: ["OpenWhisperLicensing"],
            path: "Sources/OpenWhisperLicenseTool"
        ),
        .testTarget(
            name: "OpenWhisperTests",
            dependencies: ["OpenWhisper", "OpenWhisperLicensing"],
            path: "Tests/OpenWhisperTests"
        ),
        .testTarget(
            name: "OpenWhisperLicensingTests",
            dependencies: ["OpenWhisperLicensing"],
            path: "Tests/OpenWhisperLicensingTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
