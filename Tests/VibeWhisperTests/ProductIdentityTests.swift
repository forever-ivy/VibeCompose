import Foundation
import Testing
@testable import VibeWhisper

@Test
func productIdentityUsesCanonicalMacValues() {
    #expect(ProductIdentity.name == "VibeWhisper")
    #expect(ProductIdentity.slug == "vibewhisper")
    #expect(ProductIdentity.defaultBundleIdentifier == "app.vibewhisper.mac")
    #expect(ProductIdentity.keychainService == "app.vibewhisper.mac.ChatGPTSession")
    #expect(
        ProductIdentity.recoveryAPIKeychainService
            == "app.vibewhisper.mac.OpenAICompatibleAPIKey"
    )
    #expect(ProductIdentity.installedAppURL.path == "/Applications/VibeWhisper.app")
    #expect(ProductIdentity.userAgent.hasPrefix("VibeWhisper/"))
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

    #expect(contents.contains("VIBEWHISPER_APP_NAME=\(ProductIdentity.name)"))
    #expect(contents.contains("VIBEWHISPER_BUNDLE_ID=\(ProductIdentity.defaultBundleIdentifier)"))
}

@Test
func productIdentityBuildsApplicationSupportPaths() {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

    #expect(
        ProductIdentity.applicationSupportURL(homeDirectoryURL: home).path
            == "/Users/example/Library/Application Support/VibeWhisper"
    )
    #expect(
        ProductIdentity.recoveryURL(homeDirectoryURL: home).path
            == "/Users/example/Library/Application Support/VibeWhisper/Recovery"
    )
}
