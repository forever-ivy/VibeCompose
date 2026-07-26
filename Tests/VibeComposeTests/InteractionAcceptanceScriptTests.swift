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
    #expect(source.contains("general|account|dictation"))
    #expect(source.contains("--open-onboarding"))
    #expect(source.contains("--onboarding-step"))
    #expect(source.contains("--open-history"))
    #expect(source.contains("--open-terminology"))
    #expect(source.contains("--open-quick-add"))
    #expect(source.contains("--open-skill-library"))
    #expect(source.contains("--open-skill-switcher"))
    #expect(source.contains("--preview-demo"))
    #expect(source.contains("replace|paste|fallback"))
    #expect(source.contains("--preview-demo-scenario"))
    #expect(source.contains("official Computer Use"))
    #expect(source.contains("--restore"))
}
