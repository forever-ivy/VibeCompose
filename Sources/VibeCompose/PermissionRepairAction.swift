import Foundation
import SystemSettingsKit

struct PermissionSettingsDestination: Sendable, Equatable {
    let url: URL
    let paneIdentifier: String?
    let anchor: String?

    static let privacySecurityPaneIdentifier = "com.apple.settings.PrivacySecurity.extension"

    static let accessibility = PermissionSettingsDestination(
        url: URL(string: "x-apple.systempreferences:\(privacySecurityPaneIdentifier)?Privacy_Accessibility")!,
        paneIdentifier: privacySecurityPaneIdentifier,
        anchor: "Privacy_Accessibility"
    )

    static let microphone = PermissionSettingsDestination(
        url: URL(string: "x-apple.systempreferences:\(privacySecurityPaneIdentifier)?Privacy_Microphone")!,
        paneIdentifier: privacySecurityPaneIdentifier,
        anchor: "Privacy_Microphone"
    )

    @MainActor
    @discardableResult
    func open() -> Bool {
        if let paneIdentifier {
            return SystemSettings.open(paneIdentifier: paneIdentifier, anchor: anchor)
        }

        return SystemSettings.open(url: url)
    }
}

enum PermissionRepairActionKind: Sendable, Equatable {
    case requestMicrophoneAccess
    case guidedAccessibilityAccess
    case openSettings(PermissionSettingsDestination)
    case refreshStatus
}

enum PermissionRepairActionProminence: Sendable, Equatable {
    case primary
    case secondary
    case utility
}

struct PermissionRepairAction: Sendable, Equatable, Identifiable {
    let title: String
    let kind: PermissionRepairActionKind
    let prominence: PermissionRepairActionProminence

    var id: String {
        switch kind {
        case .requestMicrophoneAccess:
            return "\(title)-microphone-request"
        case .guidedAccessibilityAccess:
            return "\(title)-guide"
        case .openSettings(let destination):
            return "\(title)-\(destination.url.absoluteString)"
        case .refreshStatus:
            return "\(title)-refresh"
        }
    }
}
