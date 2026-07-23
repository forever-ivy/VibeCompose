import Foundation
import Testing
@testable import VibeWhisper

@Test
func softwareUpdateConfigurationRequiresHTTPSFeedAndEd25519PublicKey() throws {
    let publicKey = Data(repeating: 0x42, count: 32).base64EncodedString()
    let configuration = try SoftwareUpdateConfiguration(
        infoDictionary: [
            "SUFeedURL": "https://updates.vibewhisper.example/stable/appcast.xml",
            "SUPublicEDKey": publicKey,
        ]
    )

    #expect(
        configuration.feedURL.absoluteString
            == "https://updates.vibewhisper.example/stable/appcast.xml"
    )
    #expect(configuration.publicKey == publicKey)
}

@Test
func softwareUpdateConfigurationRejectsIncompleteOrUnsafeConfiguration() {
    #expect(throws: SoftwareUpdateConfiguration.ValidationError.incomplete) {
        _ = try SoftwareUpdateConfiguration(infoDictionary: [:])
    }
    #expect(throws: SoftwareUpdateConfiguration.ValidationError.invalidFeedURL) {
        _ = try SoftwareUpdateConfiguration(
            infoDictionary: [
                "SUFeedURL": "http://updates.vibewhisper.example/appcast.xml",
                "SUPublicEDKey": Data(repeating: 1, count: 32)
                    .base64EncodedString(),
            ]
        )
    }
    #expect(throws: SoftwareUpdateConfiguration.ValidationError.invalidFeedURL) {
        _ = try SoftwareUpdateConfiguration(
            infoDictionary: [
                "SUFeedURL": "https://user@updates.vibewhisper.example/appcast.xml",
                "SUPublicEDKey": Data(repeating: 1, count: 32)
                    .base64EncodedString(),
            ]
        )
    }
    #expect(throws: SoftwareUpdateConfiguration.ValidationError.invalidPublicKey) {
        _ = try SoftwareUpdateConfiguration(
            infoDictionary: [
                "SUFeedURL": "https://updates.vibewhisper.example/appcast.xml",
                "SUPublicEDKey": Data(repeating: 1, count: 31)
                    .base64EncodedString(),
            ]
        )
    }
}

@MainActor
@Test
func unconfiguredSparkleUpdaterFailsClosedWithoutStartingAnUpdate() throws {
    let temporaryBundleURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "VibeWhisperUpdaterTests-\(UUID().uuidString).bundle",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: temporaryBundleURL,
        withIntermediateDirectories: true
    )
    defer {
        try? FileManager.default.removeItem(at: temporaryBundleURL)
    }
    try """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleIdentifier</key>
      <string>app.vibewhisper.tests.updater</string>
    </dict>
    </plist>
    """.write(
        to: temporaryBundleURL.appendingPathComponent("Info.plist"),
        atomically: true,
        encoding: .utf8
    )
    let bundle = try #require(Bundle(url: temporaryBundleURL))
    let updater = SparkleSoftwareUpdater(bundle: bundle)

    let snapshot = updater.snapshot()
    #expect(snapshot.isConfigured == false)
    #expect(snapshot.canCheckForUpdates == false)
    switch updater.checkForUpdates() {
    case .success:
        Issue.record("An unconfigured updater unexpectedly started a check.")
    case .failure(.busy):
        Issue.record("An unconfigured updater reported a busy update session.")
    case .failure(.unavailable(let detail)):
        #expect(
            detail
                == SoftwareUpdateConfiguration.ValidationError.incomplete
                .localizedDescription
        )
    }
}
