import Foundation
import Testing
@testable import VibeWhisper

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
        appName: "VibeWhisper",
        signatureState: .adHocOrUnsigned,
        bundleURL: URL(fileURLWithPath: "/Users/tester/Projects/vibewhisper/dist/VibeWhisper.app")
    )

    #expect(guidance.detail?.contains("ad-hoc") == true)
    #expect(guidance.detail?.contains("Apple Development") == true)
}

@Test
func accessibilityRepairGuidanceIncludesManualAddPathOutsideApplications() {
    let guidance = AccessibilityPermission.repairGuidance(
        appName: "VibeWhisper",
        signatureState: .stable(teamIdentifier: "TEAM123"),
        bundleURL: URL(fileURLWithPath: "/Users/tester/Projects/vibewhisper/dist/VibeWhisper.app")
    )

    #expect(guidance.detail?.contains("/Users/tester/Projects/vibewhisper/dist/VibeWhisper.app") == true)
    #expect(guidance.detail?.contains("click +") == true)
}

@Test
func accessibilityStatusTitleIsGrantedWhenProcessIsTrusted() {
    #expect(
        AccessibilityPermission.statusTitle(
            isTrusted: true,
            signatureState: .adHocOrUnsigned
        ) == "Granted"
    )
    #expect(
        AccessibilityPermission.statusTitle(
            isTrusted: true,
            signatureState: .stable(teamIdentifier: "TEAM123")
        ) == "Granted"
    )
}

@Test
func accessibilityStatusTitleEscalatesOnlyForAdHocWhenUntrusted() {
    #expect(
        AccessibilityPermission.statusTitle(
            isTrusted: false,
            signatureState: .adHocOrUnsigned
        ) == "Re-add required"
    )
    #expect(
        AccessibilityPermission.statusTitle(
            isTrusted: false,
            signatureState: .stable(teamIdentifier: "TEAM123")
        ) == "Not enabled"
    )
    #expect(
        AccessibilityPermission.statusTitle(
            isTrusted: false,
            signatureState: .unavailable
        ) == "Not enabled"
    )
}

@Test
func accessibilityIsTrustedPrefersInjectedTrustCheckWithoutPrompt() {
    var checks = 0
    let trusted = AccessibilityPermission.isTrusted {
        checks += 1
        return true
    }
    #expect(trusted)
    #expect(checks == 1)

    let untrusted = AccessibilityPermission.isTrusted {
        checks += 1
        return false
    }
    #expect(untrusted == false)
    #expect(checks == 2)
}
