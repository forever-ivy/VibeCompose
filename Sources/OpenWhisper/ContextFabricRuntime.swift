import Foundation

/// Context is requested by a Skill, but read only by an app-owned adapter after
/// policy evaluation. The enum is intentionally broader than the adapters that
/// are enabled today so configuration and receipts can migrate without another
/// schema break.
enum ContextSourceKind:
    String,
    Codable,
    Sendable,
    Equatable,
    Hashable,
    CaseIterable,
    Identifiable
{
    case voice
    case selection
    case activeApp
    case styleCapsule
    case terminology
    case focusedParagraph
    case openFile
    case workspace
    case editorDiagnostics
    case terminalSession
    case browserPage
    case conversationWindow
    case clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voice:
            return L10n.text("Voice")
        case .selection:
            return L10n.text("Selected text")
        case .activeApp:
            return L10n.text("Active application")
        case .styleCapsule:
            return L10n.text("Style Capsule")
        case .terminology:
            return L10n.text("Terminology")
        case .focusedParagraph:
            return L10n.text("Focused paragraph")
        case .openFile:
            return L10n.text("Open file")
        case .workspace:
            return L10n.text("Selected workspace")
        case .editorDiagnostics:
            return L10n.text("Editor diagnostics")
        case .terminalSession:
            return L10n.text("Terminal session")
        case .browserPage:
            return L10n.text("Browser page")
        case .conversationWindow:
            return L10n.text("Conversation window")
        case .clipboard:
            return L10n.text("Clipboard")
        }
    }

    var isAvailableInCurrentRuntime: Bool {
        switch self {
        case .voice, .selection, .activeApp, .styleCapsule, .terminology:
            return true
        case .focusedParagraph,
             .openFile,
             .workspace,
             .editorDiagnostics,
             .terminalSession,
             .browserPage,
             .conversationWindow,
             .clipboard:
            return false
        }
    }

    /// Ordinary Settings expose only sources that can actually be captured by
    /// the current runtime. Future adapters remain visible to Skill authors in
    /// compatibility reports, but are not presented as non-functional product
    /// controls.
    static var userVisibleSettingsSources: [ContextSourceKind] {
        allCases.filter(\.isAvailableInCurrentRuntime)
    }
}

struct ContextRequest:
    Codable,
    Sendable,
    Equatable
{
    var required: [ContextSourceKind]
    var optional: [ContextSourceKind]

    init(
        required: [ContextSourceKind] = [.voice],
        optional: [ContextSourceKind] = []
    ) {
        self.required = Self.normalized(required)
        if !self.required.contains(.voice) {
            self.required.insert(.voice, at: 0)
        }
        let requiredSet = Set(self.required)
        self.optional = Self.normalized(optional).filter {
            !requiredSet.contains($0)
        }
    }

    var allSources: [ContextSourceKind] {
        required + optional
    }

    private static func normalized(
        _ values: [ContextSourceKind]
    ) -> [ContextSourceKind] {
        var seen = Set<ContextSourceKind>()
        return values.filter { seen.insert($0).inserted }
    }
}

enum ContextRetentionPolicy:
    String,
    Codable,
    Sendable,
    Equatable,
    CaseIterable
{
    case sessionOnly
    case redactedReceipts
}

struct ContextSourceSetting:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    var source: ContextSourceKind
    var isEnabled: Bool
    var maximumCharacters: Int

    var id: ContextSourceKind { source }

    init(
        source: ContextSourceKind,
        isEnabled: Bool,
        maximumCharacters: Int
    ) {
        self.source = source
        self.isEnabled = isEnabled
        self.maximumCharacters = min(20_000, max(0, maximumCharacters))
    }
}

struct ContextSnapshotItem:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    let id: UUID
    let source: ContextSourceKind
    let content: String
    let characterCount: Int
    let contentSHA256: String
    let capturedAt: Date

    init(
        id: UUID = UUID(),
        source: ContextSourceKind,
        content: String,
        contentSHA256: String,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.content = content
        self.characterCount = content.count
        self.contentSHA256 = contentSHA256
        self.capturedAt = capturedAt
    }
}

/// Immutable, session-scoped context. Callers replace the value instead of
/// mutating it, which prevents Retry or a Skill switch from silently retaining
/// an earlier selection.
struct ContextSnapshot:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    let id: UUID
    let sessionID: UUID
    let installationID: UUID
    let createdAt: Date
    let items: [ContextSnapshotItem]

    init(
        id: UUID = UUID(),
        sessionID: UUID = UUID(),
        installationID: UUID,
        createdAt: Date = Date(),
        items: [ContextSnapshotItem] = []
    ) {
        self.id = id
        self.sessionID = sessionID
        self.installationID = installationID
        self.createdAt = createdAt
        self.items = items
    }

    static func empty(
        installationID: UUID,
        sessionID: UUID = UUID()
    ) -> ContextSnapshot {
        ContextSnapshot(
            sessionID: sessionID,
            installationID: installationID
        )
    }

    func content(for source: ContextSourceKind) -> String? {
        items.first { $0.source == source }?.content
    }
}

/// A redacted, per-source decision. It deliberately stores categories and
/// counts only; the captured Context text remains session-only.
struct ContextDecision:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    let source: ContextSourceKind
    let requestedAs: String
    let availability: String
    let permission: String
    let captureResult: String
    let characterCount: Int
    let decisionCode: String

    var id: ContextSourceKind { source }
}

struct ContextReceipt:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    let id: UUID
    let sessionID: UUID
    let installationID: UUID
    let requestedSources: [ContextSourceKind]
    let grantedSources: [ContextSourceKind]
    let deniedSources: [ContextSourceKind]
    let characterCounts: [String: Int]
    let decisions: [ContextDecision]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        installationID: UUID,
        requestedSources: [ContextSourceKind],
        grantedSources: [ContextSourceKind],
        deniedSources: [ContextSourceKind],
        characterCounts: [String: Int],
        decisions: [ContextDecision] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.installationID = installationID
        self.requestedSources = requestedSources
        self.grantedSources = grantedSources
        self.deniedSources = deniedSources
        self.characterCounts = characterCounts
        self.decisions = decisions
        self.createdAt = createdAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        installationID = try container.decode(UUID.self, forKey: .installationID)
        requestedSources = try container.decode([ContextSourceKind].self, forKey: .requestedSources)
        grantedSources = try container.decode([ContextSourceKind].self, forKey: .grantedSources)
        deniedSources = try container.decode([ContextSourceKind].self, forKey: .deniedSources)
        characterCounts = try container.decode([String: Int].self, forKey: .characterCounts)
        decisions = try container.decodeIfPresent([ContextDecision].self, forKey: .decisions) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID
        case installationID
        case requestedSources
        case grantedSources
        case deniedSources
        case characterCounts
        case decisions
        case createdAt
    }

    static func from(
        request: ContextRequest,
        snapshot: ContextSnapshot,
        deniedSources: [ContextSourceKind] = [],
        unavailableSources: [ContextSourceKind] = [],
        emptySources: [ContextSourceKind] = []
    ) -> ContextReceipt {
        let granted = normalized(
            [.voice] + snapshot.items.map(\.source)
        )
        let denied = normalized(
            deniedSources
                + unavailableSources
                + emptySources
        )
        let deniedSet = Set(deniedSources)
        let unavailableSet = Set(unavailableSources)
        let emptySet = Set(emptySources)
        let snapshotBySource = Dictionary(
            uniqueKeysWithValues: snapshot.items.map {
                ($0.source, $0)
            }
        )
        let decisions = request.allSources.map { source in
            let item = snapshotBySource[source]
            let requestedAs = request.required.contains(source)
                ? "required"
                : "optional"
            let availability = source.isAvailableInCurrentRuntime
                ? "available"
                : "unavailable"
            let permission: String
            if deniedSet.contains(source) {
                permission = "denied"
            } else if unavailableSet.contains(source) {
                permission = "unavailable"
            } else {
                permission = "allowed"
            }
            let captureResult: String
            let decisionCode: String
            if source == .voice || item != nil {
                captureResult = "captured"
                decisionCode = "granted"
            } else if unavailableSet.contains(source) {
                captureResult = "unavailable"
                decisionCode = "unavailable"
            } else if emptySet.contains(source) {
                captureResult = "empty"
                decisionCode = "empty"
            } else if deniedSet.contains(source) {
                captureResult = "denied"
                decisionCode = "denied"
            } else {
                captureResult = "not_requested"
                decisionCode = "not_requested"
            }
            return ContextDecision(
                source: source,
                requestedAs: requestedAs,
                availability: availability,
                permission: permission,
                captureResult: captureResult,
                characterCount: item?.characterCount ?? 0,
                decisionCode: decisionCode
            )
        }
        return ContextReceipt(
            sessionID: snapshot.sessionID,
            installationID: snapshot.installationID,
            requestedSources: request.allSources,
            grantedSources: granted,
            deniedSources: denied,
            characterCounts: Dictionary(
                uniqueKeysWithValues: snapshot.items.map {
                    ($0.source.rawValue, $0.characterCount)
                }
            ),
            decisions: decisions
        )
    }

    private static func normalized(
        _ sources: [ContextSourceKind]
    ) -> [ContextSourceKind] {
        var seen = Set<ContextSourceKind>()
        return sources.filter { seen.insert($0).inserted }
    }
}

struct ContextPolicyDecision:
    Sendable,
    Equatable
{
    let allowed: [ContextSourceKind]
    let denied: [ContextSourceKind]
    let unavailable: [ContextSourceKind]
    let blocksExecution: Bool
}

struct ContextPolicy:
    Sendable
{
    func evaluate(
        request: ContextRequest,
        settings: [ContextSourceSetting],
        sensitiveApplication: Bool
    ) -> ContextPolicyDecision {
        let settingsBySource = Dictionary(
            uniqueKeysWithValues: settings.map { ($0.source, $0) }
        )
        var allowed: [ContextSourceKind] = []
        var denied: [ContextSourceKind] = []
        var unavailable: [ContextSourceKind] = []

        for source in request.allSources {
            if source == .voice {
                allowed.append(source)
                continue
            }
            guard source.isAvailableInCurrentRuntime else {
                unavailable.append(source)
                continue
            }
            if sensitiveApplication,
               source != .styleCapsule,
               source != .terminology
            {
                denied.append(source)
                continue
            }
            let enabled = settingsBySource[source]?.isEnabled
                ?? Self.defaultEnabled(source)
            if enabled {
                allowed.append(source)
            } else {
                denied.append(source)
            }
        }

        let blockedRequired = request.required.contains {
            denied.contains($0) || unavailable.contains($0)
        }
        return ContextPolicyDecision(
            allowed: allowed,
            denied: denied,
            unavailable: unavailable,
            blocksExecution: blockedRequired
        )
    }

    private static func defaultEnabled(
        _ source: ContextSourceKind
    ) -> Bool {
        switch source {
        case .voice, .selection, .activeApp, .styleCapsule, .terminology:
            return true
        default:
            return false
        }
    }
}
