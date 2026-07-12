// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "OpenWhisper",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "OpenWhisper", targets: ["OpenWhisper"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/jaywcjlove/PermissionFlow.git",
            revision: "3c5ae16337d3448e8561e00352a01b68f92fe974"
        ),
    ],
    targets: [
        .executableTarget(
            name: "OpenWhisper",
            dependencies: [
                .product(name: "PermissionFlow", package: "PermissionFlow"),
                .product(name: "SystemSettingsKit", package: "PermissionFlow"),
            ],
            path: "Sources/OpenWhisper",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "OpenWhisperTests",
            dependencies: ["OpenWhisper"],
            path: "Tests/OpenWhisperTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
