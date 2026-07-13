import Foundation
import Testing

@Test
func accessibilityAcceptanceCoversEveryPrimaryProductSurface() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let scriptURL = root.appendingPathComponent(
        "scripts/accessibility_acceptance.sh"
    )
    let source = try String(contentsOf: scriptURL, encoding: .utf8)

    #expect(source.contains("/Applications/$APP_NAME.app"))
    #expect(source.contains("--accessibility-audit-output"))
    #expect(source.contains("settings-account"))
    #expect(source.contains("settings-dictation"))
    #expect(source.contains("settings-ai-polish"))
    #expect(source.contains("settings-paste"))
    #expect(source.contains("settings-privacy"))
    #expect(source.contains("settings-advanced"))
    #expect(source.contains("\"onboarding\" \"--open-onboarding\""))
    #expect(source.contains("\"history\" \"--open-history\""))
    #expect(source.contains("\"terminology\" \"--open-terminology\""))
    #expect(source.contains("\"quick-add\" \"--open-quick-add\""))
    #expect(source.contains("missingActionableNames"))
    #expect(source.contains("official Computer Use"))
}
