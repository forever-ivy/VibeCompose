import Foundation

struct StyleCapsule:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    let id: String
    var name: String
    var summary: String
    var examples: [String]
    var createdAt: String
    var updatedAt: String
    var isBuiltIn: Bool

    init(
        id: String,
        name: String,
        summary: String,
        examples: [String] = [],
        createdAt: String =
            ISO8601DateFormatter()
                .string(from: Date()),
        updatedAt: String =
            ISO8601DateFormatter()
                .string(from: Date()),
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = String(
            name.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).prefix(80)
        )
        self.summary = String(
            summary.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).prefix(4_000)
        )
        self.examples = examples
            .map {
                String(
                    $0.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).prefix(1_000)
                )
            }
            .filter { !$0.isEmpty }
            .prefix(10)
            .map { $0 }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isBuiltIn = isBuiltIn
    }

    var promptText: String {
        var sections = [summary]
        if !examples.isEmpty {
            sections.append(
                "User-approved examples:\n"
                    + examples.map {
                        "- \($0)"
                    }.joined(
                        separator: "\n"
                    )
            )
        }
        return sections.joined(
            separator: "\n"
        )
    }

    static func isValidIdentifier(
        _ value: String
    ) -> Bool {
        value.range(
            of:
                #"^(?:builtin|user)\.[a-z0-9][a-z0-9.-]{2,100}$"#,
            options:
                .regularExpression
        ) != nil
    }
}

enum StyleCapsuleRegistry {
    static let workFormalID =
        "builtin.work-formal"
    static let teamChatID =
        "builtin.team-chat"
    static let technicalWritingID =
        "builtin.technical-writing"
    static let englishBusinessID =
        "builtin.english-business"
    static let personalCasualID =
        "builtin.personal-casual"

    static let builtIn: [StyleCapsule] = [
        StyleCapsule(
            id: workFormalID,
            name: "Work Formal",
            summary:
                "Use a professional, calm tone. Prefer complete sentences, explicit requests, restrained politeness, and concise paragraphs. Avoid hype, slang, emojis, and unnecessary preambles.",
            isBuiltIn: true
        ),
        StyleCapsule(
            id: teamChatID,
            name: "Team Chat",
            summary:
                "Use a concise, direct, collaborative team-chat tone. Lead with the decision or request, keep paragraphs short, and use bullets only when they improve scanability. Avoid formal greetings and signatures.",
            isBuiltIn: true
        ),
        StyleCapsule(
            id: technicalWritingID,
            name: "Technical Writing",
            summary:
                "Use precise technical language, explicit constraints, compact headings, and implementation-oriented bullets. Preserve identifiers and avoid marketing language, vague adjectives, and unsupported claims.",
            isBuiltIn: true
        ),
        StyleCapsule(
            id: englishBusinessID,
            name: "English Business",
            summary:
                "Write clear international business English with short paragraphs, neutral confidence, explicit next steps, and moderate politeness. Avoid idioms, exaggerated claims, and culture-specific slang.",
            isBuiltIn: true
        ),
        StyleCapsule(
            id: personalCasualID,
            name: "Personal Casual",
            summary:
                "Use a warm, natural, conversational tone with varied sentence length. Keep the message compact, avoid corporate phrasing, and do not add emojis or sign-offs unless requested.",
            isBuiltIn: true
        ),
    ]

    static func all(
        custom: [StyleCapsule]
    ) -> [StyleCapsule] {
        builtIn + custom.filter {
            !$0.isBuiltIn
        }
    }
}

struct StyleCapsuleAssignment:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    var skillID: String
    var capsuleID: String

    var id: String {
        skillID
    }
}

struct StyleCapsuleConfig:
    Codable,
    Sendable,
    Equatable
{
    static let maximumAssignmentCount =
        100

    var enabled = true
    var defaultCapsuleID: String?
    var skillAssignments:
        [StyleCapsuleAssignment] = []

    init() {}

    init(
        enabled: Bool = true,
        defaultCapsuleID: String? = nil,
        skillAssignments:
            [StyleCapsuleAssignment] = []
    ) {
        self.enabled = enabled
        self.defaultCapsuleID =
            Self.normalizedCapsuleID(
                defaultCapsuleID
            )
        self.skillAssignments =
            Self.normalizedAssignments(
                skillAssignments
            )
    }

    init(from decoder: any Decoder)
        throws
    {
        let container =
            try decoder.container(
                keyedBy: CodingKeys.self
            )
        enabled =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .enabled
            ) ?? true
        defaultCapsuleID =
            Self.normalizedCapsuleID(
                try container.decodeIfPresent(
                    String.self,
                    forKey:
                        .defaultCapsuleID
                )
            )
        skillAssignments =
            Self.normalizedAssignments(
                try container.decodeIfPresent(
                    [StyleCapsuleAssignment].self,
                    forKey:
                        .skillAssignments
                ) ?? []
            )
    }

    func capsuleID(
        for skillID: String
    ) -> String? {
        skillAssignments.first {
            $0.skillID == skillID
        }?.capsuleID
            ?? defaultCapsuleID
    }

    func assignedCapsuleID(
        for skillID: String
    ) -> String? {
        skillAssignments.first {
            $0.skillID == skillID
        }?.capsuleID
    }

    mutating func setCapsuleID(
        _ capsuleID: String?,
        for skillID: String
    ) {
        skillAssignments.removeAll {
            $0.skillID == skillID
        }
        if
            let capsuleID =
                Self.normalizedCapsuleID(
                    capsuleID
                ),
            SkillDefinition
                .isValidIdentifier(
                    skillID
                )
        {
            skillAssignments.append(
                StyleCapsuleAssignment(
                    skillID: skillID,
                    capsuleID: capsuleID
                )
            )
        }
        skillAssignments =
            Self.normalizedAssignments(
                skillAssignments
            )
    }

    private static func normalizedCapsuleID(
        _ value: String?
    ) -> String? {
        guard let value else {
            return nil
        }
        let normalized =
            value.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).lowercased()
        return StyleCapsule
            .isValidIdentifier(normalized)
            ? normalized
            : nil
    }

    private static func normalizedAssignments(
        _ values:
            [StyleCapsuleAssignment]
    ) -> [StyleCapsuleAssignment] {
        var seen = Set<String>()
        return values.compactMap {
            assignment in
            guard
                SkillDefinition
                    .isValidIdentifier(
                        assignment.skillID
                    ),
                let capsuleID =
                    normalizedCapsuleID(
                        assignment
                            .capsuleID
                    ),
                seen.insert(
                    assignment.skillID
                ).inserted
            else {
                return nil
            }
            return StyleCapsuleAssignment(
                skillID:
                    assignment.skillID,
                capsuleID: capsuleID
            )
        }
        .prefix(maximumAssignmentCount)
        .map { $0 }
    }
}

enum StyleCapsuleError:
    LocalizedError,
    Equatable
{
    case invalidIdentifier
    case invalidContent
    case builtInReadOnly
    case symbolicLink
    case oversized
    case missing

    var errorDescription: String? {
        switch self {
        case .invalidIdentifier:
            return L10n.text(
                "The Style Capsule identifier is invalid."
            )
        case .invalidContent:
            return L10n.text(
                "Enter a name and a readable style summary."
            )
        case .builtInReadOnly:
            return L10n.text(
                "Built-in Style Capsules cannot be changed or deleted."
            )
        case .symbolicLink:
            return L10n.text(
                "OpenWhisper blocked a symbolic link in Style Capsule storage."
            )
        case .oversized:
            return L10n.text(
                "The Style Capsule is too large."
            )
        case .missing:
            return L10n.text(
                "The Style Capsule no longer exists."
            )
        }
    }
}

struct StyleCapsuleStore:
    @unchecked Sendable
{
    static let maximumCustomCapsules = 100
    static let maximumFileBytes =
        64 * 1_024

    let fileManager: FileManager
    let rootURL: URL

    init(
        fileManager: FileManager = .default,
        applicationSupportURL: URL =
            ProductIdentity
                .applicationSupportURL(
                    homeDirectoryURL:
                        FileManager.default
                            .homeDirectoryForCurrentUser
                )
    ) {
        self.fileManager = fileManager
        rootURL =
            applicationSupportURL
                .appendingPathComponent(
                    "StyleCapsules",
                    isDirectory: true
                )
    }

    func loadCustom()
        throws -> [StyleCapsule]
    {
        try prepareRoot()
        let urls =
            try fileManager
                .contentsOfDirectory(
                    at: rootURL,
                    includingPropertiesForKeys: [
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                        .fileSizeKey,
                    ],
                    options: [
                        .skipsHiddenFiles,
                    ]
                )
                .filter {
                    $0.pathExtension
                        .lowercased()
                        == "json"
                }
                .sorted {
                    $0.lastPathComponent
                        < $1.lastPathComponent
                }
                .prefix(
                    Self
                        .maximumCustomCapsules
                )

        return try urls.compactMap { url in
            let values =
                try url.resourceValues(
                    forKeys: [
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                        .fileSizeKey,
                    ]
                )
            guard values.isSymbolicLink
                != true
            else {
                throw StyleCapsuleError
                    .symbolicLink
            }
            guard values.isRegularFile
                == true
            else {
                return nil
            }
            guard
                (values.fileSize ?? 0)
                    <= Self
                        .maximumFileBytes
            else {
                throw StyleCapsuleError
                    .oversized
            }
            let capsule =
                try JSONDecoder()
                    .decode(
                        StyleCapsule.self,
                        from:
                            Data(
                                contentsOf:
                                    url
                            )
                    )
            guard
                StyleCapsule
                    .isValidIdentifier(
                        capsule.id
                    ),
                capsule.id.hasPrefix(
                    "user."
                ),
                !capsule.name.isEmpty,
                !capsule.summary.isEmpty,
                !capsule.isBuiltIn
            else {
                return nil
            }
            return capsule
        }
    }

    func loadAll()
        throws -> [StyleCapsule]
    {
        StyleCapsuleRegistry.all(
            custom: try loadCustom()
        )
    }

    func save(
        _ capsule: StyleCapsule
    ) throws {
        guard
            StyleCapsule
                .isValidIdentifier(
                    capsule.id
                ),
            capsule.id.hasPrefix(
                "user."
            )
        else {
            throw StyleCapsuleError
                .invalidIdentifier
        }
        guard
            !capsule.name
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty,
            !capsule.summary
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty,
            !capsule.isBuiltIn
        else {
            throw StyleCapsuleError
                .invalidContent
        }
        try prepareRoot()
        let existing =
            try loadCustom()
        guard
            existing.contains(
                where: {
                    $0.id == capsule.id
                }
            )
                || existing.count
                    < Self
                        .maximumCustomCapsules
        else {
            throw StyleCapsuleError
                .oversized
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
        ]
        let data =
            try encoder.encode(capsule)
        guard data.count
            <= Self.maximumFileBytes
        else {
            throw StyleCapsuleError
                .oversized
        }
        let url = fileURL(
            for: capsule.id
        )
        try data.write(
            to: url,
            options: [.atomic]
        )
        try fileManager.setAttributes(
            [
                .posixPermissions:
                    NSNumber(
                        value:
                            Int16(0o600)
                    ),
            ],
            ofItemAtPath: url.path
        )
    }

    func delete(id: String) throws {
        guard id.hasPrefix("user.")
        else {
            throw StyleCapsuleError
                .builtInReadOnly
        }
        try prepareRoot()
        let url = fileURL(for: id)
        guard
            fileManager.fileExists(
                atPath: url.path
            )
        else {
            throw StyleCapsuleError
                .missing
        }
        let values =
            try url.resourceValues(
                forKeys: [
                    .isSymbolicLinkKey,
                ]
            )
        guard values.isSymbolicLink
            != true
        else {
            throw StyleCapsuleError
                .symbolicLink
        }
        try fileManager.removeItem(
            at: url
        )
    }

    func export(
        _ capsule: StyleCapsule,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
        ]
        try encoder.encode(capsule)
            .write(
                to: url,
                options: [.atomic]
            )
    }

    private func prepareRoot() throws {
        if fileManager.fileExists(
            atPath: rootURL.path
        ) {
            let values =
                try rootURL
                    .resourceValues(
                        forKeys: [
                            .isSymbolicLinkKey,
                        ]
                    )
            guard values.isSymbolicLink
                != true
            else {
                throw StyleCapsuleError
                    .symbolicLink
            }
        }
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories:
                true
        )
        try fileManager.setAttributes(
            [
                .posixPermissions:
                    NSNumber(
                        value:
                            Int16(0o700)
                    ),
            ],
            ofItemAtPath:
                rootURL.path
        )
    }

    private func fileURL(
        for id: String
    ) -> URL {
        rootURL.appendingPathComponent(
            id + ".json",
            isDirectory: false
        )
    }
}

enum StyleCapsuleAnalyzer {
    static func summarize(
        samples: String
    ) -> String {
        let normalized =
            samples.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard !normalized.isEmpty else {
            return ""
        }
        let sentences =
            normalized.split(
                whereSeparator: {
                    ".!?。！？\n"
                        .contains($0)
                }
            )
        let averageWords: Int = {
            guard !sentences.isEmpty else {
                return 0
            }
            let total =
                sentences.reduce(0) {
                    partial,
                    sentence in
                    partial
                        + sentence.split(
                            whereSeparator:
                                \.isWhitespace
                        ).count
                }
            return max(
                1,
                total
                    / sentences.count
            )
        }()
        let usesBullets =
            normalized.contains("\n- ")
                || normalized
                    .contains("\n• ")
        let containsChinese =
            normalized.range(
                of: #"\p{Han}"#,
                options:
                    .regularExpression
            ) != nil
        let containsEnglish =
            normalized.range(
                of: #"[A-Za-z]"#,
                options:
                    .regularExpression
            ) != nil
        let language: String
        switch (
            containsChinese,
            containsEnglish
        ) {
        case (true, true):
            language =
                "mixed Chinese and English"
        case (true, false):
            language =
                "predominantly Chinese"
        default:
            language =
                "predominantly English"
        }
        let sentenceStyle =
            averageWords <= 12
                ? "short, compact sentences"
                : "moderate-length sentences"
        let structure =
            usesBullets
                ? "Use bullets when organizing multiple points."
                : "Prefer short paragraphs over unnecessary bullets."
        return """
        Write in \(language) with \(sentenceStyle). \(structure)
        Preserve the speaker's directness and technical density. Avoid adding greetings, sign-offs, emojis, hype, unsupported claims, or facts that are not present.
        """
    }
}

struct StyleCapsuleResolver:
    Sendable
{
    func resolve(
        config:
            StyleCapsuleConfig,
        available:
            [StyleCapsule],
        skill:
            SkillDefinition
    ) -> StyleCapsule? {
        guard
            config.enabled,
            skill.allCapabilities
                .contains(
                    .styleCapsule
                ),
            let id =
                config.capsuleID(
                    for: skill.id
                )
        else {
            return nil
        }
        return available.first {
            $0.id == id
        }
    }
}

struct TerminologyPackDefinition:
    Sendable,
    Equatable,
    Identifiable
{
    let id: String
    let version: String
    let name: String
    let category: String
    let risk: SkillRiskLevel
    let entries: [TerminologyEntry]

    var localizedName: String {
        L10n.text(name)
    }
}

enum TerminologyPackRegistry {
    static let backendID =
        "app.openwhisper.terms.backend"
    static let medicalID =
        "app.openwhisper.terms.medical"
    static let kubernetesID =
        "app.openwhisper.terms.kubernetes"

    static let builtIn: [TerminologyPackDefinition] = [
        make(
            id: backendID,
            name: "Backend Engineering",
            category: "Engineering",
            risk: .low,
            terms: [
                ("FastAPI", ["fast api"]),
                ("PostgreSQL", ["postgres", "post gre sql"]),
                ("Redis", ["red is"]),
                ("OpenAPI", ["open api"]),
                ("gRPC", ["g r p c"]),
                ("idempotency", ["idempotence"]),
            ]
        ),
        make(
            id: medicalID,
            name: "Medical Terminology",
            category: "Medical",
            risk: .high,
            terms: [
                ("HbA1c", ["h b a one c"]),
                ("metformin", ["met formin"]),
                ("hypertension", []),
                ("electrocardiogram", ["ECG", "EKG"]),
                ("milligrams", ["mg"]),
                ("contraindication", []),
            ]
        ),
        make(
            id: kubernetesID,
            name: "Kubernetes",
            category: "Engineering",
            risk: .medium,
            terms: [
                ("Kubernetes", ["k8s", "cube er netties"]),
                ("kubectl", ["cube control"]),
                ("kubeconfig", ["cube config"]),
                ("StatefulSet", ["stateful set"]),
                ("ConfigMap", ["config map"]),
                ("HorizontalPodAutoscaler", ["HPA"]),
            ]
        ),
    ]

    static func definition(
        id: String
    ) -> TerminologyPackDefinition? {
        builtIn.first { $0.id == id }
    }

    private static func make(
        id: String,
        name: String,
        category: String,
        risk: SkillRiskLevel,
        terms:
            [(String, [String])]
    ) -> TerminologyPackDefinition {
        TerminologyPackDefinition(
            id: id,
            version: "1.0.0",
            name: name,
            category: category,
            risk: risk,
            entries:
                terms.map {
                    canonical,
                    aliases in
                    TerminologyEntry(
                        id:
                            StableIdentifier
                                .uuid(
                                    namespace:
                                        "OpenWhisper.TerminologyPack",
                                    components: [
                                        id,
                                        canonical,
                                    ]
                                ),
                        type: .term,
                        original:
                            canonical,
                        replacement: nil,
                        aliases: aliases,
                        isEnabled: true,
                        source:
                            "domain-pack:\(id)",
                        usageCount: 0,
                        createdAt:
                            "2026-07-14T00:00:00Z"
                    )
                }
        )
    }
}

struct TerminologyPackConfig:
    Codable,
    Sendable,
    Equatable
{
    var enabledPackIDs:
        [String] = []

    init() {}

    init(
        enabledPackIDs: [String]
    ) {
        self.enabledPackIDs =
            Self.normalized(
                enabledPackIDs
            )
    }

    init(from decoder: any Decoder)
        throws
    {
        let container =
            try decoder.container(
                keyedBy: CodingKeys.self
            )
        enabledPackIDs =
            Self.normalized(
                try container.decodeIfPresent(
                    [String].self,
                    forKey:
                        .enabledPackIDs
                ) ?? []
            )
    }

    mutating func setEnabled(
        _ isEnabled: Bool,
        packID: String
    ) {
        enabledPackIDs.removeAll {
            $0 == packID
        }
        if
            isEnabled,
            TerminologyPackRegistry
                .definition(id: packID)
                != nil
        {
            enabledPackIDs.append(
                packID
            )
        }
        enabledPackIDs =
            Self.normalized(
                enabledPackIDs
            )
    }

    func isEnabled(
        _ packID: String
    ) -> Bool {
        enabledPackIDs.contains(
            packID
        )
    }

    private static func normalized(
        _ values: [String]
    ) -> [String] {
        var seen = Set<String>()
        return values.filter {
            TerminologyPackRegistry
                .definition(id: $0)
                != nil
                && seen.insert($0)
                    .inserted
        }
    }
}

struct TerminologyPackConflict:
    Sendable,
    Equatable,
    Identifiable
{
    let packID: String
    let personalEntryID: UUID
    let term: String

    var id: String {
        "\(packID)|\(personalEntryID.uuidString)|\(term)"
    }
}

struct ResolvedTerminologyAssets:
    Sendable,
    Equatable
{
    let entries: [TerminologyEntry]
    let enabledPackIDs: [String]
    let maximumRisk:
        SkillRiskLevel
    let conflicts:
        [TerminologyPackConflict]
}

struct TerminologyPackResolver:
    Sendable
{
    func resolve(
        personalEntries:
            [TerminologyEntry],
        config:
            TerminologyPackConfig,
        skill:
            SkillDefinition
    ) -> ResolvedTerminologyAssets {
        var personalKeys:
            [String: TerminologyEntry] = [:]
        for entry in personalEntries {
            let key = identityKey(entry)
            if personalKeys[key] == nil {
                personalKeys[key] = entry
            }
        }
        let personalCorrections =
            personalEntries.filter {
                $0.type == .correction
            }
        let personalTerms =
            personalEntries.filter {
                $0.type == .term
            }
        let skillEntries =
            skill.terminologyEntries
                .map { entry in
                    var entry = entry
                    entry.source =
                        "skill:\(skill.id)"
                    return entry
                }
        var domainEntries:
            [TerminologyEntry] = []
        var conflicts:
            [TerminologyPackConflict] = []
        var enabledIDs:
            [String] = []
        var risk:
            SkillRiskLevel = .low

        for packID in
            config.enabledPackIDs
        {
            guard
                let pack =
                    TerminologyPackRegistry
                        .definition(
                            id: packID
                        )
            else {
                continue
            }
            enabledIDs.append(packID)
            risk = maximumRisk(
                risk,
                pack.risk
            )
            for entry in pack.entries {
                if
                    let personal =
                        personalKeys[
                            identityKey(
                                entry
                            )
                        ]
                {
                    conflicts.append(
                        TerminologyPackConflict(
                            packID:
                                packID,
                            personalEntryID:
                                personal.id,
                            term:
                                entry
                                    .canonical
                        )
                    )
                    continue
                }
                domainEntries.append(entry)
            }
        }

        let merged =
            personalCorrections
            + skillEntries
            + personalTerms
            + domainEntries

        return ResolvedTerminologyAssets(
            entries: merged,
            enabledPackIDs:
                enabledIDs,
            maximumRisk: risk,
            conflicts: conflicts
        )
    }

    func conflicts(
        personalEntries:
            [TerminologyEntry],
        pack:
            TerminologyPackDefinition
    ) -> [TerminologyPackConflict] {
        resolve(
            personalEntries:
                personalEntries,
            config:
                TerminologyPackConfig(
                    enabledPackIDs: [
                        pack.id,
                    ]
                ),
            skill:
                SkillRegistry.builtIn
                    .definition(
                        id:
                            SkillRegistry
                                .directSkillID
                    )!
        ).conflicts
    }

    private func identityKey(
        _ entry: TerminologyEntry
    ) -> String {
        "\(entry.type.rawValue)|"
            + entry.original
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .folding(
                    options: [
                        .caseInsensitive,
                        .diacriticInsensitive,
                    ],
                    locale: .current
                )
    }

    private func maximumRisk(
        _ lhs: SkillRiskLevel,
        _ rhs: SkillRiskLevel
    ) -> SkillRiskLevel {
        let rank: [SkillRiskLevel: Int] = [
            .low: 0,
            .medium: 1,
            .high: 2,
        ]
        return (rank[lhs] ?? 0)
            >= (rank[rhs] ?? 0)
            ? lhs
            : rhs
    }
}
