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
    static let maximumSelectionCharacterLimit =
        20_000
    static let maximumGrantCount = 200

    var selectionEnabled = true
    var maximumSelectionCharacters =
        defaultMaximumSelectionCharacters
    var permissionGrants:
        [SkillPermissionGrant] = []
    var sourceSettings:
        [ContextSourceSetting] = []
    var retentionPolicy:
        ContextRetentionPolicy = .sessionOnly
    var recentReceipts:
        [ContextReceipt] = []

    init() {}

    init(
        selectionEnabled: Bool = true,
        maximumSelectionCharacters: Int =
            defaultMaximumSelectionCharacters,
        permissionGrants:
            [SkillPermissionGrant] = [],
        sourceSettings:
            [ContextSourceSetting] = [],
        retentionPolicy:
            ContextRetentionPolicy = .sessionOnly,
        recentReceipts:
            [ContextReceipt] = []
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
        self.sourceSettings = Self.normalizedSettings(
            sourceSettings,
            selectionEnabled: selectionEnabled,
            maximumSelectionCharacters:
                self.maximumSelectionCharacters
        )
        self.retentionPolicy = retentionPolicy
        self.recentReceipts = Array(
            recentReceipts.suffix(50)
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
        sourceSettings = Self.normalizedSettings(
            try container.decodeIfPresent(
                [ContextSourceSetting].self,
                forKey: .sourceSettings
            ) ?? [],
            selectionEnabled: selectionEnabled,
            maximumSelectionCharacters:
                maximumSelectionCharacters
        )
        retentionPolicy = try container.decodeIfPresent(
            ContextRetentionPolicy.self,
            forKey: .retentionPolicy
        ) ?? .sessionOnly
        recentReceipts = Array(
            (try container.decodeIfPresent(
                [ContextReceipt].self,
                forKey: .recentReceipts
            ) ?? []).suffix(50)
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
        recentReceipts.removeAll()
    }

    func setting(
        for source: ContextSourceKind
    ) -> ContextSourceSetting {
        sourceSettings.first { $0.source == source }
            ?? ContextSourceSetting(
                source: source,
                isEnabled: source.isAvailableInCurrentRuntime,
                maximumCharacters:
                    source == .selection
                    ? maximumSelectionCharacters
                    : 4_000
            )
    }

    mutating func setSourceEnabled(
        _ isEnabled: Bool,
        source: ContextSourceKind
    ) {
        sourceSettings.removeAll { $0.source == source }
        var setting = self.setting(for: source)
        setting.isEnabled = isEnabled
        sourceSettings.append(setting)
        if source == .selection {
            selectionEnabled = isEnabled
        }
        sourceSettings = Self.normalizedSettings(
            sourceSettings,
            selectionEnabled: selectionEnabled,
            maximumSelectionCharacters:
                maximumSelectionCharacters
        )
    }

    mutating func record(
        receipt: ContextReceipt
    ) {
        guard retentionPolicy == .redactedReceipts else {
            return
        }
        recentReceipts.removeAll { $0.id == receipt.id }
        recentReceipts.append(receipt)
        recentReceipts = Array(recentReceipts.suffix(50))
    }

    private static func boundedMaximumCharacters(
        _ value: Int
    ) -> Int {
        min(
            maximumSelectionCharacterLimit,
            max(100, value)
        )
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

    private static func normalizedSettings(
        _ values: [ContextSourceSetting],
        selectionEnabled: Bool,
        maximumSelectionCharacters: Int
    ) -> [ContextSourceSetting] {
        var seen = Set<ContextSourceKind>()
        var output: [ContextSourceSetting] = values.compactMap { value -> ContextSourceSetting? in
            guard seen.insert(value.source).inserted else {
                return nil
            }
            return ContextSourceSetting(
                source: value.source,
                isEnabled: value.source.isAvailableInCurrentRuntime
                    && value.isEnabled,
                maximumCharacters: value.maximumCharacters
            )
        }
        if !seen.contains(.selection) {
            output.append(
                ContextSourceSetting(
                    source: .selection,
                    isEnabled: selectionEnabled,
                    maximumCharacters:
                        maximumSelectionCharacters
                )
            )
        }
        return output.sorted { $0.source.rawValue < $1.source.rawValue }
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
    var clipboardCapture:
        @MainActor @Sendable (
            LaunchAppContext?,
            Int
        ) async -> SelectionContextCaptureResult
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
        clipboardCapture:
            @escaping @MainActor @Sendable (
                LaunchAppContext?,
                Int
            ) async -> SelectionContextCaptureResult = {
                launchContext,
                maximumCharacters in
                await ClipboardSelectionContextCapture
                    .capture(
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
        self.clipboardCapture =
            clipboardCapture
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
            "VibeCompose will read only the text you selected in %@, up to %ld characters. It will not read the rest of the window, document, clipboard, or screen.",
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
    var blocksExecution = false
    var blockedRequiredSources:
        [ContextSourceKind] = []
    var deniedSources:
        [ContextSourceKind] = []
    var unavailableSources:
        [ContextSourceKind] = []
    var emptySources:
        [ContextSourceKind] = []
    var contextSnapshot:
        ContextSnapshot?
    var contextReceipt:
        ContextReceipt?

    var selectedCharacterCount: Int {
        promptContext.selection?.count
            ?? 0
    }

    var blockedMessage: String? {
        guard blocksExecution else { return nil }
        let names = blockedRequiredSources
            .map(\.title)
            .joined(separator: ", ")
        if blockedRequiredSources == [.selection] {
            switch reason {
            case .selectionDisabled,
                 .permissionDenied,
                 .voiceOnly,
                 .sensitiveApplication:
                return L10n.text(
                    "This Skill requires selected text, but access is not allowed. Allow selected text for this Skill or choose another Skill."
                )
            case .selectionTooLarge:
                return L10n.text(
                    "This Skill requires selected text, but the selection is too large. Select a smaller range and try again."
                )
            default:
                return L10n.text(
                    "This Skill requires selected text. Select text in the target app and press the dictation shortcut again, or choose another Skill."
                )
            }
        }
        return L10n.format(
            "This Skill cannot run because required context is missing: %@. Provide the context or choose another Skill.",
            names
        )
    }

    mutating func blockMissingRequiredSources(
        for request: ContextRequest
    ) {
        let captured = Set(
            contextSnapshot?.items.map(\.source) ?? []
        )
        let missing = request.required.filter {
            $0 != .voice && !captured.contains($0)
        }
        guard !missing.isEmpty else { return }
        blocksExecution = true
        blockedRequiredSources = Self.normalized(
            blockedRequiredSources + missing
        )
        emptySources = Self.normalized(
            emptySources + missing.filter {
                !deniedSources.contains($0)
                    && !unavailableSources.contains($0)
            }
        )
    }

    mutating func appendSnapshotItem(
        source: ContextSourceKind,
        content: String
    ) {
        guard let existing = contextSnapshot else {
            return
        }
        let normalized = content.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty else { return }
        var items = existing.items.filter { $0.source != source }
        items.append(
            ContextSnapshotItem(
                source: source,
                content: normalized,
                contentSHA256:
                    SelectionContextSnapshot.digest(
                        for: normalized
                    )
            )
        )
        contextSnapshot = ContextSnapshot(
            id: existing.id,
            sessionID: existing.sessionID,
            installationID: existing.installationID,
            createdAt: existing.createdAt,
            items: items
        )
    }

    mutating func refreshReceipt(
        request: ContextRequest,
        deniedSources: [ContextSourceKind]? = nil
    ) {
        guard let contextSnapshot else { return }
        if let deniedSources {
            self.deniedSources = Self.normalized(
                deniedSources
            )
        }
        contextReceipt = ContextReceipt.from(
            request: request,
            snapshot: contextSnapshot,
            deniedSources:
                Self.normalized(
                    self.deniedSources
                ),
            unavailableSources:
                Self.normalized(
                    unavailableSources
                ),
            emptySources:
                Self.normalized(
                    emptySources
                )
        )
    }

    private static func normalized(
        _ sources: [ContextSourceKind]
    ) -> [ContextSourceKind] {
        var seen = Set<ContextSourceKind>()
        return sources.filter { seen.insert($0).inserted }
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
        let request = plan.profile.contextRequest
        let sensitiveApplication = !SensitiveAppPolicy
            .permitsContext(
                bundleIdentifier:
                    launchAppContext?.bundleIdentifier,
                privacy: privacyConfig
            )
        let policyDecision = ContextPolicy().evaluate(
            request: request,
            settings: contextConfig.sourceSettings,
            sensitiveApplication: sensitiveApplication
        )
        var initialItems: [ContextSnapshotItem] = []
        if request.allSources.contains(.activeApp),
           policyDecision.allowed.contains(.activeApp),
           let launchAppContext
        {
            let appDescription = [
                launchAppContext.localizedName,
                launchAppContext.bundleIdentifier,
            ].compactMap { $0 }.joined(separator: " — ")
            if !appDescription.isEmpty {
                initialItems.append(
                    ContextSnapshotItem(
                        source: .activeApp,
                        content: appDescription,
                        contentSHA256:
                            SelectionContextSnapshot.digest(
                                for: appDescription
                            )
                    )
                )
            }
        }
        let initialSnapshot = ContextSnapshot(
            id: plan.contextSnapshot.id,
            sessionID: plan.contextSnapshot.sessionID,
            installationID: plan.installation.id,
            createdAt: plan.contextSnapshot.createdAt,
            items: initialItems
        )
        let policyDenied =
            policyDecision.denied
        let policyUnavailable =
            policyDecision.unavailable
        let policyBlocked = request.required.filter {
            policyDenied.contains($0)
                || policyUnavailable.contains($0)
        }
        if policyDecision.blocksExecution {
            var prepared = PreparedSkillContext(
                reason: sensitiveApplication
                    ? .sensitiveApplication
                    : .selectionDisabled,
                blocksExecution: true,
                blockedRequiredSources:
                    policyBlocked,
                deniedSources:
                    policyDenied,
                unavailableSources:
                    policyUnavailable,
                contextSnapshot:
                    initialSnapshot
            )
            prepared.refreshReceipt(
                request: request
            )
            return prepared
        }
        guard request.allSources.contains(
            .selection
        ) else {
            // Handle clipboard / focusedParagraph captures when selection is
            // not requested. These are lightweight, permission-free reads that
            // run after policy and sensitive-app checks.
            var prepared = PreparedSkillContext(
                reason: .notRequested,
                deniedSources:
                    policyDenied,
                unavailableSources:
                    policyUnavailable,
                contextSnapshot: initialSnapshot
            )

            if request.allSources.contains(.clipboard),
               policyDecision.allowed.contains(.clipboard)
                   || !policyDecision.denied.contains(.clipboard)
            {
                let pasteboardText = NSPasteboard.general
                    .string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let text = pasteboardText, !text.isEmpty {
                    prepared.promptContext.clipboard = text
                    prepared.grantedCapabilities.append(.clipboard)
                    prepared.appendSnapshotItem(
                        source: .clipboard,
                        content: text
                    )
                } else {
                    prepared.emptySources.append(.clipboard)
                }
            }

            if request.allSources.contains(.focusedParagraph),
               policyDecision.allowed.contains(.focusedParagraph)
                   || !policyDecision.denied.contains(.focusedParagraph)
            {
                let paragraph = await MainActor.run {
                    FocusedElementInspector.captureFocusedParagraph(
                        in: launchAppContext,
                        maximumCharacters:
                            contextConfig.maximumSelectionCharacters
                    )
                }
                if let text = paragraph {
                    prepared.promptContext.focusedParagraph = text
                    prepared.grantedCapabilities.append(.focusedParagraph)
                    prepared.appendSnapshotItem(
                        source: .focusedParagraph,
                        content: text
                    )
                } else {
                    prepared.emptySources.append(.focusedParagraph)
                }
            }

            prepared.blockMissingRequiredSources(
                for: request
            )
            prepared.refreshReceipt(
                request: request
            )
            prepared.refreshReceipt(request: request)
            return prepared
        }

        guard policyDecision.allowed.contains(.selection) else {
            var prepared = PreparedSkillContext(
                reason: sensitiveApplication
                    ? .sensitiveApplication
                    : .selectionDisabled,
                deniedSources:
                    policyDenied,
                unavailableSources:
                    policyUnavailable,
                contextSnapshot: initialSnapshot
            )
            prepared.refreshReceipt(
                request: request
            )
            return prepared
        }

        guard contextConfig.selectionEnabled
        else {
            var prepared = PreparedSkillContext(
                reason: .selectionDisabled,
                deniedSources: [.selection],
                contextSnapshot: initialSnapshot
            )
            prepared.blockMissingRequiredSources(for: request)
            prepared.refreshReceipt(request: request)
            return prepared
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
            var prepared = PreparedSkillContext(
                reason:
                    .sensitiveApplication,
                deniedSources: [.selection],
                contextSnapshot: initialSnapshot
            )
            prepared.blockMissingRequiredSources(for: request)
            prepared.refreshReceipt(request: request)
            return prepared
        }

        let scope = contextConfig.scope(
            skillID: plan.skill.id,
            capability: .selection
        )
        var persistentGrant:
            SkillPermissionGrant?

        switch scope {
        case .denied:
            var prepared = PreparedSkillContext(
                reason: .permissionDenied,
                deniedSources: [.selection],
                contextSnapshot: initialSnapshot
            )
            prepared.blockMissingRequiredSources(for: request)
            prepared.refreshReceipt(request: request)
            return prepared
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
                var prepared = PreparedSkillContext(
                    reason: .voiceOnly,
                    deniedSources: [.selection],
                    contextSnapshot: initialSnapshot
                )
                prepared.blockMissingRequiredSources(for: request)
                prepared.refreshReceipt(request: request)
                return prepared
            case .cancel:
                return PreparedSkillContext(
                    reason: .cancelled,
                    shouldCancel: true,
                    contextSnapshot: initialSnapshot
                )
            }
        }

        // Permission dialogs and mic prompts may have fronted VibeCompose.
        // Restore the launch app before reading AX selection so hosts that
        // clear or hide selection while backgrounded still yield text.
        let didRestore = LaunchAppContext.restoreFrontmostIfNeeded(
            launchAppContext
        )
        // activate(options:) is asynchronous; give the host a brief settle
        // window so AXFocusedUIElement / AXSelectedText become readable again.
        if didRestore {
            try? await Task.sleep(for: .milliseconds(80))
        }

        let accessibilityCapture =
            selectionProvider.capture(
                launchAppContext,
                contextConfig
                    .maximumSelectionCharacters
            )
        let selectionCapture:
            SelectionContextCaptureResult
        switch accessibilityCapture {
        case .unavailable, .targetChanged:
            // WeChat and a few custom-rendered editors expose no usable AX
            // document subtree. After policy and user permission checks, use
            // the host's normal Copy command as a narrow read-only fallback.
            // The implementation restores the previous clipboard before
            // returning and never runs for ordinary non-context Skills.
            selectionCapture =
                await selectionProvider
                    .clipboardCapture(
                        launchAppContext,
                        contextConfig
                            .maximumSelectionCharacters
                    )
        default:
            selectionCapture =
                accessibilityCapture
        }

        switch selectionCapture {
        case .captured(let snapshot):
            guard
                !snapshot.selectedText
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty
            else {
                var prepared = PreparedSkillContext(
                    reason: .noSelection,
                    persistentGrant:
                        persistentGrant,
                    emptySources: [.selection],
                    contextSnapshot: initialSnapshot
                )
                prepared.blockMissingRequiredSources(
                    for: request
                )
                prepared.refreshReceipt(
                    request: request
                )
                return prepared
            }
            var fabricSnapshot = initialSnapshot
            var items = fabricSnapshot.items
            items.append(
                ContextSnapshotItem(
                    source: .selection,
                    content: snapshot.selectedText,
                    contentSHA256: snapshot.textDigest
                )
            )
            fabricSnapshot = ContextSnapshot(
                id: fabricSnapshot.id,
                sessionID: fabricSnapshot.sessionID,
                installationID: fabricSnapshot.installationID,
                createdAt: fabricSnapshot.createdAt,
                items: items
            )
            var prepared = PreparedSkillContext(
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
                    persistentGrant,
                deniedSources:
                    policyDenied,
                unavailableSources:
                    policyUnavailable,
                contextSnapshot: fabricSnapshot
            )
            prepared.refreshReceipt(
                request: request
            )
            return prepared
        case .noSelection:
            var prepared = PreparedSkillContext(
                reason: .noSelection,
                persistentGrant:
                    persistentGrant,
                emptySources: [.selection],
                contextSnapshot: initialSnapshot
            )
            prepared.blockMissingRequiredSources(for: request)
            prepared.refreshReceipt(request: request)
            return prepared
        case .unavailable:
            var prepared = PreparedSkillContext(
                reason: .unavailable,
                persistentGrant:
                    persistentGrant,
                unavailableSources: [.selection],
                contextSnapshot: initialSnapshot
            )
            prepared.blockMissingRequiredSources(for: request)
            prepared.refreshReceipt(request: request)
            return prepared
        case .targetChanged:
            var prepared = PreparedSkillContext(
                reason: .targetChanged,
                persistentGrant:
                    persistentGrant,
                emptySources: [.selection],
                contextSnapshot: initialSnapshot
            )
            prepared.blockMissingRequiredSources(for: request)
            prepared.refreshReceipt(request: request)
            return prepared
        case .tooLarge:
            var prepared = PreparedSkillContext(
                reason: .selectionTooLarge,
                persistentGrant:
                    persistentGrant,
                emptySources: [.selection],
                contextSnapshot: initialSnapshot
            )
            prepared.blockMissingRequiredSources(for: request)
            prepared.refreshReceipt(request: request)
            return prepared
        }
    }
}
