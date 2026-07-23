import CryptoKit
import Foundation

enum SkillPackageFormat:
    String,
    Codable,
    Sendable,
    Equatable
{
    case builtIn
    case agentSkillsStandard
    case legacyVibeWhisperV1
}

enum SkillResourceKind:
    String,
    Codable,
    Sendable,
    Equatable
{
    case instructions
    case profile
    case reference
    case asset
    case template
    case terminology
    case examples
    case goldenTests
    case vendorExtension
    case executable
    case unsupported
}

enum SkillResourceVisibility:
    String,
    Codable,
    Sendable,
    Equatable
{
    case runtime
    case metadataOnly
    case quarantined
}

struct SkillResourceDescriptor:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    let relativePath: String
    let kind: SkillResourceKind
    let byteCount: Int
    let contentSHA256: String
    let runtimeVisibility: SkillResourceVisibility

    var id: String { relativePath }
}

struct ResolvedSkillResource:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    let descriptor: SkillResourceDescriptor
    let content: String

    var id: String { descriptor.relativePath }
}

struct AgentSkillMetadata:
    Codable,
    Sendable,
    Equatable
{
    let name: String
    let description: String
    let license: String?
    let compatibility: String?
    let metadata: [String: String]
    let allowedTools: String?
}

struct AgentSkillPackage:
    Codable,
    Sendable,
    Equatable
{
    let rootURL: URL
    let metadata: AgentSkillMetadata
    let instructions: String
    let resources: [SkillResourceDescriptor]
    let vendorExtensions: [String: String]
    let contentSHA256: String
}

struct SkillResourceBindings:
    Codable,
    Sendable,
    Equatable
{
    var terminology: [String] = []
    var templates: [String] = []
    var references: [String] = []
    var examples: [String] = []
    var goldenTests: [String] = []
}

struct VibeWhisperSkillProfile:
    Codable,
    Sendable,
    Equatable
{
    var contextRequest: ContextRequest
    var resourceBindings: SkillResourceBindings
    var output: SkillOutputContract
    var validators: SkillValidatorPolicy
    var risk: SkillRiskLevel

    static let safeDefault = VibeWhisperSkillProfile(
        contextRequest: ContextRequest(),
        resourceBindings: SkillResourceBindings(),
        output: SkillOutputContract(
            format: .plainText,
            delivery: .previewThenPaste,
            risk: .medium
        ),
        validators: SkillValidatorPolicy(),
        risk: .medium
    )
}

struct InstalledSkillIdentity:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    let id: UUID
    let portableName: String
    let sourceID: String
    let packageID: String?
    let version: String?
    let revision: String
    let publisher: String?

    static func normalized(
        definition: SkillDefinition,
        sourceID: String,
        revision: String? = nil,
        portableName: String? = nil,
        packageID: String? = nil,
        publisher: String? = nil
    ) -> InstalledSkillIdentity {
        let resolvedRevision = revision ?? definition.version
        // A bundled Skill is one logical installation across app updates.
        // Keep the original v1 identity seed so favorites, app defaults, and
        // next-run references survive a semantic-version upgrade; `version`
        // and `revision` still freeze the exact declaration used by a run.
        let identityRevision =
            sourceID == "builtin"
            ? "1.0.0"
            : resolvedRevision
        return InstalledSkillIdentity(
            id: StableIdentifier.uuid(
                namespace: "VibeWhisper.InstalledSkillIdentity",
                components: [
                    sourceID,
                    packageID,
                    definition.id,
                    identityRevision,
                ]
            ),
            portableName: portableName ?? definition.name,
            sourceID: sourceID,
            packageID: packageID,
            version: definition.version,
            revision: resolvedRevision,
            publisher: publisher ?? definition.author
        )
    }
}

enum StandardFormatStatus:
    String,
    Codable,
    Sendable,
    Equatable
{
    case valid
    case invalid
}

enum VibeWhisperRuntimeStatus:
    String,
    Codable,
    Sendable,
    Equatable
{
    case compatible
    case incompatible
    case disabled
}

enum SkillCompatibilityLevel:
    String,
    Codable,
    Sendable,
    Equatable
{
    case portable
    case openWhisperEnhanced
    case vendorExtended
    case toolDependent
    case executableDependent
}

struct SkillCompatibilityReport:
    Codable,
    Sendable,
    Equatable
{
    let standardFormatStatus: StandardFormatStatus
    let runtimeStatus: VibeWhisperRuntimeStatus
    let level: SkillCompatibilityLevel
    let issues: [String]
    let ignoredVendorFeatures: [String]
    let quarantinedResources: [String]
}

enum AgentSkillPackageError:
    LocalizedError,
    Equatable
{
    case missingSkillMarkdown
    case invalidFrontmatter(String)
    case invalidProfile(String)
    case unsafePath(String)
    case symbolicLink(String)
    case unreadableText(String)
    case tooManyFiles
    case fileTooLarge(String)
    case packageTooLarge
    case incompatible(String)

    var errorDescription: String? {
        switch self {
        case .missingSkillMarkdown:
            return L10n.text("The standard Skill directory is missing SKILL.md.")
        case .invalidFrontmatter(let detail):
            return L10n.format("SKILL.md frontmatter is invalid: %@", detail)
        case .invalidProfile(let detail):
            return L10n.format("vibewhisper.yaml is invalid: %@", detail)
        case .unsafePath(let path):
            return L10n.format("The Skill contains an unsafe path: %@", path)
        case .symbolicLink(let path):
            return L10n.format("The Skill contains a symbolic link: %@", path)
        case .unreadableText(let path):
            return L10n.format("The Skill resource is not readable UTF-8 text: %@", path)
        case .tooManyFiles:
            return L10n.text("The Skill contains too many files.")
        case .fileTooLarge(let path):
            return L10n.format("A Skill resource is too large: %@", path)
        case .packageTooLarge:
            return L10n.text("The Skill directory is too large.")
        case .incompatible(let detail):
            return L10n.format("The Skill is not compatible with VibeWhisper: %@", detail)
        }
    }
}

private struct RestrictedYAMLDocument {
    var scalars: [String: String]
    var lists: [String: [String]]

    func scalar(_ key: String) -> String? { scalars[key] }
    func list(_ key: String) -> [String] { lists[key] ?? [] }
    var paths: Set<String> {
        Set(scalars.keys).union(lists.keys)
    }

    static func parse(
        _ text: String,
        allowedRoots: Set<String>,
        preserveUnknownRoots: Bool
    ) throws -> RestrictedYAMLDocument {
        guard text.utf8.count <= 96 * 1_024,
              !text.contains("\t"),
              !text.contains("!!"),
              !text.contains("!<")
        else {
            throw AgentSkillPackageError.invalidFrontmatter(
                "tabs, YAML tags, and oversized documents are not supported"
            )
        }

        let lines = text.components(separatedBy: .newlines)
        guard lines.count <= 1_500 else {
            throw AgentSkillPackageError.invalidFrontmatter("too many YAML lines")
        }

        var scalars: [String: String] = [:]
        var lists: [String: [String]] = [:]
        var root: String?
        var listPath: String?
        var blockPath: String?
        var blockIndent = 0
        var blockFolded = false
        var blockLines: [String] = []

        func clean(_ value: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else { return trimmed }
            if trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
                if let data = trimmed.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(String.self, from: data)
                {
                    return decoded
                }
                return String(trimmed.dropFirst().dropLast())
            }
            if trimmed.hasPrefix("'"), trimmed.hasSuffix("'") {
                return String(trimmed.dropFirst().dropLast())
                    .replacingOccurrences(of: "''", with: "'")
            }
            return trimmed
        }

        func inlineList(_ value: Substring) throws -> [String] {
            var values: [String] = []
            var current = ""
            var quote: Character?
            var escaped = false
            for character in value {
                if escaped {
                    current.append(character)
                    escaped = false
                    continue
                }
                if character == "\\", quote == "\"" {
                    current.append(character)
                    escaped = true
                    continue
                }
                if character == "\"" || character == "'" {
                    if quote == nil {
                        quote = character
                    } else if quote == character {
                        quote = nil
                    }
                    current.append(character)
                    continue
                }
                if character == ",", quote == nil {
                    values.append(clean(current))
                    current = ""
                } else {
                    current.append(character)
                }
            }
            guard quote == nil, !escaped else {
                throw AgentSkillPackageError.invalidFrontmatter(
                    "unterminated quoted list value"
                )
            }
            if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                values.append(clean(current))
            }
            return values
        }

        func flushBlock() throws {
            guard let blockPath else { return }
            let value = blockFolded
                ? blockLines.joined(separator: " ")
                : blockLines.joined(separator: "\n")
            guard scalars[blockPath] == nil, lists[blockPath] == nil else {
                throw AgentSkillPackageError.invalidFrontmatter(
                    "duplicate key \(blockPath)"
                )
            }
            scalars[blockPath] = String(value.prefix(16_000))
        }

        for (index, rawLine) in lines.enumerated() {
            let indent = rawLine.prefix { $0 == " " }.count
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if blockPath != nil {
                if trimmed.isEmpty {
                    blockLines.append("")
                    continue
                }
                if indent >= blockIndent {
                    blockLines.append(
                        String(rawLine.dropFirst(min(blockIndent, rawLine.count)))
                    )
                    continue
                }
                try flushBlock()
                blockPath = nil
                blockLines = []
            }

            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard indent == 0 || indent == 2 else {
                throw AgentSkillPackageError.invalidFrontmatter(
                    "invalid indentation on line \(index + 1)"
                )
            }
            if trimmed.hasPrefix("- ") {
                guard let listPath, indent == 2 else {
                    throw AgentSkillPackageError.invalidFrontmatter(
                        "unexpected list on line \(index + 1)"
                    )
                }
                lists[listPath, default: []].append(
                    clean(String(trimmed.dropFirst(2)))
                )
                continue
            }
            guard let separator = trimmed.firstIndex(of: ":") else {
                throw AgentSkillPackageError.invalidFrontmatter(
                    "missing ':' on line \(index + 1)"
                )
            }
            let key = String(trimmed[..<separator])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.range(
                of: #"^[A-Za-z][A-Za-z0-9_.-]*$"#,
                options: .regularExpression
            ) != nil else {
                throw AgentSkillPackageError.invalidFrontmatter(
                    "invalid key on line \(index + 1)"
                )
            }
            let value = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.hasPrefix("&"),
                  !value.hasPrefix("*"),
                  !value.hasPrefix("!")
            else {
                throw AgentSkillPackageError.invalidFrontmatter(
                    "YAML anchors, aliases, and tags are not supported"
                )
            }

            let path: String
            if indent == 0 {
                guard allowedRoots.contains(key) || preserveUnknownRoots else {
                    throw AgentSkillPackageError.invalidFrontmatter(
                        "unknown key \(key)"
                    )
                }
                root = value.isEmpty ? key : nil
                path = key
            } else {
                guard let root else {
                    throw AgentSkillPackageError.invalidFrontmatter(
                        "orphan key on line \(index + 1)"
                    )
                }
                path = "\(root).\(key)"
            }
            guard scalars[path] == nil, lists[path] == nil else {
                throw AgentSkillPackageError.invalidFrontmatter("duplicate key \(path)")
            }
            if value == "|" || value == ">" {
                blockPath = path
                blockIndent = indent + 2
                blockFolded = value == ">"
                blockLines = []
                listPath = nil
            } else if value.hasPrefix("[") && value.hasSuffix("]") {
                let inner = value.dropFirst().dropLast()
                lists[path] = try inlineList(inner)
                listPath = path
            } else if value.isEmpty {
                listPath = path
            } else {
                scalars[path] = clean(value)
                listPath = nil
            }
        }
        try flushBlock()
        return RestrictedYAMLDocument(scalars: scalars, lists: lists)
    }
}

struct AgentSkillFrontmatterParser:
    Sendable
{
    func parse(
        _ text: String
    ) throws -> (metadata: AgentSkillMetadata, instructions: String, vendor: [String: String]) {
        guard text.hasPrefix("---") else {
            throw AgentSkillPackageError.invalidFrontmatter(
                "SKILL.md must begin with YAML frontmatter"
            )
        }
        let lines = text.components(separatedBy: .newlines)
        guard let end = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
        }) else {
            throw AgentSkillPackageError.invalidFrontmatter(
                "frontmatter closing delimiter is missing"
            )
        }
        let yaml = lines[1..<end].joined(separator: "\n")
        let body = lines[(end + 1)...]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 40_000 else {
            throw AgentSkillPackageError.invalidFrontmatter(
                "instructions must contain 1–40,000 characters"
            )
        }
        let document = try RestrictedYAMLDocument.parse(
            yaml,
            allowedRoots: [
                "name", "description", "license", "compatibility",
                "metadata", "allowed-tools",
            ],
            preserveUnknownRoots: true
        )
        let name = document.scalar("name")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let description = document.scalar("description")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard name.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"#,
            options: .regularExpression
        ) != nil else {
            throw AgentSkillPackageError.invalidFrontmatter(
                "name must be a portable 1–64 character identifier"
            )
        }
        guard !description.isEmpty, description.count <= 1_024 else {
            throw AgentSkillPackageError.invalidFrontmatter(
                "description must contain 1–1,024 characters"
            )
        }

        let metadata: [String: String] = Dictionary(
            uniqueKeysWithValues: document.scalars.compactMap { key, value -> (String, String)? in
                guard key.hasPrefix("metadata.") else { return nil }
                return (String(key.dropFirst("metadata.".count)), String(value.prefix(2_048)))
            }
        )
        let known: Set<String> = [
            "name", "description", "license", "compatibility", "allowed-tools",
        ]
        var vendor = document.scalars.filter { key, _ in
            !known.contains(key) && !key.hasPrefix("metadata.")
        }
        for (key, values) in document.lists
        where !known.contains(key) && !key.hasPrefix("metadata.") {
            vendor[key] = values.joined(separator: ", ")
        }
        let allowedTools = document.scalar("allowed-tools")
            ?? document.list("allowed-tools").nilIfEmpty?.joined(separator: ", ")
        return (
            AgentSkillMetadata(
                name: name,
                description: description,
                license: document.scalar("license"),
                compatibility: document.scalar("compatibility"),
                metadata: metadata,
                allowedTools: allowedTools
            ),
            body,
            vendor
        )
    }
}

struct VibeWhisperProfileLoader:
    Sendable
{
    func load(from url: URL?) throws -> VibeWhisperSkillProfile {
        guard let url else { return .safeDefault }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= 64 * 1_024,
              let text = String(data: data, encoding: .utf8)
        else {
            throw AgentSkillPackageError.invalidProfile("profile is too large or not UTF-8")
        }
        let document: RestrictedYAMLDocument
        do {
            document = try RestrictedYAMLDocument.parse(
                text,
                allowedRoots: ["context", "resources", "output", "risk", "validators"],
                preserveUnknownRoots: false
            )
        } catch {
            throw AgentSkillPackageError.invalidProfile(error.localizedDescription)
        }

        let allowedPaths: Set<String> = [
            "context.required", "context.optional",
            "resources.terminology", "resources.templates",
            "resources.references", "resources.examples",
            "resources.goldenTests",
            "output.format", "output.delivery", "output.risk", "risk",
            "validators.requireNonEmpty", "validators.maximumCharacters",
            "validators.preserveTechnicalLiterals",
            "validators.requireClosedMarkdownFences",
            "validators.requiredSections", "validators.forbiddenPhrases",
        ]
        if let unknownPath = document.paths.subtracting(allowedPaths).sorted().first {
            throw AgentSkillPackageError.invalidProfile(
                "unknown profile key \(unknownPath)"
            )
        }

        func sources(_ path: String) throws -> [ContextSourceKind] {
            try document.list(path).map { value in
                guard let source = ContextSourceKind(rawValue: value) else {
                    throw AgentSkillPackageError.invalidProfile(
                        "unknown Context source \(value)"
                    )
                }
                return source
            }
        }

        let formatValue = document.scalar("output.format") ?? SkillOutputFormat.plainText.rawValue
        let deliveryValue = document.scalar("output.delivery") ?? SkillDeliveryPolicy.previewThenPaste.rawValue
        let riskValue = document.scalar("risk")
            ?? document.scalar("output.risk")
            ?? SkillRiskLevel.medium.rawValue
        guard let format = SkillOutputFormat(rawValue: formatValue),
              format != .actionPreview,
              let delivery = SkillDeliveryPolicy(rawValue: deliveryValue),
              let risk = SkillRiskLevel(rawValue: riskValue)
        else {
            throw AgentSkillPackageError.invalidProfile(
                "output format, delivery, or risk is unsupported"
            )
        }
        if delivery == .automaticPasteWhenVerified, risk != .low {
            throw AgentSkillPackageError.invalidProfile(
                "medium- and high-risk Skills cannot auto-paste"
            )
        }
        let required = try sources("context.required")
        let optional = try sources("context.optional")
        let maximumCharacters = min(
            100_000,
            max(1, Int(document.scalar("validators.maximumCharacters") ?? "") ?? 12_000)
        )
        let bool: (String, Bool) -> Bool = { path, fallback in
            switch document.scalar(path)?.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return fallback
            }
        }
        return VibeWhisperSkillProfile(
            contextRequest: ContextRequest(
                required: required.isEmpty ? [.voice] : required,
                optional: optional
            ),
            resourceBindings: SkillResourceBindings(
                terminology: document.list("resources.terminology"),
                templates: document.list("resources.templates"),
                references: document.list("resources.references"),
                examples: document.list("resources.examples"),
                goldenTests: document.list("resources.goldenTests")
            ),
            output: SkillOutputContract(
                format: format,
                delivery: delivery,
                risk: risk
            ),
            validators: SkillValidatorPolicy(
                requireNonEmpty: bool("validators.requireNonEmpty", true),
                maximumCharacters: maximumCharacters,
                preserveTechnicalLiterals: bool("validators.preserveTechnicalLiterals", true),
                requireClosedMarkdownFences: bool("validators.requireClosedMarkdownFences", false),
                requiredSectionAlternatives: document.list("validators.requiredSections").map { [$0] },
                forbiddenPhrases: document.list("validators.forbiddenPhrases")
            ),
            risk: risk
        )
    }
}

struct AgentSkillPackageLoader:
    @unchecked Sendable
{
    static let maximumFileCount = 128
    static let maximumFileBytes = 512 * 1_024
    static let maximumPackageBytes = 4 * 1_024 * 1_024

    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load(from rootURL: URL) throws -> AgentSkillPackage {
        let skillURL = rootURL.appendingPathComponent("SKILL.md")
        guard fileManager.fileExists(atPath: skillURL.path) else {
            throw AgentSkillPackageError.missingSkillMarkdown
        }
        let files = try enumerateFiles(rootURL: rootURL)
        guard let skillFile = files.first(where: { $0.path == "SKILL.md" }) else {
            throw AgentSkillPackageError.missingSkillMarkdown
        }
        let skillData = try Data(contentsOf: skillFile.url, options: [.mappedIfSafe])
        guard skillData.count <= 96 * 1_024,
              let skillText = String(data: skillData, encoding: .utf8),
              !skillText.unicodeScalars.contains(where: { $0.value == 0 })
        else {
            throw AgentSkillPackageError.unreadableText("SKILL.md")
        }
        let parsed = try AgentSkillFrontmatterParser().parse(skillText)
        let descriptors = try files.map { file in
            SkillResourceDescriptor(
                relativePath: file.path,
                kind: kind(for: file.path, prefix: file.prefix),
                byteCount: file.bytes,
                contentSHA256: Self.sha256(try Data(contentsOf: file.url, options: [.mappedIfSafe])),
                runtimeVisibility: visibility(for: file.path, prefix: file.prefix)
            )
        }
        return AgentSkillPackage(
            rootURL: rootURL,
            metadata: parsed.metadata,
            instructions: parsed.instructions,
            resources: descriptors,
            vendorExtensions: parsed.vendor,
            contentSHA256: try contentHash(files)
        )
    }

    private struct FileEntry {
        let path: String
        let url: URL
        let bytes: Int
        let prefix: Data.SubSequence
    }

    private func enumerateFiles(rootURL: URL) throws -> [FileEntry] {
        let root = rootURL.standardizedFileURL
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
            ],
            options: [.skipsHiddenFiles]
        ) else {
            throw AgentSkillPackageError.unsafePath(root.path)
        }
        var files: [FileEntry] = []
        var total = 0
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
            ])
            let relative = String(url.standardizedFileURL.path.dropFirst(root.path.count + 1))
            try validate(relative)
            if values.isSymbolicLink == true {
                throw AgentSkillPackageError.symbolicLink(relative)
            }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else {
                throw AgentSkillPackageError.unsafePath(relative)
            }
            let bytes = values.fileSize ?? 0
            guard bytes <= Self.maximumFileBytes else {
                throw AgentSkillPackageError.fileTooLarge(relative)
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            files.append(FileEntry(path: relative, url: url, bytes: bytes, prefix: data.prefix(4)))
            total += bytes
            guard files.count <= Self.maximumFileCount else {
                throw AgentSkillPackageError.tooManyFiles
            }
            guard total <= Self.maximumPackageBytes else {
                throw AgentSkillPackageError.packageTooLarge
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func validate(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              path.count <= 500,
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        else {
            throw AgentSkillPackageError.unsafePath(path)
        }
    }

    private func kind(for path: String, prefix: Data.SubSequence) -> SkillResourceKind {
        if path == "SKILL.md" { return .instructions }
        if path == "vibewhisper.yaml" { return .profile }
        if path.hasPrefix("scripts/") || Self.isExecutable(path: path, prefix: prefix) { return .executable }
        if path.hasPrefix("references/") { return path.lowercased().contains("template") ? .template : .reference }
        if path.hasPrefix("assets/") { return .asset }
        if path == "terminology.csv" { return .terminology }
        if path == "examples.jsonl" { return .examples }
        if path == "tests/golden.jsonl" { return .goldenTests }
        if path.hasPrefix("agents/") { return .vendorExtension }
        return .unsupported
    }

    private func visibility(for path: String, prefix: Data.SubSequence) -> SkillResourceVisibility {
        if path.hasPrefix("scripts/") || Self.isExecutable(path: path, prefix: prefix) {
            return .quarantined
        }
        switch kind(for: path, prefix: prefix) {
        case .instructions, .profile, .vendorExtension, .examples, .goldenTests:
            return .metadataOnly
        case .reference, .asset, .template, .terminology:
            return .runtime
        case .executable, .unsupported:
            return .quarantined
        }
    }

    private static func isExecutable(path: String, prefix: Data.SubSequence) -> Bool {
        let executableExtensions: Set<String> = [
            "app", "bin", "command", "dylib", "exe", "js", "mjs", "node",
            "o", "php", "pl", "py", "rb", "sh", "so", "swift", "wasm",
        ]
        if executableExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) {
            return true
        }
        let bytes = Array(prefix)
        if bytes.prefix(2) == [0x23, 0x21] { return true }
        let machO: [[UInt8]] = [
            [0xFE, 0xED, 0xFA, 0xCE], [0xFE, 0xED, 0xFA, 0xCF],
            [0xCE, 0xFA, 0xED, 0xFE], [0xCF, 0xFA, 0xED, 0xFE],
            [0xCA, 0xFE, 0xBA, 0xBE],
        ]
        return machO.contains(bytes)
    }

    private func contentHash(_ files: [FileEntry]) throws -> String {
        var hasher = SHA256()
        for file in files {
            let pathData = Data(file.path.utf8)
            let content = try Data(contentsOf: file.url, options: [.mappedIfSafe])
            var pathLength = UInt64(pathData.count).bigEndian
            var contentLength = UInt64(content.count).bigEndian
            withUnsafeBytes(of: &pathLength) { hasher.update(data: Data($0)) }
            hasher.update(data: pathData)
            withUnsafeBytes(of: &contentLength) { hasher.update(data: Data($0)) }
            hasher.update(data: content)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct SkillCompatibilityAnalyzer:
    Sendable
{
    func analyze(
        package: AgentSkillPackage,
        profile: VibeWhisperSkillProfile
    ) -> SkillCompatibilityReport {
        var issues: [String] = []
        var ignored: [String] = []
        let quarantined = package.resources
            .filter { $0.runtimeVisibility == .quarantined }
            .map(\.relativePath)
        let hasAllowedTools = package.metadata.allowedTools?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let loweredInstructions = package.instructions.lowercased()
        let dependsOnExecutable = quarantined.contains { path in
            loweredInstructions.contains(path.lowercased())
                || loweredInstructions.contains("run the script")
                || loweredInstructions.contains("execute the script")
        }
        if hasAllowedTools {
            issues.append("allowed-tools requests tools that VibeWhisper does not expose")
        }
        if dependsOnExecutable {
            issues.append("instructions require an executable resource")
        }
        if !package.vendorExtensions.isEmpty {
            ignored.append(contentsOf: package.vendorExtensions.keys.sorted())
        }
        ignored.append(contentsOf: package.resources
            .filter { $0.kind == .vendorExtension }
            .map(\.relativePath))
        let unavailableContext = profile.contextRequest.required.filter {
            !$0.isAvailableInCurrentRuntime
        }
        if !unavailableContext.isEmpty {
            issues.append(
                "required Context sources are unavailable: "
                    + unavailableContext.map(\.rawValue).joined(separator: ", ")
            )
        }

        let level: SkillCompatibilityLevel
        if dependsOnExecutable {
            level = .executableDependent
        } else if hasAllowedTools {
            level = .toolDependent
        } else if !package.vendorExtensions.isEmpty || !ignored.isEmpty || !quarantined.isEmpty {
            level = .vendorExtended
        } else if package.resources.contains(where: { $0.relativePath == "vibewhisper.yaml" }) {
            level = .openWhisperEnhanced
        } else {
            level = .portable
        }
        return SkillCompatibilityReport(
            standardFormatStatus: .valid,
            runtimeStatus: issues.isEmpty ? .compatible : .incompatible,
            level: level,
            issues: issues,
            ignoredVendorFeatures: Array(Set(ignored)).sorted(),
            quarantinedResources: quarantined.sorted()
        )
    }
}

struct SkillResourceResolver:
    @unchecked Sendable
{
    static let maximumResolvedCharacters = 24_000
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func resolve(
        package: AgentSkillPackage,
        profile: VibeWhisperSkillProfile
    ) throws -> [ResolvedSkillResource] {
        let explicitlyBound = Set(
            profile.resourceBindings.terminology
                + profile.resourceBindings.templates
                + profile.resourceBindings.references
                + profile.resourceBindings.examples
                + profile.resourceBindings.goldenTests
        )
        let candidates = package.resources.filter {
            $0.runtimeVisibility == .runtime
                && (explicitlyBound.isEmpty || explicitlyBound.contains($0.relativePath))
        }
        var total = 0
        var output: [ResolvedSkillResource] = []
        for descriptor in candidates {
            let url = package.rootURL.appendingPathComponent(descriptor.relativePath)
            let standardized = url.standardizedFileURL
            guard standardized.path.hasPrefix(package.rootURL.standardizedFileURL.path + "/") else {
                throw AgentSkillPackageError.unsafePath(descriptor.relativePath)
            }
            let data = try Data(contentsOf: standardized, options: [.mappedIfSafe])
            guard AgentSkillPackageLoader.sha256ForRuntime(data) == descriptor.contentSHA256 else {
                throw AgentSkillPackageError.unsafePath(descriptor.relativePath)
            }
            guard let text = String(data: data, encoding: .utf8),
                  !text.unicodeScalars.contains(where: { $0.value == 0 })
            else {
                // Static binary assets are catalogued but never put into a text prompt.
                continue
            }
            let remaining = Self.maximumResolvedCharacters - total
            guard remaining > 0 else { break }
            let clipped = String(text.prefix(remaining))
            total += clipped.count
            output.append(ResolvedSkillResource(descriptor: descriptor, content: clipped))
        }
        return output
    }
}

extension AgentSkillPackageLoader {
    fileprivate static func sha256ForRuntime(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct NormalizedSkillPackage:
    Sendable,
    Equatable
{
    let format: SkillPackageFormat
    let definition: SkillDefinition
    let installation: InstalledSkillIdentity
    let package: AgentSkillPackage
    let profile: VibeWhisperSkillProfile
    let compatibility: SkillCompatibilityReport
    let resources: [ResolvedSkillResource]
}

struct AgentSkillNormalizer:
    Sendable
{
    func normalize(
        package: AgentSkillPackage
    ) throws -> NormalizedSkillPackage {
        let profileURL = package.resources.contains {
            $0.relativePath == "vibewhisper.yaml"
        } ? package.rootURL.appendingPathComponent("vibewhisper.yaml") : nil
        let profile = try VibeWhisperProfileLoader().load(from: profileURL)
        let compatibility = SkillCompatibilityAnalyzer().analyze(
            package: package,
            profile: profile
        )
        let digestPrefix = String(package.contentSHA256.prefix(12))
        let metadataID = package.metadata.metadata["vibewhisper-id"]?.lowercased()
        let generatedID = Self.generatedIdentifier(
            portableName: package.metadata.name,
            digestPrefix: digestPrefix
        )
        let id = metadataID.flatMap {
            SkillDefinition.isValidIdentifier($0) ? $0 : nil
        } ?? generatedID
        guard !SkillRegistry.builtIn.contains(id: id) else {
            throw AgentSkillPackageError.incompatible("the package ID is reserved")
        }
        let metadataVersion = package.metadata.metadata["version"]
        let version = metadataVersion.flatMap {
            SkillDefinition.isValidVersion($0) ? $0 : nil
        } ?? "0.0.0-\(digestPrefix)"
        let author = package.metadata.metadata["author"]
            ?? package.metadata.metadata["publisher"]
            ?? "Community"
        let terminology = try Self.loadTerminology(
            package: package,
            skillID: id
        )
        let requiredCapabilities = Self.capabilities(
            profile.contextRequest.required,
            includeVoice: true
        )
        let optionalCapabilities = Self.capabilities(
            profile.contextRequest.optional,
            includeVoice: false
        )
        let resources = try SkillResourceResolver().resolve(
            package: package,
            profile: profile
        )
        let definition = SkillDefinition(
            id: id,
            version: version,
            name: package.metadata.name,
            author: author,
            requiredCapabilities: requiredCapabilities,
            optionalCapabilities: optionalCapabilities,
            terminologyEntries: terminology,
            promptInstruction: package.instructions,
            output: profile.output,
            validators: profile.validators
        )
        let installation = InstalledSkillIdentity.normalized(
            definition: definition,
            sourceID: "local.agent-skills",
            revision: package.contentSHA256,
            portableName: package.metadata.name,
            packageID: package.metadata.metadata["package-id"],
            publisher: author
        )
        return NormalizedSkillPackage(
            format: .agentSkillsStandard,
            definition: definition,
            installation: installation,
            package: package,
            profile: profile,
            compatibility: compatibility,
            resources: resources
        )
    }

    private static func generatedIdentifier(
        portableName: String,
        digestPrefix: String
    ) -> String {
        let slug = portableName.lowercased()
            .replacingOccurrences(
                of: #"[^a-z0-9-]+"#,
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "community.agent.\(slug.isEmpty ? "skill" : slug).\(digestPrefix)"
    }

    private static func capabilities(
        _ sources: [ContextSourceKind],
        includeVoice: Bool
    ) -> [SkillCapability] {
        var output: [SkillCapability] = includeVoice ? [.voice] : []
        for source in sources {
            let capability: SkillCapability? = switch source {
            case .voice: .voice
            case .selection: .selection
            case .focusedParagraph: .focusedParagraph
            case .conversationWindow: .conversationWindow
            case .clipboard: .clipboard
            case .styleCapsule: .styleCapsule
            case .activeApp, .terminology, .openFile, .workspace,
                 .editorDiagnostics, .terminalSession, .browserPage:
                nil
            }
            if let capability, !output.contains(capability) {
                output.append(capability)
            }
        }
        return output
    }

    private static func loadTerminology(
        package: AgentSkillPackage,
        skillID: String
    ) throws -> [TerminologyEntry] {
        let descriptor = package.resources.first {
            $0.kind == .terminology && $0.runtimeVisibility == .runtime
        }
        guard let descriptor else { return [] }
        let url = package.rootURL.appendingPathComponent(descriptor.relativePath)
        let result = try TerminologyTextImporter().importEntries(
            from: Data(contentsOf: url, options: [.mappedIfSafe]),
            sourceName: descriptor.relativePath
        )
        return result.entries.prefix(1_000).map { entry in
            var entry = entry
            entry.source = "skill:\(skillID)"
            return entry
        }
    }
}

private extension Array {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}
