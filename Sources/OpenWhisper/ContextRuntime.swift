import AppKit
import CryptoKit
import Foundation

enum SkillPermissionScope:
    String,
    Codable,
    Sendable,
    Equatable,
    CaseIterable,
    Identifiable
{
    case askEveryTime
    case alwaysAllow
    case denied

    var id: String { rawValue }

    var title: String {
        switch self {
        case .askEveryTime:
            return L10n.text("Ask every time")
        case .alwaysAllow:
            return L10n.text("Always allow")
        case .denied:
            return L10n.text("Never allow")
        }
    }
}

struct SkillPermissionGrant:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    var skillID: String
    var capability: SkillCapability
    var scope: SkillPermissionScope

    var id: String {
        "\(skillID)|\(capability.rawValue)"
    }
}

struct ContextConfig:
    Codable,
    Sendable,
    Equatable
{
    static let defaultMaximumSelectionCharacters =
        6_000
    static let maximumGrantCount = 200

    var selectionEnabled = true
    var maximumSelectionCharacters =
        defaultMaximumSelectionCharacters
    var permissionGrants:
        [SkillPermissionGrant] = []

    init() {}

    init(
        selectionEnabled: Bool = true,
        maximumSelectionCharacters: Int =
            defaultMaximumSelectionCharacters,
        permissionGrants:
            [SkillPermissionGrant] = []
    ) {
        self.selectionEnabled = selectionEnabled
        self.maximumSelectionCharacters =
            Self.boundedMaximumCharacters(
                maximumSelectionCharacters
            )
        self.permissionGrants =
            Self.normalizedGrants(
                permissionGrants
            )
    }

    init(from decoder: any Decoder)
        throws
    {
        let container =
            try decoder.container(
                keyedBy: CodingKeys.self
            )
        selectionEnabled =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .selectionEnabled
            ) ?? true
        maximumSelectionCharacters =
            Self.boundedMaximumCharacters(
                try container.decodeIfPresent(
                    Int.self,
                    forKey:
                        .maximumSelectionCharacters
                ) ?? Self
                    .defaultMaximumSelectionCharacters
            )
        permissionGrants =
            Self.normalizedGrants(
                try container.decodeIfPresent(
                    [SkillPermissionGrant].self,
                    forKey: .permissionGrants
                ) ?? []
            )
    }

    func scope(
        skillID: String,
        capability: SkillCapability
    ) -> SkillPermissionScope {
        permissionGrants.first {
            $0.skillID == skillID
                && $0.capability
                    == capability
        }?.scope ?? .askEveryTime
    }

    mutating func setScope(
        _ scope: SkillPermissionScope,
        skillID: String,
        capability: SkillCapability
    ) {
        permissionGrants.removeAll {
            $0.skillID == skillID
                && $0.capability
                    == capability
        }
        permissionGrants.append(
            SkillPermissionGrant(
                skillID: skillID,
                capability: capability,
                scope: scope
            )
        )
        permissionGrants =
            Self.normalizedGrants(
                permissionGrants
            )
    }

    mutating func revokeAll() {
        permissionGrants.removeAll()
    }

    private static func boundedMaximumCharacters(
        _ value: Int
    ) -> Int {
        min(20_000, max(100, value))
    }

    private static func normalizedGrants(
        _ values: [SkillPermissionGrant]
    ) -> [SkillPermissionGrant] {
        var seen = Set<String>()
        return values.compactMap { grant in
            guard
                SkillDefinition
                    .isValidIdentifier(
                        grant.skillID
                    ),
                grant.capability
                    != .voice,
                grant.capability
                    != .externalAction,
                seen.insert(grant.id)
                    .inserted
            else {
                return nil
            }
            return grant
        }
        .prefix(maximumGrantCount)
        .map { $0 }
    }
}

struct SelectionContextSnapshot:
    @unchecked Sendable,
    Equatable
{
    let target:
        FocusedAXElementReference
    let selectedRange: CFRange
    let selectedText: String
    let textDigest: String

    static func == (
        lhs: SelectionContextSnapshot,
        rhs: SelectionContextSnapshot
    ) -> Bool {
        lhs.target.identity
            == rhs.target.identity
            && lhs.target.processIdentifier
                == rhs.target
                    .processIdentifier
            && lhs.selectedRange.location
                == rhs.selectedRange.location
            && lhs.selectedRange.length
                == rhs.selectedRange.length
            && lhs.selectedText
                == rhs.selectedText
            && lhs.textDigest
                == rhs.textDigest
    }

    static func digest(
        for text: String
    ) -> String {
        SHA256.hash(
            data: Data(text.utf8)
        ).map {
            String(format: "%02x", $0)
        }.joined()
    }
}

enum SelectionContextCaptureResult:
    Sendable,
    Equatable
{
    case captured(
        SelectionContextSnapshot
    )
    case noSelection
    case unavailable
    case targetChanged
    case tooLarge(actual: Int, maximum: Int)
}

enum SelectionContextVerification:
    Sendable,
    Equatable
{
    case unchanged
    case changed
    case unavailable
}

struct SelectionContextProvider:
    Sendable
{
    var capture:
        @MainActor @Sendable (
            LaunchAppContext?,
            Int
        ) -> SelectionContextCaptureResult
    var verify:
        @MainActor @Sendable (
            SelectionContextSnapshot
        ) -> SelectionContextVerification

    init(
        capture:
            @escaping @MainActor @Sendable (
                LaunchAppContext?,
                Int
            ) -> SelectionContextCaptureResult = {
                launchContext,
                maximumCharacters in
                FocusedElementInspector
                    .captureSelectionContext(
                        in: launchContext,
                        maximumCharacters:
                            maximumCharacters
                    )
            },
        verify:
            @escaping @MainActor @Sendable (
                SelectionContextSnapshot
            ) -> SelectionContextVerification = {
                snapshot in
                FocusedElementInspector
                    .verifySelectionContext(
                        snapshot
                    )
            }
    ) {
        self.capture = capture
        self.verify = verify
    }
}

enum ContextAuthorizationChoice:
    Sendable,
    Equatable
{
    case allowOnce
    case alwaysAllow
    case voiceOnly
    case cancel
}

struct ContextPermissionRequest:
    Sendable,
    Equatable
{
    let skillID: String
    let skillName: String
    let capability:
        SkillCapability
    let appName: String?
    let maximumCharacters: Int
}

@MainActor
protocol ContextPermissionPrompting:
    AnyObject
{
    func requestPermission(
        _ request:
            ContextPermissionRequest
    ) async -> ContextAuthorizationChoice
}

@MainActor
final class ContextPermissionPromptController:
    ContextPermissionPrompting
{
    func requestPermission(
        _ request:
            ContextPermissionRequest
    ) async -> ContextAuthorizationChoice {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.format(
            "%@ wants to use selected text",
            request.skillName
        )
        let appName =
            request.appName
            ?? L10n.text(
                "the current app"
            )
        alert.informativeText = L10n.format(
            "OpenWhisper will read only the text you selected in %@, up to %ld characters. It will not read the rest of the window, document, clipboard, or screen.",
            appName,
            request.maximumCharacters
        )
        alert.addButton(
            withTitle:
                L10n.text("Allow Once")
        )
        alert.addButton(
            withTitle:
                L10n.text("Always Allow")
        )
        alert.addButton(
            withTitle:
                L10n.text("Voice Only")
        )
        alert.addButton(
            withTitle:
                L10n.text("Cancel")
        )

        NSApplication.shared.activate(
            ignoringOtherApps: true
        )
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .allowOnce
        case .alertSecondButtonReturn:
            return .alwaysAllow
        case .alertThirdButtonReturn:
            return .voiceOnly
        default:
            return .cancel
        }
    }
}

enum ContextPreparationReason:
    String,
    Sendable,
    Equatable
{
    case notRequested
    case selectionDisabled
    case permissionDenied
    case voiceOnly
    case sensitiveApplication
    case noSelection
    case unavailable
    case targetChanged
    case selectionTooLarge
    case captured
    case cancelled
}

struct PreparedSkillContext:
    @unchecked Sendable,
    Equatable
{
    var promptContext =
        SkillPromptContext()
    var selectionSnapshot:
        SelectionContextSnapshot?
    var grantedCapabilities:
        [SkillCapability] = []
    var reason:
        ContextPreparationReason =
            .notRequested
    var persistentGrant:
        SkillPermissionGrant?
    var shouldCancel = false

    var selectedCharacterCount: Int {
        promptContext.selection?.count
            ?? 0
    }
}

@MainActor
struct ContextBroker {
    let selectionProvider:
        SelectionContextProvider

    init(
        selectionProvider:
            SelectionContextProvider =
                .init()
    ) {
        self.selectionProvider =
            selectionProvider
    }

    func prepare(
        plan:
            ResolvedSkillExecutionPlan,
        launchAppContext:
            LaunchAppContext?,
        contextConfig:
            ContextConfig,
        privacyConfig:
            PrivacyConfig,
        permissionPrompter:
            any ContextPermissionPrompting
    ) async -> PreparedSkillContext {
        let capabilities =
            plan.skill.requiredCapabilities
                + plan.skill
                    .optionalCapabilities
        guard capabilities.contains(
            .selection
        ) else {
            return PreparedSkillContext(
                reason: .notRequested
            )
        }

        guard contextConfig.selectionEnabled
        else {
            return PreparedSkillContext(
                reason: .selectionDisabled
            )
        }

        guard
            SensitiveAppPolicy
                .permitsContext(
                    bundleIdentifier:
                        launchAppContext?
                            .bundleIdentifier,
                    privacy: privacyConfig
                )
        else {
            return PreparedSkillContext(
                reason:
                    .sensitiveApplication
            )
        }

        let scope = contextConfig.scope(
            skillID: plan.skill.id,
            capability: .selection
        )
        var persistentGrant:
            SkillPermissionGrant?

        switch scope {
        case .denied:
            return PreparedSkillContext(
                reason: .permissionDenied
            )
        case .alwaysAllow:
            break
        case .askEveryTime:
            let choice =
                await permissionPrompter
                    .requestPermission(
                        ContextPermissionRequest(
                            skillID:
                                plan.skill.id,
                            skillName:
                                plan.skill
                                    .localizedName,
                            capability:
                                .selection,
                            appName:
                                launchAppContext?
                                    .localizedName,
                            maximumCharacters:
                                contextConfig
                                    .maximumSelectionCharacters
                        )
                    )
            switch choice {
            case .allowOnce:
                break
            case .alwaysAllow:
                persistentGrant =
                    SkillPermissionGrant(
                        skillID:
                            plan.skill.id,
                        capability:
                            .selection,
                        scope:
                            .alwaysAllow
                    )
            case .voiceOnly:
                return PreparedSkillContext(
                    reason: .voiceOnly
                )
            case .cancel:
                return PreparedSkillContext(
                    reason: .cancelled,
                    shouldCancel: true
                )
            }
        }

        switch selectionProvider.capture(
            launchAppContext,
            contextConfig
                .maximumSelectionCharacters
        ) {
        case .captured(let snapshot):
            return PreparedSkillContext(
                promptContext:
                    SkillPromptContext(
                        selection:
                            snapshot
                                .selectedText
                    ),
                selectionSnapshot:
                    snapshot,
                grantedCapabilities: [
                    .selection,
                ],
                reason: .captured,
                persistentGrant:
                    persistentGrant
            )
        case .noSelection:
            return PreparedSkillContext(
                reason: .noSelection,
                persistentGrant:
                    persistentGrant
            )
        case .unavailable:
            return PreparedSkillContext(
                reason: .unavailable,
                persistentGrant:
                    persistentGrant
            )
        case .targetChanged:
            return PreparedSkillContext(
                reason: .targetChanged,
                persistentGrant:
                    persistentGrant
            )
        case .tooLarge:
            return PreparedSkillContext(
                reason: .selectionTooLarge,
                persistentGrant:
                    persistentGrant
            )
        }
    }
}
