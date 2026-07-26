import Foundation
import Testing
@testable import VibeCompose

@Test
func productIdentityUsesCanonicalMacValues() {
    #expect(ProductIdentity.name == "VibeCompose")
    #expect(ProductIdentity.slug == "vibecompose")
    #expect(ProductIdentity.defaultBundleIdentifier == "app.vibecompose.mac")
    #expect(ProductIdentity.keychainService == "app.vibecompose.mac.ChatGPTSession")
    #expect(
        ProductIdentity.recoveryAPIKeychainService
            == "app.vibecompose.mac.OpenAICompatibleAPIKey"
    )
    #expect(ProductIdentity.installedAppURL.path == "/Applications/VibeCompose.app")
    #expect(ProductIdentity.userAgent.hasPrefix("VibeCompose/"))
}

@Test
func productEnvironmentMatchesRuntimeIdentity() throws {
    let repositoryURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contents = try String(
        contentsOf: repositoryURL.appendingPathComponent("product.env"),
        encoding: .utf8
    )

    #expect(contents.contains("VIBECOMPOSE_APP_NAME=\(ProductIdentity.name)"))
    #expect(contents.contains("VIBECOMPOSE_BUNDLE_ID=\(ProductIdentity.defaultBundleIdentifier)"))
}

@Test
func productIdentityBuildsApplicationSupportPaths() {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

    #expect(
        ProductIdentity.applicationSupportURL(homeDirectoryURL: home).path
            == "/Users/example/Library/Application Support/VibeCompose"
    )
    #expect(
        ProductIdentity.recoveryURL(homeDirectoryURL: home).path
            == "/Users/example/Library/Application Support/VibeCompose/Recovery"
    )
}
