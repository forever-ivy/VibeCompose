import Foundation
import Testing

@Test
func interactionAcceptanceUsesInstalledAppAndPrivatePresentationMode() throws {
    let root = URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath
    )
    let scriptURL = root.appendingPathComponent(
        "scripts/interaction_acceptance.sh"
    )
    let source = try String(
        contentsOf: scriptURL,
        encoding: .utf8
    )

    #expect(source.contains("/Applications/$APP_NAME.app"))
    #expect(source.contains("--interaction-acceptance"))
    #expect(source.contains("--open-settings"))
    #expect(source.contains("--settings-pane"))
    #expect(source.contains("--open-onboarding"))
    #expect(source.contains("--onboarding-step"))
    #expect(source.contains("--open-history"))
    #expect(source.contains("--open-terminology"))
    #expect(source.contains("--open-quick-add"))
    #expect(source.contains("official Computer Use"))
    #expect(source.contains("--restore"))
}
