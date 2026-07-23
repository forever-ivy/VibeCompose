import AppKit
import ApplicationServices
import Foundation
import PermissionFlow
import Security
import SystemSettingsKit

enum AccessibilityPermission {
    typealias TrustCheck = () -> Bool
    typealias TrustPrompt = () -> Bool

    struct RepairGuidance: Sendable, Equatable {
        let subtitle: String
        let detail: String?
    }

    enum SignatureState: Sendable, Equatable {
        case stable(teamIdentifier: String)
        case adHocOrUnsigned
        case unavailable
    }

    private static let promptOptionKey = "AXTrustedCheckOptionPrompt"
    @MainActor
    private static var permissionFlowController = PermissionFlow.makeController(
        configuration: .init(promptForAccessibilityTrust: false)
    )

    /// Live process trust for Accessibility.
    ///
    /// Status UI and paste routing must read this without prompting. Some macOS
    /// builds disagree briefly between the plain and options APIs right after a
    /// grant outside the app, so treat either affirmative as trusted.
    static func isTrusted(
        trustCheck: TrustCheck = { liveProcessIsTrusted() }
    ) -> Bool {
        trustCheck()
    }

    /// Non-prompting dual check used by production status reads.
    static func liveProcessIsTrusted() -> Bool {
        let options = [
            promptOptionKey: false,
        ] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            return true
        }
        return AXIsProcessTrusted()
    }

    /// Status chip title for Settings / setup tiles.
    ///
    /// Granted always wins. When the process is not trusted, prefer an honest
    /// "not enabled" label; only ad-hoc builds escalate to "Re-add required"
    /// because TCC often keeps a stale toggle that never maps to the binary.
    static func statusTitle(
        isTrusted: Bool,
        signatureState: SignatureState = signatureState()
    ) -> String {
        if isTrusted {
            return L10n.text("Granted")
        }

        switch signatureState {
        case .adHocOrUnsigned:
            return L10n.text("Re-add required")
        case .stable, .unavailable:
            return L10n.text("Not enabled")
        }
    }

    @discardableResult
    static func requestTrustIfNeeded(
        trustCheck: TrustCheck = { liveProcessIsTrusted() },
        prompt: TrustPrompt = {
            let options = [
                promptOptionKey: true,
            ] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
    ) -> Bool {
        guard !trustCheck() else {
            return true
        }

        return prompt()
    }

    static func repairActions() -> [PermissionRepairAction] {
        [
            PermissionRepairAction(
                title: L10n.text("Guide Accessibility Access"),
                kind: .guidedAccessibilityAccess,
                prominence: .primary
            ),
            PermissionRepairAction(
                title: L10n.text("Open Accessibility Settings"),
                kind: .openSettings(accessibilitySettingsDestination()),
                prominence: .secondary
            ),
            PermissionRepairAction(
                title: L10n.text("Refresh Status"),
                kind: .refreshStatus,
                prominence: .utility
            ),
        ]
    }

    static func accessibilitySettingsDestination() -> PermissionSettingsDestination {
        .accessibility
    }

    @MainActor
    static func guideAccess(sourceFrameInScreen: CGRect? = nil) {
        guard !isTrusted() else {
            return
        }

        _ = requestTrustIfNeeded()
        permissionFlowController.authorize(
            pane: .accessibility,
            suggestedAppURLs: [Bundle.main.bundleURL],
            sourceFrameInScreen: sourceFrameInScreen
        )
    }

    @MainActor
    @discardableResult
    static func openAccessibilitySettings() -> Bool {
        accessibilitySettingsDestination().open()
    }

    static func signatureState(bundleURL: URL = Bundle.main.bundleURL) -> SignatureState {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(), &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return .unavailable
        }

        var signingInformation: CFDictionary?
        let copyStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )
        guard copyStatus == errSecSuccess,
              let signingInformation,
              let signingInfo = signingInformation as? [String: Any] else {
            return .unavailable
        }

        return signatureState(signingInformation: signingInfo)
    }

    static func repairGuidance(
        appName: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "VibeWhisper",
        signatureState: SignatureState = signatureState(),
        bundleURL: URL = Bundle.main.bundleURL
    ) -> RepairGuidance {
        let subtitle = L10n.format(
            "Allow Accessibility for %@ so it can send Cmd+V to the active text cursor. Until then, it only copies to the clipboard.",
            appName
        )

        var details: [String] = []

        switch signatureState {
        case .stable:
            break
        case .adHocOrUnsigned:
            details.append(
                L10n.format(
                    "This build is ad-hoc signed or missing a stable team identity, so macOS may open Accessibility without creating a toggle for %@. Repackage it with Apple Development signing, reopen the packaged app, then request access again.",
                    appName
                )
            )
        case .unavailable:
            details.append(
                L10n.format(
                    "VibeWhisper could not inspect its own code signature. If Accessibility opens without a %@ row, rebuild the packaged app before requesting access again.",
                    appName
                )
            )
        }

        if isInstalledInApplications(bundleURL: bundleURL) {
            details.append(
                L10n.format(
                    "If %@ still does not appear in the list, click + in Accessibility and add the running app again.",
                    appName
                )
            )
        } else {
            details.append(
                L10n.format(
                    "If %@ still does not appear in the list, click + in Accessibility and add this app manually: %@",
                    appName,
                    bundleURL.path
                )
            )
        }

        return RepairGuidance(
            subtitle: subtitle,
            detail: details.joined(separator: " ")
        )
    }

    private static func signatureState(signingInformation: [String: Any]) -> SignatureState {
        if let teamIdentifier = signingInformation[kSecCodeInfoTeamIdentifier as String] as? String,
           !teamIdentifier.isEmpty {
            return .stable(teamIdentifier: teamIdentifier)
        }

        return .adHocOrUnsigned
    }

    private static func isInstalledInApplications(bundleURL: URL) -> Bool {
        bundleURL.standardizedFileURL.path.hasPrefix("/Applications/")
    }
}
