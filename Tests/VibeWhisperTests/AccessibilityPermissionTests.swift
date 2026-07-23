import Foundation
import Testing
@testable import OpenWhisper

@Test
func accessibilityRepairActionsPreferGuidedFlowAndKeepTypedSettingsFallback() {
    let actions = AccessibilityPermission.repairActions()

    #expect(actions.count == 3)
    #expect(actions[0].title == "Guide Accessibility Access")
    #expect(actions[0].kind == .guidedAccessibilityAccess)
    #expect(actions[1].title == "Open Accessibility Settings")
    #expect(
        actions[1].kind == .openSettings(
            PermissionSettingsDestination(
                url: URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!,
                paneIdentifier: "com.apple.settings.PrivacySecurity.extension",
                anchor: "Privacy_Accessibility"
            )
        )
    )
    #expect(actions[2].title == "Refresh Status")
    #expect(actions[2].kind == .refreshStatus)
}

@Test
func accessibilityRepairGuidanceFlagsAdHocBuilds() {
    let guidance = AccessibilityPermission.repairGuidance(
        appName: "OpenWhisper",
        signatureState: .adHocOrUnsigned,
        bundleURL: URL(fileURLWithPath: "/Users/tester/Projects/openwhisper/dist/OpenWhisper.app")
    )

    #expect(guidance.detail?.contains("ad-hoc") == true)
    #expect(guidance.detail?.contains("Apple Development") == true)
}

@Test
func accessibilityRepairGuidanceIncludesManualAddPathOutsideApplications() {
    let guidance = AccessibilityPermission.repairGuidance(
        appName: "OpenWhisper",
        signatureState: .stable(teamIdentifier: "TEAM123"),
        bundleURL: URL(fileURLWithPath: "/Users/tester/Projects/openwhisper/dist/OpenWhisper.app")
    )

    #expect(guidance.detail?.contains("/Users/tester/Projects/openwhisper/dist/OpenWhisper.app") == true)
    #expect(guidance.detail?.contains("click +") == true)
}
