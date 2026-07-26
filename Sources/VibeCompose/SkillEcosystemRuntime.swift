import CryptoKit
import Foundation

struct SkillCollectionItem:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    var id: UUID
    var installationID: UUID
    var portableName: String
    var minimumVersion: String?

    init(
        id: UUID = UUID(),
        installationID: UUID,
        portableName: String,
        minimumVersion: String? = nil
    ) {
        self.id = id
        self.installationID = installationID
        self.portableName = portableName
        self.minimumVersion = minimumVersion
    }
}

/// A Collection is distribution and discovery metadata only. It never merges
/// prompts, permissions, or execution state.
struct SkillCollection:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    var id: UUID
    var name: String
    var summary: String
    var category: String
    var publisher: String?
    var items: [SkillCollectionItem]

    init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        category: String,
        publisher: String? = nil,
        items: [SkillCollectionItem]
    ) {
        self.id = id
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        self.summary = String(summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000))
        self.category = String(category.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        self.publisher = publisher.map { String($0.prefix(120)) }
        var seen = Set<UUID>()
        self.items = items.filter { seen.insert($0.installationID).inserted }.prefix(100).map { $0 }
    }
}

struct SkillCollectionRegistry:
    Sendable,
    Equatable
{
    private(set) var collections: [SkillCollection]

    init(collections: [SkillCollection] = []) {
        var seen = Set<UUID>()
        self.collections = collections.filter { seen.insert($0.id).inserted }
    }

    func collection(id: UUID) -> SkillCollection? {
        collections.first { $0.id == id }
    }

    func search(_ query: String) -> [SkillCollection] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !normalized.isEmpty else { return collections }
        return collections.filter {
            [$0.name, $0.summary, $0.category, $0.publisher ?? ""]
                .joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .contains(normalized)
        }
    }
}

struct SkillEcosystemConfig:
    Codable,
    Sendable,
    Equatable
{
    var favoriteInstallationIDs: [UUID] = []
    var recentInstallationIDs: [UUID] = []
    var collections: [SkillCollection] = []
    var registrySources: [TrustedSkillRegistrySource] = []
    var remoteRegistryEnabled = false

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favoriteInstallationIDs = Array(Set(
            try container.decodeIfPresent([UUID].self, forKey: .favoriteInstallationIDs) ?? []
        )).prefix(500).map { $0 }
        recentInstallationIDs = Self.normalizedRecent(
            try container.decodeIfPresent(
                [UUID].self,
                forKey: .recentInstallationIDs
            ) ?? []
        )
        collections = Array((try container.decodeIfPresent(
            [SkillCollection].self,
            forKey: .collections
        ) ?? []).prefix(200))
        registrySources = Array((try container.decodeIfPresent(
            [TrustedSkillRegistrySource].self,
            forKey: .registrySources
        ) ?? []).prefix(20))
        remoteRegistryEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .remoteRegistryEnabled
        ) ?? false
    }

    mutating func recordRecent(
        installationID: UUID
    ) {
        recentInstallationIDs.removeAll {
            $0 == installationID
        }
        recentInstallationIDs.insert(
            installationID,
            at: 0
        )
        recentInstallationIDs = Self.normalizedRecent(
            recentInstallationIDs
        )
    }

    private static func normalizedRecent(
        _ values: [UUID]
    ) -> [UUID] {
        var seen = Set<UUID>()
        return values.filter {
            seen.insert($0).inserted
        }.prefix(20).map { $0 }
    }
}

struct SkillMenuEntry:
    Sendable,
    Equatable,
    Identifiable
{
    let installationID: UUID
    let skillID: String
    let displayName: String
    let summary: String
    let sourceLabel: String
    let requiresSelection: Bool
    let risk: SkillRiskLevel

    var id: UUID { installationID }
}

enum SkillMenuSearch {
    static func results(
        in entries: [SkillMenuEntry],
        matching query: String,
        locale: Locale = .current
    ) -> [SkillMenuEntry] {
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: locale
            )
        guard !normalized.isEmpty else { return [] }
        return entries.filter { entry in
            [
                entry.displayName,
                entry.summary,
                entry.sourceLabel,
            ]
            .joined(separator: " ")
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: locale
            )
            .contains(normalized)
        }
    }
}

struct SkillMenuSnapshot:
    Sendable,
    Equatable
{
    let current: SkillMenuEntry
    let resolutionSource: SkillResolutionSource
    let nextRunInstallationID: UUID?
    let currentApplicationName: String?
    let currentApplicationBundleIdentifier: String?
    let favorites: [SkillMenuEntry]
    let recent: [SkillMenuEntry]
    let installed: [SkillMenuEntry]

    var resolutionLabel: String {
        resolutionSource.localizedLabel
    }
}

enum SkillMenuAction:
    Sendable,
    Equatable
{
    case useNext(UUID)
    case setApplicationDefault(
        installationID: UUID,
        appName: String?,
        bundleIdentifier: String
    )
    case setGlobalDefault(UUID)
    case toggleFavorite(UUID)
    case clearNextRun
}

/// Next-run selection is intentionally memory-only. It is consumed only after
/// the matching recording has actually started, so a Context block or recorder
/// failure never silently loses the user's choice.
struct NextRunSkillSelection:
    Sendable,
    Equatable
{
    private(set) var installationID: UUID?

    mutating func select(_ installationID: UUID) {
        self.installationID = installationID
    }

    mutating func clear() {
        installationID = nil
    }

    @discardableResult
    mutating func consumeAfterSuccessfulRecordingStart(
        using plan: ResolvedSkillExecutionPlan
    ) -> Bool {
        guard
            plan.source == .nextRun,
            installationID == plan.installation.id
        else {
            return false
        }
        installationID = nil
        return true
    }
}

struct SkillRuntimePresentation:
    Sendable,
    Equatable
{
    let displayName: String
    let source: SkillResolutionSource

    var label: String {
        L10n.format(
            "%@ · %@",
            displayName,
            source.localizedLabel
        )
    }
}

struct ResolvedSkillRun:
    Sendable,
    Equatable,
    Identifiable
{
    let id: UUID
    let sessionID: UUID
    var plan: ResolvedSkillExecutionPlan
    let targetApplicationName: String?
    let targetBundleIdentifier: String?
    let resolvedAt: Date

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        plan: ResolvedSkillExecutionPlan,
        launchAppContext: LaunchAppContext?,
        resolvedAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.plan = plan
        self.targetApplicationName =
            launchAppContext?.localizedName
        self.targetBundleIdentifier =
            launchAppContext?.bundleIdentifier
        self.resolvedAt = resolvedAt
    }

    var presentation: SkillRuntimePresentation {
        SkillRuntimePresentation(
            displayName: plan.skill.localizedName,
            source: plan.source
        )
    }
}

enum SkillMenuCatalog {
    static func entries(
        inventory: CommunitySkillInventory
    ) -> [SkillMenuEntry] {
        let builtIns = SkillRegistry.builtIn
            .orderedDefinitions.map { definition in
                let identity = InstalledSkillIdentity.normalized(
                    definition: definition,
                    sourceID: "builtin"
                )
                return SkillMenuEntry(
                    installationID: identity.id,
                    skillID: definition.id,
                    displayName: definition.localizedName,
                    summary: definition.localizedSummary,
                    sourceLabel: L10n.text("Built-in"),
                    requiresSelection:
                        definition.requiredCapabilities
                            .contains(.selection),
                    risk: definition.output.risk
                )
            }
        let community = inventory.packages
            .filter {
                $0.isActive
                    && $0.compatibility.runtimeStatus
                        == .compatible
            }
            .map { package in
                SkillMenuEntry(
                    installationID: package.installation.id,
                    skillID: package.definition.id,
                    displayName:
                        package.definition.localizedName,
                    summary:
                        package.agentPackage?.metadata.description
                        ?? package.definition.promptInstruction,
                    sourceLabel:
                        package.installation.sourceID
                            .hasPrefix("registry:")
                        ? L10n.text("Community")
                        : L10n.text("Imported"),
                    requiresSelection:
                        package.profile.contextRequest.required
                            .contains(.selection),
                    risk: package.profile.risk
                )
            }
        var seen = Set<UUID>()
        return (builtIns + community)
            .filter { seen.insert($0.installationID).inserted }
            .sorted {
                $0.displayName.localizedStandardCompare(
                    $1.displayName
                ) == .orderedAscending
            }
    }

    static func snapshot(
        plan: ResolvedSkillExecutionPlan,
        inventory: CommunitySkillInventory,
        ecosystem: SkillEcosystemConfig,
        nextRunInstallationID: UUID?,
        currentApplicationName: String?,
        currentApplicationBundleIdentifier: String?
    ) -> SkillMenuSnapshot {
        let entries = entries(inventory: inventory)
        let current = entries.first {
            $0.installationID == plan.installation.id
        } ?? SkillMenuEntry(
            installationID: plan.installation.id,
            skillID: plan.skill.id,
            displayName: plan.skill.localizedName,
            summary: plan.skill.localizedSummary,
            sourceLabel: plan.installation.sourceID == "builtin"
                ? L10n.text("Built-in")
                : L10n.text("Imported"),
            requiresSelection:
                plan.profile.contextRequest.required
                    .contains(.selection),
            risk: plan.profile.risk
        )
        let byID = Dictionary(
            uniqueKeysWithValues: entries.map {
                ($0.installationID, $0)
            }
        )
        return SkillMenuSnapshot(
            current: current,
            resolutionSource: plan.source,
            nextRunInstallationID: nextRunInstallationID,
            currentApplicationName: currentApplicationName,
            currentApplicationBundleIdentifier:
                currentApplicationBundleIdentifier,
            favorites: ecosystem.favoriteInstallationIDs
                .compactMap { byID[$0] },
            recent: ecosystem.recentInstallationIDs
                .compactMap { byID[$0] },
            installed: entries
        )
    }
}

enum SkillCreatorTemplateID:
    String,
    Codable,
    Sendable,
    Equatable,
    CaseIterable,
    Identifiable
{
    case medicalClinicalNote = "medical-clinical-note"
    case medicalMedicationList = "medical-medication-list"
    case medicalReferralLetter = "medical-referral-letter"
    case codingPrompt = "coding-prompt"
    case researchPrompt = "research-prompt"
    case imagePrompt = "image-prompt"
    case bugReport = "bug-report"
    case implementationTask = "implementation-task"
    case commitMessage = "commit-message"
    case pullRequestDescription = "pr-description"
    case meetingNotes = "meeting-notes"
    case actionItems = "action-items"
    case businessEmail = "business-email"
    case customerSupportReply = "customer-support-reply"
    case legalDraftFormatting = "legal-draft-formatting"
    case recruitingFeedback = "recruiting-feedback"
    case localizeOutput = "localize-output"

    var id: String { rawValue }

    var title: String {
        rawValue.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    var category: String {
        switch self {
        case .medicalClinicalNote, .medicalMedicationList, .medicalReferralLetter:
            "Medical"
        case .codingPrompt, .bugReport, .implementationTask,
             .commitMessage, .pullRequestDescription:
            "Development"
        case .researchPrompt, .imagePrompt:
            "Prompts"
        case .meetingNotes, .actionItems:
            "Meetings"
        case .businessEmail, .customerSupportReply:
            "Business"
        case .legalDraftFormatting:
            "Legal"
        case .recruitingFeedback:
            "People"
        case .localizeOutput:
            "Localization"
        }
    }

    var defaultRisk: SkillRiskLevel {
        switch self {
        case .medicalClinicalNote, .medicalMedicationList,
             .medicalReferralLetter, .legalDraftFormatting:
            .high
        default:
            .medium
        }
    }

    var instructions: String {
        switch self {
        case .medicalClinicalNote:
            "Convert the dictation into a structured clinical note. Preserve uncertainty and never invent findings, diagnoses, medication doses, or patient facts."
        case .medicalMedicationList:
            "Produce a medication list with medicine, dose, route, frequency, and stated notes. Mark missing fields as not stated rather than guessing."
        case .medicalReferralLetter:
            "Draft a concise referral letter using only stated clinical facts, reason for referral, and requested next step."
        case .codingPrompt:
            "Turn the dictation into an implementation-ready coding prompt with goal, constraints, affected surfaces, and acceptance criteria."
        case .researchPrompt:
            "Turn the dictation into a bounded research prompt with question, scope, evidence expectations, and output format."
        case .imagePrompt:
            "Create a production-ready image prompt covering subject, composition, lighting, materials, palette, camera, and exclusions."
        case .bugReport:
            "Produce a reproducible bug report with observed behavior, expected behavior, steps, environment, evidence, and impact."
        case .implementationTask:
            "Produce an implementation task with objective, non-goals, constraints, steps, tests, and acceptance criteria."
        case .commitMessage:
            "Create a concise imperative commit subject and an optional body that explains why and notable behavior changes."
        case .pullRequestDescription:
            "Create a pull request description with summary, changes, verification, risks, and reviewer notes."
        case .meetingNotes:
            "Structure the dictation into attendees, discussion, decisions, open questions, and follow-ups without inventing owners."
        case .actionItems:
            "Extract explicit action items only. Include owner and due date only when stated."
        case .businessEmail:
            "Draft a clear business email with an appropriate subject, concise body, explicit ask, and stated deadlines."
        case .customerSupportReply:
            "Draft an empathetic support response that acknowledges the issue, gives verified steps, and avoids unsupported promises."
        case .legalDraftFormatting:
            "Format the supplied legal drafting content into clear clauses while preserving every stated condition and defined term."
        case .recruitingFeedback:
            "Structure recruiting feedback around evidence, role criteria, strengths, concerns, and recommendation without inferring protected traits."
        case .localizeOutput:
            "Localize the dictated source for the requested locale while preserving product names, technical literals, intent, and formatting."
        }
    }
}

struct SkillCreatorDraft:
    Sendable,
    Equatable
{
    var name: String
    var description: String
    var instructions: String
    var license: String?
    var version: String
    var author: String
    var profile: VibeComposeSkillProfile
    var references: [String: String]
    var assets: [String: Data]
    var goldenCasesJSONL: String?

    static func template(
        _ template: SkillCreatorTemplateID
    ) -> SkillCreatorDraft {
        let risk = template.defaultRisk
        return SkillCreatorDraft(
            name: template.rawValue,
            description: "VibeCompose \(template.title) Skill",
            instructions: template.instructions,
            license: "MIT",
            version: "1.0.0",
            author: "Local Creator",
            profile: VibeComposeSkillProfile(
                contextRequest: ContextRequest(
                    required: [.voice],
                    optional: [.selection, .styleCapsule, .terminology]
                ),
                resourceBindings: SkillResourceBindings(),
                output: SkillOutputContract(
                    format: .markdown,
                    delivery: .previewThenPaste,
                    risk: risk
                ),
                validators: SkillValidatorPolicy(
                    requireClosedMarkdownFences: true
                ),
                risk: risk
            ),
            references: [:],
            assets: [:],
            goldenCasesJSONL: nil
        )
    }
}

struct SkillCreatorValidationReport:
    Sendable,
    Equatable
{
    let errors: [String]
    let warnings: [String]
    let inspectedPackage: AgentSkillPackage?
    let compatibility: SkillCompatibilityReport?

    var isValid: Bool { errors.isEmpty && inspectedPackage != nil }
}

struct SkillCreator:
    @unchecked Sendable
{
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func export(
        _ draft: SkillCreatorDraft,
        to destination: URL
    ) throws -> AgentSkillPackage {
        guard destination.isFileURL else {
            throw AgentSkillPackageError.unsafePath(destination.path)
        }
        if fileManager.fileExists(atPath: destination.path) {
            throw CommunitySkillPackageError.alreadyInstalled(destination.lastPathComponent)
        }
        try fileManager.createDirectory(
            at: destination,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        do {
            try write(draft, to: destination)
            let package = try AgentSkillPackageLoader(fileManager: fileManager).load(from: destination)
            _ = try AgentSkillNormalizer().normalize(package: package)
            return package
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    func validate(
        _ draft: SkillCreatorDraft
    ) -> SkillCreatorValidationReport {
        let temporary = fileManager.temporaryDirectory
            .appendingPathComponent("VibeCompose-SkillCreator-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
            try write(draft, to: temporary)
            let package = try AgentSkillPackageLoader(fileManager: fileManager).load(from: temporary)
            let normalized = try AgentSkillNormalizer().normalize(package: package)
            try? fileManager.removeItem(at: temporary)
            return SkillCreatorValidationReport(
                errors: normalized.compatibility.runtimeStatus == .compatible
                    ? [] : normalized.compatibility.issues,
                warnings: normalized.compatibility.ignoredVendorFeatures
                    + normalized.compatibility.quarantinedResources,
                inspectedPackage: package,
                compatibility: normalized.compatibility
            )
        } catch {
            try? fileManager.removeItem(at: temporary)
            return SkillCreatorValidationReport(
                errors: [error.localizedDescription],
                warnings: [],
                inspectedPackage: nil,
                compatibility: nil
            )
        }
    }

    func fork(
        package: AgentSkillPackage,
        name: String
    ) -> SkillCreatorDraft {
        var references: [String: String] = [:]
        for descriptor in package.resources where
            descriptor.runtimeVisibility == .runtime
                && (descriptor.kind == .reference || descriptor.kind == .template)
        {
            let url = package.rootURL.appendingPathComponent(descriptor.relativePath)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                references[descriptor.relativePath] = text
            }
        }
        let profileURL = package.rootURL.appendingPathComponent("vibecompose.yaml")
        let profile = (try? VibeComposeProfileLoader().load(
            from: fileManager.fileExists(atPath: profileURL.path) ? profileURL : nil
        )) ?? .safeDefault
        return SkillCreatorDraft(
            name: name,
            description: package.metadata.description,
            instructions: package.instructions,
            license: package.metadata.license,
            version: "1.0.0",
            author: "Local Creator",
            profile: profile,
            references: references,
            assets: [:],
            goldenCasesJSONL: nil
        )
    }

    private func write(
        _ draft: SkillCreatorDraft,
        to root: URL
    ) throws {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = draft.description
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard SkillDefinition.isValidVersion(draft.version) else {
            throw AgentSkillPackageError.invalidFrontmatter("version must use semantic versioning")
        }
        let frontmatter = [
            "---",
            "name: \(yamlScalar(name))",
            "description: \(yamlScalar(description))",
            draft.license.map { "license: \(yamlScalar($0))" },
            "metadata:",
            "  version: \(yamlScalar(draft.version))",
            "  author: \(yamlScalar(draft.author))",
            "---",
            "",
            draft.instructions.trimmingCharacters(in: .whitespacesAndNewlines),
            "",
        ].compactMap { $0 }.joined(separator: "\n")
        try secureWrite(Data(frontmatter.utf8), to: root.appendingPathComponent("SKILL.md"))
        try secureWrite(Data(profileYAML(draft.profile).utf8), to: root.appendingPathComponent("vibecompose.yaml"))

        for (relativePath, content) in draft.references.sorted(by: { $0.key < $1.key }) {
            let safe = try safeResourcePath(relativePath, root: "references")
            try secureWrite(Data(content.utf8), to: root.appendingPathComponent(safe))
        }
        for (relativePath, content) in draft.assets.sorted(by: { $0.key < $1.key }) {
            let safe = try safeResourcePath(relativePath, root: "assets")
            try secureWrite(content, to: root.appendingPathComponent(safe))
        }
        if let golden = draft.goldenCasesJSONL,
           !golden.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            try secureWrite(Data(golden.utf8), to: root.appendingPathComponent("tests/golden.jsonl"))
        }
    }

    private func safeResourcePath(_ path: String, root: String) throws -> String {
        let normalized = path.hasPrefix(root + "/") ? path : "\(root)/\(path)"
        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard normalized.count <= 500,
              components.first == Substring(root),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        else {
            throw AgentSkillPackageError.unsafePath(path)
        }
        return normalized
    }

    private func secureWrite(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        try data.write(to: url, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }

    private func yamlScalar(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func profileYAML(_ profile: VibeComposeSkillProfile) -> String {
        func list(_ values: [String]) -> String {
            "[" + values.map(yamlScalar).joined(separator: ", ") + "]"
        }
        return """
        context:
          required: \(list(profile.contextRequest.required.map(\.rawValue)))
          optional: \(list(profile.contextRequest.optional.map(\.rawValue)))
        resources:
          terminology: \(list(profile.resourceBindings.terminology))
          templates: \(list(profile.resourceBindings.templates))
          references: \(list(profile.resourceBindings.references))
          examples: \(list(profile.resourceBindings.examples))
          goldenTests: \(list(profile.resourceBindings.goldenTests))
        output:
          format: \(profile.output.format.rawValue)
          delivery: \(profile.output.delivery.rawValue)
          risk: \(profile.risk.rawValue)
        validators:
          requireNonEmpty: \(profile.validators.requireNonEmpty)
          maximumCharacters: \(profile.validators.maximumCharacters)
          preserveTechnicalLiterals: \(profile.validators.preserveTechnicalLiterals)
          requireClosedMarkdownFences: \(profile.validators.requireClosedMarkdownFences)
          requiredSections: \(list(profile.validators.requiredSectionAlternatives.compactMap(\.first)))
          forbiddenPhrases: \(list(profile.validators.forbiddenPhrases))
        """
    }
}

struct TrustedSkillRegistrySource:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    var id: UUID
    var name: String
    var indexURL: URL
    var publicKeyBase64: String
    var isEnabled: Bool
    var teamAllowlistedPublisherIDs: [String]

    init(
        id: UUID = UUID(),
        name: String,
        indexURL: URL,
        publicKeyBase64: String,
        isEnabled: Bool = false,
        teamAllowlistedPublisherIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.indexURL = indexURL
        self.publicKeyBase64 = publicKeyBase64
        self.isEnabled = isEnabled
        self.teamAllowlistedPublisherIDs = teamAllowlistedPublisherIDs
    }
}

struct TrustedSkillRegistryPackage:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    var id: String { packageID + "@" + version }
    let packageID: String
    let portableName: String
    let version: String
    let revision: String
    let publisherID: String
    let archiveURL: URL
    let archiveSHA256: String
    let contentSHA256: String
    let minimumAppVersion: String
    let isRevoked: Bool
    let replacesRevision: String?
}

struct TrustedSkillRegistryIndex:
    Codable,
    Sendable,
    Equatable
{
    let schemaVersion: Int
    let registryID: String
    let generatedAt: Date
    let keyID: String
    let packages: [TrustedSkillRegistryPackage]
    let collections: [SkillCollection]
    let revokedRevisions: [String]
}

enum TrustedSkillRegistryError:
    LocalizedError,
    Equatable
{
    case disabled
    case invalidKey
    case invalidSignature
    case invalidIndex
    case publisherNotAllowed(String)
    case revoked(String)
    case hashMismatch
    case packageNotFound(String)
    case responseTooLarge
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .disabled: "Remote Skill Registry is disabled."
        case .invalidKey: "The Registry public key is invalid."
        case .invalidSignature: "The Registry index signature is invalid."
        case .invalidIndex: "The Registry index is invalid."
        case .publisherNotAllowed(let publisher): "Publisher \(publisher) is not allowed by team policy."
        case .revoked(let revision): "Skill revision \(revision) has been revoked."
        case .hashMismatch: "The downloaded Skill archive hash does not match the signed index."
        case .packageNotFound(let packageID): "The Registry package \(packageID) was not found."
        case .responseTooLarge: "The Registry response exceeds VibeCompose's size limit."
        case .transport(let detail): "The Registry request failed: \(detail)"
        }
    }
}

struct TrustedSkillRegistryVerifier:
    Sendable
{
    func verify(
        indexData: Data,
        signature: Data,
        source: TrustedSkillRegistrySource
    ) throws -> TrustedSkillRegistryIndex {
        guard source.isEnabled else {
            throw TrustedSkillRegistryError.disabled
        }
        guard source.indexURL.scheme?.lowercased() == "https" else {
            throw TrustedSkillRegistryError.invalidIndex
        }
        guard let keyData = Data(base64Encoded: source.publicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else {
            throw TrustedSkillRegistryError.invalidKey
        }
        guard key.isValidSignature(signature, for: indexData) else {
            throw TrustedSkillRegistryError.invalidSignature
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let index = try? decoder.decode(TrustedSkillRegistryIndex.self, from: indexData),
              index.schemaVersion == 1,
              !index.registryID.isEmpty
        else {
            throw TrustedSkillRegistryError.invalidIndex
        }
        let revoked = Set(index.revokedRevisions)
        var identities = Set<String>()
        for package in index.packages {
            guard !package.packageID.isEmpty,
                  !package.portableName.isEmpty,
                  !package.publisherID.isEmpty,
                  !package.revision.isEmpty,
                  identities.insert(package.id).inserted,
                  SkillDefinition.isValidVersion(package.version),
                  SkillDefinition.isValidVersion(package.minimumAppVersion),
                  package.archiveURL.scheme?.lowercased() == "https",
                  Self.isSHA256(package.archiveSHA256),
                  Self.isSHA256(package.contentSHA256)
            else {
                throw TrustedSkillRegistryError.invalidIndex
            }
            if package.isRevoked || revoked.contains(package.revision) {
                continue
            }
            if !source.teamAllowlistedPublisherIDs.isEmpty,
               !source.teamAllowlistedPublisherIDs.contains(package.publisherID)
            {
                throw TrustedSkillRegistryError.publisherNotAllowed(package.publisherID)
            }
        }
        return index
    }

    func verifyArchive(
        _ data: Data,
        package: TrustedSkillRegistryPackage,
        index: TrustedSkillRegistryIndex
    ) throws {
        if package.isRevoked || index.revokedRevisions.contains(package.revision) {
            throw TrustedSkillRegistryError.revoked(package.revision)
        }
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest == package.archiveSHA256.lowercased() else {
            throw TrustedSkillRegistryError.hashMismatch
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9a-fA-F]{64}$"#,
            options: .regularExpression
        ) != nil
    }
}

/// Remote Registry access is opt-in and always passes through signature,
/// archive hash, archive preflight, standard package validation, compatibility
/// analysis, and the same private installation store as a local import.
struct TrustedSkillRegistryClient:
    @unchecked Sendable
{
    typealias Fetch = @Sendable (URL) async throws -> Data

    let fileManager: FileManager
    let cacheRootURL: URL
    let fetch: Fetch

    init(
        fileManager: FileManager = .default,
        applicationSupportURL: URL = ProductIdentity.applicationSupportURL(
            homeDirectoryURL: FileManager.default.homeDirectoryForCurrentUser
        ),
        fetch: @escaping Fetch = TrustedSkillRegistryClient.liveFetch
    ) {
        self.fileManager = fileManager
        cacheRootURL = applicationSupportURL
            .appendingPathComponent("Skills/RegistryCache", isDirectory: true)
        self.fetch = fetch
    }

    func loadIndex(
        source: TrustedSkillRegistrySource,
        remoteRegistryEnabled: Bool
    ) async throws -> TrustedSkillRegistryIndex {
        guard remoteRegistryEnabled, source.isEnabled else {
            throw TrustedSkillRegistryError.disabled
        }
        async let indexRequest = fetch(source.indexURL)
        async let signatureRequest = fetch(
            source.indexURL.appendingPathExtension("sig")
        )
        let (indexData, encodedSignature) = try await (
            indexRequest,
            signatureRequest
        )
        guard indexData.count <= 2 * 1_024 * 1_024,
              encodedSignature.count <= 4 * 1_024
        else {
            throw TrustedSkillRegistryError.responseTooLarge
        }
        let signature = encodedSignature.count == 64
            ? encodedSignature
            : Data(
                base64Encoded: encodedSignature
                    .trimmingASCIIWhitespace()
            ) ?? encodedSignature
        return try TrustedSkillRegistryVerifier().verify(
            indexData: indexData,
            signature: signature,
            source: source
        )
    }

    func install(
        packageID: String,
        version: String? = nil,
        source: TrustedSkillRegistrySource,
        remoteRegistryEnabled: Bool,
        store: SkillPackageStore
    ) async throws -> CommunitySkillPackage {
        let index = try await loadIndex(
            source: source,
            remoteRegistryEnabled: remoteRegistryEnabled
        )
        let candidates = index.packages.filter {
            $0.packageID == packageID
                && !$0.isRevoked
                && !index.revokedRevisions.contains($0.revision)
                && (version == nil || $0.version == version)
        }
        guard let package = candidates.sorted(by: {
            SemanticVersion.compare($0.version, $1.version)
                == .orderedDescending
        }).first else {
            throw TrustedSkillRegistryError.packageNotFound(packageID)
        }
        guard SemanticVersion.compare(
            ProductIdentity.runtimeVersion,
            package.minimumAppVersion
        ) != .orderedAscending else {
            throw CommunitySkillPackageError.incompatibleVersion(
                package.minimumAppVersion
            )
        }
        let archiveURL = try await cachedArchive(
            package: package,
            index: index
        )
        return try store.installRegistryPackage(
            from: archiveURL,
            source: source,
            package: package
        )
    }

    func cachedArchive(
        package: TrustedSkillRegistryPackage,
        index: TrustedSkillRegistryIndex
    ) async throws -> URL {
        let verifier = TrustedSkillRegistryVerifier()
        let digest = package.archiveSHA256.lowercased()
        let directory = cacheRootURL
            .appendingPathComponent(digest, isDirectory: true)
        let archiveURL = directory.appendingPathComponent("package.zip")
        if let values = try? archiveURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ), values.isRegularFile == true, values.isSymbolicLink != true,
           let existing = try? Data(
               contentsOf: archiveURL,
               options: [.mappedIfSafe]
           ), (try? verifier.verifyArchive(
               existing,
               package: package,
               index: index
           )) != nil {
                return archiveURL
        }
        try? fileManager.removeItem(at: directory)

        let data = try await fetch(package.archiveURL)
        guard data.count <= 8 * 1_024 * 1_024 else {
            throw TrustedSkillRegistryError.responseTooLarge
        }
        try verifier.verifyArchive(
            data,
            package: package,
            index: index
        )
        try secureDirectory(directory)
        let temporary = directory.appendingPathComponent(".download")
        try data.write(to: temporary, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: temporary.path
        )
        try fileManager.moveItem(at: temporary, to: archiveURL)
        return archiveURL
    }

    private func secureDirectory(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            let values = try url.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard values.isDirectory == true,
                  values.isSymbolicLink != true
            else {
                throw AgentSkillPackageError.unsafePath(url.path)
            }
        } else {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
            )
        }
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: url.path
        )
    }

    private static func liveFetch(_ url: URL) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let response = response as? HTTPURLResponse,
               !(200...299).contains(response.statusCode)
            {
                throw TrustedSkillRegistryError.transport(
                    "HTTP \(response.statusCode)"
                )
            }
            return data
        } catch let error as TrustedSkillRegistryError {
            throw error
        } catch {
            throw TrustedSkillRegistryError.transport(
                error.localizedDescription
            )
        }
    }
}

private extension Data {
    func trimmingASCIIWhitespace() -> Data {
        let whitespace: Set<UInt8> = [0x09, 0x0A, 0x0D, 0x20]
        var lower = startIndex
        var upper = endIndex
        while lower < upper, whitespace.contains(self[lower]) {
            lower = index(after: lower)
        }
        while upper > lower {
            let previous = index(before: upper)
            guard whitespace.contains(self[previous]) else { break }
            upper = previous
        }
        return Data(self[lower..<upper])
    }
}
