// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VibeCompose",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "VibeCompose", targets: ["VibeCompose"]),
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
            name: "VibeCompose",
            dependencies: [
                .product(name: "PermissionFlow", package: "PermissionFlow"),
                .product(name: "SystemSettingsKit", package: "PermissionFlow"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/VibeCompose",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "VibeComposeTests",
            dependencies: ["VibeCompose"],
            path: "Tests/VibeComposeTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
