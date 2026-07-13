import Foundation
import Testing
@testable import OpenWhisper

@Test
func productIdentityUsesCanonicalMacValues() {
    #expect(ProductIdentity.name == "OpenWhisper")
    #expect(ProductIdentity.slug == "openwhisper")
    #expect(ProductIdentity.defaultBundleIdentifier == "app.openwhisper.mac")
    #expect(ProductIdentity.keychainService == "app.openwhisper.mac.ChatGPTSession")
    #expect(
        ProductIdentity.recoveryAPIKeychainService
            == "app.openwhisper.mac.OpenAICompatibleAPIKey"
    )
    #expect(
        ProductIdentity.licenseReceiptKeychainService
            == "app.openwhisper.mac.LicenseReceipt"
    )
    #expect(
        ProductIdentity.licenseDeviceKeychainService
            == "app.openwhisper.mac.LicenseDevice"
    )
    #expect(ProductIdentity.installedAppURL.path == "/Applications/OpenWhisper.app")
    #expect(ProductIdentity.userAgent.hasPrefix("OpenWhisper/"))
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

    #expect(contents.contains("OPENWHISPER_APP_NAME=\(ProductIdentity.name)"))
    #expect(contents.contains("OPENWHISPER_BUNDLE_ID=\(ProductIdentity.defaultBundleIdentifier)"))
}

@Test
func productIdentityBuildsApplicationSupportPaths() {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

    #expect(
        ProductIdentity.applicationSupportURL(homeDirectoryURL: home).path
            == "/Users/example/Library/Application Support/OpenWhisper"
    )
    #expect(
        ProductIdentity.recoveryURL(homeDirectoryURL: home).path
            == "/Users/example/Library/Application Support/OpenWhisper/Recovery"
    )
}
