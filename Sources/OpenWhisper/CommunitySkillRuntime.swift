import CryptoKit
import Foundation

struct CommunitySkillVersionSelection:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    var skillID: String
    var version: String

    var id: String { skillID }
}

struct CommunitySkillConfig:
    Codable,
    Sendable,
    Equatable
{
    static let maximumSelectionCount = 200

    var activeVersions:
        [CommunitySkillVersionSelection] = []

    init() {}

    init(
        activeVersions:
            [CommunitySkillVersionSelection]
    ) {
        self.activeVersions =
            Self.normalized(activeVersions)
    }

    init(from decoder: any Decoder)
        throws
    {
        let container =
            try decoder.container(
                keyedBy: CodingKeys.self
            )
        activeVersions =
            Self.normalized(
                try container.decodeIfPresent(
                    [CommunitySkillVersionSelection]
                        .self,
                    forKey: .activeVersions
                ) ?? []
            )
    }

    func activeVersion(
        for skillID: String
    ) -> String? {
        activeVersions.first {
            $0.skillID == skillID
        }?.version
    }

    mutating func setActiveVersion(
        _ version: String?,
        for skillID: String
    ) {
        activeVersions.removeAll {
            $0.skillID == skillID
        }
        if
            SkillDefinition
                .isValidIdentifier(skillID),
            let version,
            SkillDefinition
                .isValidVersion(version)
        {
            activeVersions.append(
                CommunitySkillVersionSelection(
                    skillID: skillID,
                    version: version
                )
            )
        }
        activeVersions =
            Self.normalized(
                activeVersions
            )
    }

    private static func normalized(
        _ values:
            [CommunitySkillVersionSelection]
    ) -> [CommunitySkillVersionSelection] {
        var seen = Set<String>()
        return values.compactMap { value in
            guard
                SkillDefinition
                    .isValidIdentifier(
                        value.skillID
                    ),
                SkillDefinition
                    .isValidVersion(
                        value.version
                    ),
                seen.insert(value.skillID)
                    .inserted
            else {
                return nil
            }
            return value
        }
        .prefix(maximumSelectionCount)
        .map { $0 }
    }
}

enum CommunitySkillPackageError:
    LocalizedError,
    Equatable
{
    case invalidPackage(String)
    case symbolicLink(String)
    case pathTraversal(String)
    case unknownFile(String)
    case executableContent(String)
    case tooManyFiles
    case fileTooLarge(String)
    case packageTooLarge
    case missingRequiredFile(String)
    case invalidManifest(String)
    case unsupportedCapability(String)
    case unsupportedOutput(String)
    case incompatibleVersion(String)
    case alreadyInstalled(String)
    case builtInReadOnly
    case missing

    var errorDescription: String? {
        switch self {
        case .invalidPackage(let detail):
            return L10n.format(
                "The Skill package is invalid: %@",
                detail
            )
        case .symbolicLink(let path):
            return L10n.format(
                "OpenWhisper blocked a symbolic link in the Skill package: %@",
                path
            )
        case .pathTraversal(let path):
            return L10n.format(
                "OpenWhisper blocked an unsafe Skill package path: %@",
                path
            )
        case .unknownFile(let path):
            return L10n.format(
                "The Skill package contains an unsupported file: %@",
                path
            )
        case .executableContent(let path):
            return L10n.format(
                "The Skill package contains executable or script content: %@",
                path
            )
        case .tooManyFiles:
            return L10n.text(
                "The Skill package contains too many files."
            )
        case .fileTooLarge(let path):
            return L10n.format(
                "A Skill package file is too large: %@",
                path
            )
        case .packageTooLarge:
            return L10n.text(
                "The Skill package is too large."
            )
        case .missingRequiredFile(let path):
            return L10n.format(
                "The Skill package is missing %@.",
                path
            )
        case .invalidManifest(let detail):
            return L10n.format(
                "The Skill manifest is invalid: %@",
                detail
            )
        case .unsupportedCapability(let value):
            return L10n.format(
                "Community Skill v1 does not allow the %@ capability.",
                value
            )
        case .unsupportedOutput(let value):
            return L10n.format(
                "Community Skill v1 does not allow the %@ output.",
                value
            )
        case .incompatibleVersion(let version):
            return L10n.format(
                "This Skill requires OpenWhisper %@ or later.",
                version
            )
        case .alreadyInstalled(let version):
            return L10n.format(
                "Skill version %@ is already installed.",
                version
            )
        case .builtInReadOnly:
            return L10n.text(
                "Built-in Skills cannot be removed."
            )
        case .missing:
            return L10n.text(
                "The installed Skill no longer exists."
            )
        }
    }
}

struct CommunitySkillPackage:
    Sendable,
    Equatable,
    Identifiable
{
    let definition: SkillDefinition
    let packageURL: URL
    let relativeFiles: [String]
    let contentSHA256: String
    var isActive: Bool

    var id: String {
        "\(definition.id)@\(definition.version)"
    }
}

struct RejectedCommunitySkillPackage:
    Sendable,
    Equatable,
    Identifiable
{
    let path: String
    let reason: String

    var id: String {
        "\(path)|\(reason)"
    }
}

struct CommunitySkillInventory:
    Sendable,
    Equatable
{
    let packages:
        [CommunitySkillPackage]
    let rejected:
        [RejectedCommunitySkillPackage]

    var activeDefinitions:
        [SkillDefinition]
    {
        packages
            .filter(\.isActive)
            .map(\.definition)
    }

    var registry: SkillRegistry {
        SkillRegistry.builtIn
            .merging(activeDefinitions)
    }
}

struct CommunitySkillGoldenTestResult:
    Sendable,
    Equatable
{
    let total: Int
    let passed: Int
    let issueCodes: [String]
}

private struct CommunitySkillManifest {
    let schemaVersion: Int
    let id: String
    let version: String
    let name: String
    let author: String
    let minimumAppVersion: String
    let requiredCapabilities:
        [SkillCapability]
    let optionalCapabilities:
        [SkillCapability]
    let output: SkillOutputContract
    let validators:
        SkillValidatorPolicy
}

private struct CommunityValidatorDocument:
    Decodable
{
    var requireNonEmpty: Bool?
    var maximumCharacters: Int?
    var preserveTechnicalLiterals: Bool?
    var requireClosedMarkdownFences:
        Bool?
    var requiredSections: [String]?
    var requiredSectionAlternatives:
        [[String]]?
    var forbiddenPhrases: [String]?
}

private struct CommunityGoldenCase:
    Decodable
{
    var name: String?
    var transcript: String
    var selectedText: String?
    var expectedOutput: String
}

private struct CommunitySkillFile {
    let relativePath: String
    let url: URL
    let byteCount: Int
}

struct SkillPackageStore:
    @unchecked Sendable
{
    static let maximumFileCount = 64
    static let maximumFileBytes =
        256 * 1_024
    static let maximumPackageBytes =
        1_024 * 1_024
    static let maximumPromptBytes =
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
                    "Skills/Installed",
                    isDirectory: true
                )
    }

    func inspect(
        packageURL: URL
    ) throws -> CommunitySkillPackage {
        let files =
            try validatedFiles(
                in: packageURL
            )
        let fileMap = Dictionary(
            uniqueKeysWithValues:
                files.map {
                    ($0.relativePath, $0)
                }
        )
        guard
            let manifestFile =
                fileMap["skill.yaml"]
        else {
            throw CommunitySkillPackageError
                .missingRequiredFile(
                    "skill.yaml"
                )
        }
        guard
            let promptFile =
                fileMap["prompt.md"]
        else {
            throw CommunitySkillPackageError
                .missingRequiredFile(
                    "prompt.md"
                )
        }
        guard
            promptFile.byteCount
                <= Self.maximumPromptBytes
        else {
            throw CommunitySkillPackageError
                .fileTooLarge("prompt.md")
        }

        let manifestText =
            try utf8Text(
                at: manifestFile.url,
                relativePath:
                    manifestFile.relativePath
            )
        let manifest =
            try parseManifest(manifestText)
        try validateManifest(manifest)

        let prompt =
            try utf8Text(
                at: promptFile.url,
                relativePath:
                    promptFile.relativePath
            )
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard
            !prompt.isEmpty,
            prompt.count <= 40_000
        else {
            throw CommunitySkillPackageError
                .invalidPackage(
                    "prompt.md must contain 1–40,000 readable characters"
                )
        }

        let terminology =
            try loadTerminology(
                file: fileMap[
                    "terminology.csv"
                ],
                skillID: manifest.id
            )
        let validators =
            try loadValidators(
                file: fileMap[
                    "validators.json"
                ],
                fallback:
                    manifest.validators
            )
        try validateOptionalJSONFiles(
            files: files
        )

        let definition = SkillDefinition(
            schemaVersion:
                manifest.schemaVersion,
            id: manifest.id,
            version: manifest.version,
            name:
                try localizedName(
                    files: files,
                    fallback:
                        manifest.name
                ),
            author: manifest.author,
            minimumAppVersion:
                manifest.minimumAppVersion,
            requiredCapabilities:
                manifest.requiredCapabilities,
            optionalCapabilities:
                manifest.optionalCapabilities,
            terminologyEntries:
                terminology,
            promptInstruction: prompt,
            output: manifest.output,
            validators: validators
        )
        guard
            definition.schemaVersion == 1,
            SkillDefinition
                .isValidIdentifier(
                    definition.id
                ),
            SkillDefinition
                .isValidVersion(
                    definition.version
                ),
            !SkillRegistry.builtIn
                .contains(id: definition.id)
        else {
            throw CommunitySkillPackageError
                .invalidManifest(
                    "the ID or version is reserved or malformed"
                )
        }

        return CommunitySkillPackage(
            definition: definition,
            packageURL: packageURL,
            relativeFiles:
                files.map(\.relativePath)
                    .sorted(),
            contentSHA256:
                try contentHash(files),
            isActive: false
        )
    }

    func install(
        from packageURL: URL
    ) throws -> CommunitySkillPackage {
        guard
            packageURL.pathExtension
                .lowercased()
                == "openwhisperskill"
        else {
            throw CommunitySkillPackageError
                .invalidPackage(
                    "choose a .openwhisperskill directory"
                )
        }
        let inspected =
            try inspect(
                packageURL: packageURL
            )
        try prepareRoot()
        let skillRoot =
            rootURL.appendingPathComponent(
                inspected.definition.id,
                isDirectory: true
            )
        let destination =
            skillRoot.appendingPathComponent(
                inspected.definition.version,
                isDirectory: true
            )
        guard
            !fileManager.fileExists(
                atPath: destination.path
            )
        else {
            throw CommunitySkillPackageError
                .alreadyInstalled(
                    inspected
                        .definition.version
                )
        }
        try secureCreateDirectory(
            skillRoot
        )
        let temporary =
            skillRoot.appendingPathComponent(
                ".install-\(UUID().uuidString)",
                isDirectory: true
            )
        try secureCreateDirectory(
            temporary
        )
        do {
            for relativePath in
                inspected.relativeFiles
            {
                let source =
                    packageURL
                        .appendingPathComponent(
                            relativePath,
                            isDirectory: false
                        )
                let target =
                    temporary
                        .appendingPathComponent(
                            relativePath,
                            isDirectory: false
                        )
                try secureCreateDirectory(
                    target
                        .deletingLastPathComponent()
                )
                let values =
                    try source.resourceValues(
                        forKeys: [
                            .isRegularFileKey,
                            .isSymbolicLinkKey,
                            .fileSizeKey,
                        ]
                    )
                guard
                    values.isRegularFile
                        == true,
                    values.isSymbolicLink
                        != true,
                    (values.fileSize ?? 0)
                        <= Self.maximumFileBytes
                else {
                    throw CommunitySkillPackageError
                        .invalidPackage(
                            relativePath
                        )
                }
                let data = try Data(
                    contentsOf: source,
                    options: [.mappedIfSafe]
                )
                try data.write(
                    to: target,
                    options: [.atomic]
                )
                try setFilePermissions(
                    target
                )
            }
            let copied =
                try inspect(
                    packageURL: temporary
                )
            guard
                copied.definition
                    == inspected.definition,
                copied.contentSHA256
                    == inspected
                        .contentSHA256
            else {
                throw CommunitySkillPackageError
                    .invalidPackage(
                        "the package changed during import"
                    )
            }
            try fileManager.moveItem(
                at: temporary,
                to: destination
            )
            try secureCreateDirectory(
                destination
            )
            return CommunitySkillPackage(
                definition:
                    copied.definition,
                packageURL: destination,
                relativeFiles:
                    copied.relativeFiles,
                contentSHA256:
                    copied.contentSHA256,
                isActive: true
            )
        } catch {
            try? fileManager.removeItem(
                at: temporary
            )
            throw error
        }
    }

    func loadInventory(
        config:
            CommunitySkillConfig
    ) -> CommunitySkillInventory {
        do {
            try prepareRoot()
        } catch {
            return CommunitySkillInventory(
                packages: [],
                rejected: [
                    RejectedCommunitySkillPackage(
                        path:
                            rootURL.path,
                        reason:
                            error
                                .localizedDescription
                    ),
                ]
            )
        }

        var packages:
            [CommunitySkillPackage] = []
        var rejected:
            [RejectedCommunitySkillPackage] = []
        let skillDirectories =
            safeDirectoryContents(
                at: rootURL,
                rejected: &rejected
            )
        for skillDirectory in
            skillDirectories
        {
            let versionDirectories =
                safeDirectoryContents(
                    at: skillDirectory,
                    rejected: &rejected
                )
            for versionDirectory in
                versionDirectories
            {
                do {
                    let package =
                        try inspect(
                            packageURL:
                                versionDirectory
                        )
                    guard
                        package.definition.id
                            == skillDirectory
                                .lastPathComponent,
                        package.definition.version
                            == versionDirectory
                                .lastPathComponent
                    else {
                        throw CommunitySkillPackageError
                            .pathTraversal(
                                versionDirectory
                                    .lastPathComponent
                            )
                    }
                    packages.append(package)
                } catch {
                    rejected.append(
                        RejectedCommunitySkillPackage(
                            path:
                                versionDirectory
                                    .path,
                            reason:
                                error
                                    .localizedDescription
                        )
                    )
                }
            }
        }

        let grouped =
            Dictionary(
                grouping: packages,
                by: {
                    $0.definition.id
                }
            )
        var activeIDs = Set<String>()
        for (skillID, versions) in grouped {
            let requested =
                config.activeVersion(
                    for: skillID
                )
            let selected =
                versions.first {
                    $0.definition.version
                        == requested
                }
                ?? versions.sorted {
                    SemanticVersion
                        .compare(
                            $0.definition
                                .version,
                            $1.definition
                                .version
                        ) == .orderedDescending
                }.first
            if let selected {
                activeIDs.insert(selected.id)
            }
        }
        packages = packages.map {
            var package = $0
            package.isActive =
                activeIDs.contains(
                    package.id
                )
            return package
        }
        .sorted {
            if
                $0.definition.id
                    != $1.definition.id
            {
                return $0.definition.id
                    < $1.definition.id
            }
            return SemanticVersion.compare(
                $0.definition.version,
                $1.definition.version
            ) == .orderedDescending
        }

        return CommunitySkillInventory(
            packages: packages,
            rejected: rejected
        )
    }

    func registry(
        config:
            CommunitySkillConfig
    ) -> SkillRegistry {
        loadInventory(config: config)
            .registry
    }

    func uninstall(
        skillID: String,
        version: String? = nil
    ) throws {
        guard
            !SkillRegistry.builtIn
                .contains(id: skillID)
        else {
            throw CommunitySkillPackageError
                .builtInReadOnly
        }
        guard
            SkillDefinition
                .isValidIdentifier(skillID)
        else {
            throw CommunitySkillPackageError
                .missing
        }
        let skillRoot =
            rootURL.appendingPathComponent(
                skillID,
                isDirectory: true
            )
        let target: URL
        if let version {
            guard
                SkillDefinition
                    .isValidVersion(version)
            else {
                throw CommunitySkillPackageError
                    .missing
            }
            target =
                skillRoot
                    .appendingPathComponent(
                        version,
                        isDirectory: true
                    )
        } else {
            target = skillRoot
        }
        guard
            fileManager.fileExists(
                atPath: target.path
            )
        else {
            throw CommunitySkillPackageError
                .missing
        }
        let values =
            try target.resourceValues(
                forKeys: [
                    .isSymbolicLinkKey,
                ]
            )
        guard values.isSymbolicLink != true
        else {
            throw CommunitySkillPackageError
                .symbolicLink(
                    target.lastPathComponent
                )
        }
        try fileManager.removeItem(
            at: target
        )
        if
            target != skillRoot,
            (
                try? fileManager
                    .contentsOfDirectory(
                        atPath: skillRoot.path
                    )
            )?.isEmpty == true
        {
            try? fileManager.removeItem(
                at: skillRoot
            )
        }
    }

    func runGoldenTests(
        package:
            CommunitySkillPackage
    ) throws
        -> CommunitySkillGoldenTestResult
    {
        let url =
            package.packageURL
                .appendingPathComponent(
                    "tests/golden.jsonl"
                )
        guard
            fileManager.fileExists(
                atPath: url.path
            )
        else {
            return CommunitySkillGoldenTestResult(
                total: 0,
                passed: 0,
                issueCodes: []
            )
        }
        let values =
            try url.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                ]
            )
        guard
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            (values.fileSize ?? 0)
                <= Self.maximumFileBytes
        else {
            throw CommunitySkillPackageError
                .invalidPackage(
                    "tests/golden.jsonl"
                )
        }
        let text =
            try utf8Text(
                at: url,
                relativePath:
                    "tests/golden.jsonl"
            )
        let cases =
            try text.split(
                whereSeparator: \.isNewline
            ).map {
                try JSONDecoder().decode(
                    CommunityGoldenCase.self,
                    from: Data($0.utf8)
                )
            }
        guard cases.count <= 200
        else {
            throw CommunitySkillPackageError
                .invalidPackage(
                    "tests/golden.jsonl"
                )
        }
        let plan =
            ResolvedSkillExecutionPlan(
                skill:
                    package.definition,
                source: .manual,
                matchedApplicationRuleID:
                    nil
            )
        var passed = 0
        var issueCodes:
            [String] = []
        for testCase in cases {
            let context =
                SkillPromptContext(
                    selection:
                        testCase.selectedText
                )
            let messages =
                SkillPromptCompiler()
                    .compile(
                        transcript:
                            testCase.transcript,
                        terminologyEntries:
                            package.definition
                                .terminologyEntries,
                        config:
                            TextPolishConfig(),
                        plan: plan,
                        context: context
                    )
            let compiled =
                messages.first?.content
                ?? ""
            let systemPosition =
                compiled.range(
                    of:
                        SkillPromptCompiler
                            .systemMarker
                )?.lowerBound
                ?? compiled.endIndex
            let skillPosition =
                compiled.range(
                    of:
                        SkillPromptCompiler
                            .skillMarker
                )?.lowerBound
                ?? compiled.startIndex
            let shellIsOrdered =
                systemPosition
                    < skillPosition
            let validation =
                SkillValidatorEngine()
                    .validate(
                        output:
                            testCase
                                .expectedOutput,
                        originalText: [
                            testCase.transcript,
                            testCase.selectedText,
                        ]
                        .compactMap { $0 }
                        .joined(
                            separator: "\n"
                        ),
                        plan: plan
                    )
            if
                shellIsOrdered,
                validation.isValid
            {
                passed += 1
            } else {
                if !shellIsOrdered {
                    issueCodes.append(
                        "safetyShellOrder"
                    )
                }
                issueCodes.append(
                    contentsOf:
                        validation.issues
                            .map {
                                $0.code.rawValue
                            }
                )
            }
        }
        return CommunitySkillGoldenTestResult(
            total: cases.count,
            passed: passed,
            issueCodes:
                Array(
                    Set(issueCodes)
                ).sorted()
        )
    }

    private func validatedFiles(
        in packageURL: URL
    ) throws -> [CommunitySkillFile] {
        guard packageURL.isFileURL else {
            throw CommunitySkillPackageError
                .invalidPackage(
                    "the source is not a local package"
                )
        }
        let rootValues =
            try packageURL.resourceValues(
                forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                ]
            )
        guard
            rootValues.isDirectory == true,
            rootValues.isSymbolicLink
                != true
        else {
            throw CommunitySkillPackageError
                .invalidPackage(
                    "choose a .openwhisperskill directory"
                )
        }
        var enumerationError:
            Error?
        guard
            let enumerator =
                fileManager.enumerator(
                    at: packageURL,
                    includingPropertiesForKeys: [
                        .isDirectoryKey,
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                        .fileSizeKey,
                    ],
                    options: [],
                    errorHandler: {
                        _, error in
                        enumerationError =
                            error
                        return false
                    }
                )
        else {
            throw CommunitySkillPackageError
                .invalidPackage(
                    "the package could not be enumerated"
                )
        }

        var files:
            [CommunitySkillFile] = []
        var totalBytes = 0
        for case let url as URL in enumerator {
            let relativePath =
                relativePath(
                    url,
                    root: packageURL
                )
            if
                relativePath == ".DS_Store"
                    || relativePath
                        .hasSuffix(
                            "/.DS_Store"
                        )
            {
                continue
            }
            try validateRelativePath(
                relativePath
            )
            let values =
                try url.resourceValues(
                    forKeys: [
                        .isDirectoryKey,
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                        .fileSizeKey,
                    ]
                )
            guard values.isSymbolicLink != true
            else {
                throw CommunitySkillPackageError
                    .symbolicLink(
                        relativePath
                    )
            }
            if values.isDirectory == true {
                guard
                    isAllowedDirectory(
                        relativePath
                    )
                else {
                    throw CommunitySkillPackageError
                        .unknownFile(
                            relativePath
                        )
                }
                continue
            }
            guard values.isRegularFile == true
            else {
                throw CommunitySkillPackageError
                    .unknownFile(
                        relativePath
                    )
            }
            guard
                isAllowedFile(
                    relativePath
                )
            else {
                if
                    isExecutableExtension(
                        url.pathExtension
                    )
                {
                    throw CommunitySkillPackageError
                        .executableContent(
                            relativePath
                        )
                }
                throw CommunitySkillPackageError
                    .unknownFile(
                        relativePath
                    )
            }
            let byteCount =
                values.fileSize ?? 0
            guard
                byteCount
                    <= Self.maximumFileBytes
            else {
                throw CommunitySkillPackageError
                    .fileTooLarge(
                        relativePath
                    )
            }
            let attributes =
                try fileManager
                    .attributesOfItem(
                        atPath: url.path
                    )
            let permissions =
                (
                    attributes[
                        .posixPermissions
                    ] as? NSNumber
                )?.intValue ?? 0
            guard permissions & 0o111 == 0
            else {
                throw CommunitySkillPackageError
                    .executableContent(
                        relativePath
                    )
            }
            let prefix = try Data(
                contentsOf: url,
                options: [.mappedIfSafe]
            ).prefix(4)
            guard
                prefix != Data([0x23, 0x21]),
                !isMachOMagic(prefix)
            else {
                throw CommunitySkillPackageError
                    .executableContent(
                        relativePath
                    )
            }
            files.append(
                CommunitySkillFile(
                    relativePath:
                        relativePath,
                    url: url,
                    byteCount: byteCount
                )
            )
            guard
                files.count
                    <= Self.maximumFileCount
            else {
                throw CommunitySkillPackageError
                    .tooManyFiles
            }
            totalBytes += byteCount
            guard
                totalBytes
                    <= Self.maximumPackageBytes
            else {
                throw CommunitySkillPackageError
                    .packageTooLarge
            }
        }
        if let enumerationError {
            throw CommunitySkillPackageError
                .invalidPackage(
                    enumerationError
                        .localizedDescription
                )
        }
        return files.sorted {
            $0.relativePath
                < $1.relativePath
        }
    }

    private func parseManifest(
        _ text: String
    ) throws -> CommunitySkillManifest {
        let document =
            try FlatYAMLDocument.parse(text)
        let schemaVersion =
            try requiredInt(
                document,
                key: "schemaVersion"
            )
        let id =
            try requiredScalar(
                document,
                key: "id",
                maximum: 160
            ).lowercased()
        let version =
            try requiredScalar(
                document,
                key: "version",
                maximum: 64
            )
        let name =
            try requiredScalar(
                document,
                key: "name",
                maximum: 120
            )
        let author =
            document.scalar(
                "author"
            ).map {
                String($0.prefix(120))
            } ?? "Community"
        let minimumAppVersion =
            document.scalar(
                "minimumAppVersion"
            ) ?? "0.1.0"
        let required =
            try capabilities(
                document.list(
                    "permissions.required"
                ).isEmpty
                ? ["voice"]
                : document.list(
                    "permissions.required"
                )
            )
        let optional =
            try capabilities(
                document.list(
                    "permissions.optional"
                )
            )
        guard
            let format =
                SkillOutputFormat(
                    rawValue:
                        document.scalar(
                            "output.format"
                        ) ?? "plainText"
                ),
            let delivery =
                SkillDeliveryPolicy(
                    rawValue:
                        document.scalar(
                            "output.delivery"
                        ) ?? "previewThenPaste"
                ),
            let risk =
                SkillRiskLevel(
                    rawValue:
                        document.scalar(
                            "output.risk"
                        ) ?? "medium"
                )
        else {
            throw CommunitySkillPackageError
                .invalidManifest(
                    "output format, delivery, or risk is unsupported"
                )
        }
        return CommunitySkillManifest(
            schemaVersion: schemaVersion,
            id: id,
            version: version,
            name: name,
            author: author,
            minimumAppVersion:
                minimumAppVersion,
            requiredCapabilities:
                required,
            optionalCapabilities:
                optional,
            output: SkillOutputContract(
                format: format,
                delivery: delivery,
                risk: risk
            ),
            validators:
                SkillValidatorPolicy(
                    requireNonEmpty:
                        parseBool(
                            document.scalar(
                                "validators.requireNonEmpty"
                            )
                        ) ?? true,
                    maximumCharacters:
                        Int(
                            document.scalar(
                                "validators.maximumCharacters"
                            ) ?? ""
                        ) ?? 12_000,
                    preserveTechnicalLiterals:
                        parseBool(
                            document.scalar(
                                "validators.preserveTechnicalLiterals"
                            )
                        ) ?? true,
                    requireClosedMarkdownFences:
                        parseBool(
                            document.scalar(
                                "validators.requireClosedMarkdownFences"
                            )
                        ) ?? false,
                    requiredSectionAlternatives:
                        document.list(
                            "validators.requiredSections"
                        ).map { [$0] },
                    forbiddenPhrases:
                        document.list(
                            "validators.forbiddenPhrases"
                        )
                )
        )
    }

    private func validateManifest(
        _ manifest:
            CommunitySkillManifest
    ) throws {
        guard manifest.schemaVersion == 1
        else {
            throw CommunitySkillPackageError
                .invalidManifest(
                    "schemaVersion must be 1"
                )
        }
        guard
            SkillDefinition
                .isValidIdentifier(
                    manifest.id
                ),
            !manifest.id.hasPrefix(
                "app.openwhisper.skill."
            )
        else {
            throw CommunitySkillPackageError
                .invalidManifest(
                    "use a reverse-domain ID that does not reserve OpenWhisper's built-in namespace"
                )
        }
        guard
            SkillDefinition
                .isValidVersion(
                    manifest.version
                ),
            SkillDefinition
                .isValidVersion(
                    manifest
                        .minimumAppVersion
                )
        else {
            throw CommunitySkillPackageError
                .invalidManifest(
                    "versions must use semantic versioning"
                )
        }
        guard
            SemanticVersion.compare(
                ProductIdentity
                    .runtimeVersion,
                manifest.minimumAppVersion
            ) != .orderedAscending
        else {
            throw CommunitySkillPackageError
                .incompatibleVersion(
                    manifest
                        .minimumAppVersion
                )
        }
        guard
            manifest.requiredCapabilities
                .contains(.voice)
        else {
            throw CommunitySkillPackageError
                .invalidManifest(
                    "voice must be a required capability"
                )
        }
        let supported:
            Set<SkillCapability> = [
                .voice,
                .selection,
                .styleCapsule,
            ]
        for capability in
            manifest.requiredCapabilities
            + manifest.optionalCapabilities
        where !supported.contains(
            capability
        ) {
            throw CommunitySkillPackageError
                .unsupportedCapability(
                    capability.rawValue
                )
        }
        if
            manifest.requiredCapabilities
                .contains(where: {
                    $0 != .voice
                })
        {
            throw CommunitySkillPackageError
                .invalidManifest(
                    "selection and Style Capsule access must be optional and user-controlled"
                )
        }
        guard
            manifest.output.format
                != .actionPreview
        else {
            throw CommunitySkillPackageError
                .unsupportedOutput(
                    SkillOutputFormat
                        .actionPreview.rawValue
                )
        }
        guard
            manifest.output.delivery
                != .automaticPasteWhenVerified
                || manifest.output.risk
                    == .low
        else {
            throw CommunitySkillPackageError
                .invalidManifest(
                    "medium- and high-risk community Skills must preview or copy"
                )
        }
    }

    private func loadTerminology(
        file: CommunitySkillFile?,
        skillID: String
    ) throws -> [TerminologyEntry] {
        guard let file else {
            return []
        }
        let result =
            try TerminologyTextImporter()
                .importEntries(
                    from: Data(
                        contentsOf:
                            file.url,
                        options:
                            [.mappedIfSafe]
                    ),
                    sourceName:
                        file.relativePath
                )
        return result.entries
            .prefix(1_000)
            .map { entry in
                var entry = entry
                entry.source =
                    "skill:\(skillID)"
                entry.createdAt =
                    "1970-01-01T00:00:00Z"
                entry.id =
                    StableIdentifier.uuid(
                        namespace:
                            "OpenWhisper.CommunitySkillTerminology",
                        components: [
                            skillID,
                            entry.type
                                .rawValue,
                            entry.original,
                            entry.replacement,
                            entry.aliases
                                .joined(
                                    separator:
                                        "\u{1F}"
                                ),
                        ]
                    )
                return entry
            }
    }

    private func loadValidators(
        file: CommunitySkillFile?,
        fallback:
            SkillValidatorPolicy
    ) throws -> SkillValidatorPolicy {
        guard let file else {
            return fallback
        }
        let data = try Data(
            contentsOf: file.url,
            options: [.mappedIfSafe]
        )
        let object =
            try JSONSerialization
                .jsonObject(with: data)
        guard
            let dictionary =
                object as? [String: Any]
        else {
            throw CommunitySkillPackageError
                .invalidPackage(
                    "validators.json must be a JSON object"
                )
        }
        let allowed: Set<String> = [
            "requireNonEmpty",
            "maximumCharacters",
            "preserveTechnicalLiterals",
            "requireClosedMarkdownFences",
            "requiredSections",
            "requiredSectionAlternatives",
            "forbiddenPhrases",
        ]
        guard
            Set(dictionary.keys)
                .isSubset(of: allowed)
        else {
            throw CommunitySkillPackageError
                .invalidPackage(
                    "validators.json contains an unknown validator"
                )
        }
        let decoded =
            try JSONDecoder().decode(
                CommunityValidatorDocument
                    .self,
                from: data
            )
        let alternatives =
            decoded
                .requiredSectionAlternatives
            ?? decoded.requiredSections?
                .map { [$0] }
            ?? []
        return SkillValidatorPolicy(
            requireNonEmpty:
                decoded.requireNonEmpty
                ?? true,
            maximumCharacters:
                decoded.maximumCharacters
                ?? 12_000,
            preserveTechnicalLiterals:
                decoded
                    .preserveTechnicalLiterals
                ?? true,
            requireClosedMarkdownFences:
                decoded
                    .requireClosedMarkdownFences
                ?? false,
            requiredSectionAlternatives:
                alternatives,
            forbiddenPhrases:
                decoded.forbiddenPhrases
                ?? []
        )
    }

    private func validateOptionalJSONFiles(
        files: [CommunitySkillFile]
    ) throws {
        for file in files {
            if
                file.relativePath
                    .hasPrefix(
                        "localizations/"
                    ),
                file.relativePath
                    .hasSuffix(".json")
            {
                let object =
                    try JSONSerialization
                        .jsonObject(
                            with: Data(
                                contentsOf:
                                    file.url
                            )
                        )
                guard
                    let dictionary =
                        object
                            as? [String: String],
                    dictionary.count <= 500
                else {
                    throw CommunitySkillPackageError
                        .invalidPackage(
                            file.relativePath
                        )
                }
            }
            if
                file.relativePath
                    == "examples.jsonl"
                    || file.relativePath
                        == "tests/golden.jsonl"
            {
                let text =
                    try utf8Text(
                        at: file.url,
                        relativePath:
                            file.relativePath
                    )
                let lines =
                    text.split(
                        whereSeparator:
                            \.isNewline
                    )
                guard lines.count <= 200
                else {
                    throw CommunitySkillPackageError
                        .invalidPackage(
                            file.relativePath
                        )
                }
                for line in lines {
                    _ = try JSONSerialization
                        .jsonObject(
                            with:
                                Data(line.utf8)
                        )
                }
            }
        }
    }

    private func localizedName(
        files:
            [CommunitySkillFile],
        fallback: String
    ) throws -> String {
        let preferred =
            L10n.selectedLocalization
        let candidates = [
            "localizations/\(preferred).json",
            "localizations/en.json",
        ]
        for path in candidates {
            guard
                let file = files.first(
                    where: {
                        $0.relativePath
                            == path
                    }
                )
            else {
                continue
            }
            let object =
                try JSONSerialization
                    .jsonObject(
                        with: Data(
                            contentsOf:
                                file.url
                        )
                    )
            if
                let values =
                    object
                        as? [String: String],
                let name =
                    values["name"]?
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        ),
                !name.isEmpty
            {
                return String(
                    name.prefix(120)
                )
            }
        }
        return fallback
    }

    private func capabilities(
        _ values: [String]
    ) throws -> [SkillCapability] {
        try values.map { value in
            guard
                let capability =
                    SkillCapability(
                        rawValue: value
                    )
            else {
                throw CommunitySkillPackageError
                    .unsupportedCapability(
                        value
                    )
            }
            return capability
        }
    }

    private func parseBool(
        _ value: String?
    ) -> Bool? {
        switch value?.lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }

    private func requiredScalar(
        _ document: FlatYAMLDocument,
        key: String,
        maximum: Int
    ) throws -> String {
        guard
            let value =
                document.scalar(key)?
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    ),
            !value.isEmpty,
            value.count <= maximum
        else {
            throw CommunitySkillPackageError
                .invalidManifest(
                    "\(key) is missing or too long"
                )
        }
        return value
    }

    private func requiredInt(
        _ document: FlatYAMLDocument,
        key: String
    ) throws -> Int {
        guard
            let raw = document.scalar(key),
            let value = Int(raw)
        else {
            throw CommunitySkillPackageError
                .invalidManifest(
                    "\(key) must be an integer"
                )
        }
        return value
    }

    private func contentHash(
        _ files:
            [CommunitySkillFile]
    ) throws -> String {
        var hasher = SHA256()
        hasher.update(
            data: Data(
                "OpenWhisperCommunitySkillV1\u{0}"
                    .utf8
            )
        )
        let sortedFiles = files.sorted(by: {
            $0.relativePath
                < $1.relativePath
        })
        hasher.update(
            data: lengthPrefix(
                sortedFiles.count
            )
        )
        for file in sortedFiles {
            let pathData = Data(
                file.relativePath.utf8
            )
            let fileData = try Data(
                contentsOf: file.url,
                options: [.mappedIfSafe]
            )
            hasher.update(
                data: lengthPrefix(
                    pathData.count
                )
            )
            hasher.update(
                data: pathData
            )
            hasher.update(
                data: lengthPrefix(
                    fileData.count
                )
            )
            hasher.update(data: fileData)
        }
        return hasher.finalize()
            .map {
                String(
                    format: "%02x",
                    $0
                )
            }
            .joined()
    }

    private func lengthPrefix(
        _ value: Int
    ) -> Data {
        var encoded =
            UInt64(value).bigEndian
        return withUnsafeBytes(
            of: &encoded
        ) {
            Data($0)
        }
    }

    private func utf8Text(
        at url: URL,
        relativePath: String
    ) throws -> String {
        let data = try Data(
            contentsOf: url,
            options: [.mappedIfSafe]
        )
        guard
            let text = String(
                data: data,
                encoding: .utf8
            ),
            !text.unicodeScalars
                .contains(where: {
                    $0.value == 0
                })
        else {
            throw CommunitySkillPackageError
                .invalidPackage(
                    "\(relativePath) is not readable UTF-8 text"
                )
        }
        return text
    }

    private func safeDirectoryContents(
        at url: URL,
        rejected:
            inout [RejectedCommunitySkillPackage]
    ) -> [URL] {
        do {
            return try fileManager
                .contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [
                        .isDirectoryKey,
                        .isSymbolicLinkKey,
                    ],
                    options: [
                        .skipsHiddenFiles,
                    ]
                )
                .filter { child in
                    let values =
                        try child.resourceValues(
                            forKeys: [
                                .isDirectoryKey,
                                .isSymbolicLinkKey,
                            ]
                        )
                    guard
                        values.isDirectory
                            == true,
                        values.isSymbolicLink
                            != true
                    else {
                        throw CommunitySkillPackageError
                            .symbolicLink(
                                child
                                    .lastPathComponent
                            )
                    }
                    return true
                }
        } catch {
            rejected.append(
                RejectedCommunitySkillPackage(
                    path: url.path,
                    reason:
                        error.localizedDescription
                )
            )
            return []
        }
    }

    private func prepareRoot() throws {
        try secureCreateDirectory(
            rootURL
        )
    }

    private func secureCreateDirectory(
        _ url: URL
    ) throws {
        if fileManager.fileExists(
            atPath: url.path
        ) {
            let values =
                try url.resourceValues(
                    forKeys: [
                        .isDirectoryKey,
                        .isSymbolicLinkKey,
                    ]
                )
            guard
                values.isDirectory == true,
                values.isSymbolicLink
                    != true
            else {
                throw CommunitySkillPackageError
                    .symbolicLink(
                        url.lastPathComponent
                    )
            }
        } else {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories:
                    true
            )
        }
        try fileManager.setAttributes(
            [
                .posixPermissions:
                    NSNumber(
                        value:
                            Int16(0o700)
                    ),
            ],
            ofItemAtPath: url.path
        )
    }

    private func setFilePermissions(
        _ url: URL
    ) throws {
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

    private func relativePath(
        _ url: URL,
        root: URL
    ) -> String {
        let rootPath =
            root.standardizedFileURL.path
        let path =
            url.standardizedFileURL.path
        guard
            path.hasPrefix(
                rootPath + "/"
            )
        else {
            return "../"
        }
        return String(
            path.dropFirst(
                rootPath.count + 1
            )
        )
    }

    private func validateRelativePath(
        _ value: String
    ) throws {
        let components =
            value.split(
                separator: "/",
                omittingEmptySubsequences:
                    false
            )
        guard
            !value.isEmpty,
            !value.hasPrefix("/"),
            !components.contains(
                where: {
                    $0 == ".."
                        || $0 == "."
                        || $0.isEmpty
                }
            ),
            value.count <= 500
        else {
            throw CommunitySkillPackageError
                .pathTraversal(value)
        }
    }

    private func isAllowedDirectory(
        _ path: String
    ) -> Bool {
        path == "localizations"
            || path == "tests"
    }

    private func isAllowedFile(
        _ path: String
    ) -> Bool {
        let exact: Set<String> = [
            "skill.yaml",
            "prompt.md",
            "terminology.csv",
            "examples.jsonl",
            "validators.json",
            "tests/golden.jsonl",
        ]
        if exact.contains(path) {
            return true
        }
        if
            path.hasPrefix(
                "localizations/"
            ),
            path.hasSuffix(".json"),
            path.split(separator: "/")
                .count == 2
        {
            return true
        }
        return false
    }

    private func isExecutableExtension(
        _ value: String
    ) -> Bool {
        let extensions: Set<String> = [
            "app",
            "bin",
            "command",
            "dylib",
            "exe",
            "js",
            "mjs",
            "node",
            "o",
            "php",
            "pl",
            "py",
            "rb",
            "sh",
            "so",
            "swift",
            "wasm",
        ]
        return extensions.contains(
            value.lowercased()
        )
    }

    private func isMachOMagic(
        _ prefix: Data.SubSequence
    ) -> Bool {
        let values = Array(prefix)
        let magics: [[UInt8]] = [
            [0xFE, 0xED, 0xFA, 0xCE],
            [0xFE, 0xED, 0xFA, 0xCF],
            [0xCE, 0xFA, 0xED, 0xFE],
            [0xCF, 0xFA, 0xED, 0xFE],
            [0xCA, 0xFE, 0xBA, 0xBE],
        ]
        return magics.contains(values)
    }
}

private struct FlatYAMLDocument {
    let scalars: [String: String]
    let lists: [String: [String]]

    func scalar(
        _ key: String
    ) -> String? {
        scalars[key]
    }

    func list(
        _ key: String
    ) -> [String] {
        lists[key] ?? []
    }

    static func parse(
        _ text: String
    ) throws -> FlatYAMLDocument {
        guard
            text.utf8.count <= 64 * 1_024,
            !text.contains("\t"),
            !text.contains("!!"),
            !text.contains("!<"),
            !text.contains("|\n"),
            !text.contains(">\n")
        else {
            throw CommunitySkillPackageError
                .invalidManifest(
                    "advanced YAML features are not supported"
                )
        }
        let allowedTopLevel:
            Set<String> = [
                "schemaVersion",
                "id",
                "version",
                "name",
                "author",
                "minimumAppVersion",
                "description",
                "homepage",
                "license",
                "triggers",
                "permissions",
                "context",
                "output",
                "validators",
            ]
        var scalars:
            [String: String] = [:]
        var lists:
            [String: [String]] = [:]
        var section: String?
        var subsection: String?
        var listPath: String?

        let lines =
            text.components(
                separatedBy: .newlines
            )
        guard lines.count <= 1_000
        else {
            throw CommunitySkillPackageError
                .invalidManifest(
                    "too many YAML lines"
                )
        }
        for (lineNumber, rawLine) in
            lines.enumerated()
        {
            let trimmed =
                rawLine.trimmingCharacters(
                    in: .whitespaces
                )
            if
                trimmed.isEmpty
                    || trimmed
                        .hasPrefix("#")
            {
                continue
            }
            let indent =
                rawLine.prefix {
                    $0 == " "
                }.count
            guard
                indent == 0
                    || indent == 2
                    || indent == 4
            else {
                throw CommunitySkillPackageError
                    .invalidManifest(
                        "invalid indentation on line \(lineNumber + 1)"
                    )
            }
            if trimmed.hasPrefix("- ") {
                guard
                    let listPath,
                    indent >= 2
                else {
                    throw CommunitySkillPackageError
                        .invalidManifest(
                            "unexpected list on line \(lineNumber + 1)"
                        )
                }
                let listValue =
                    String(
                        trimmed.dropFirst(2)
                    )
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                guard
                    !listValue.hasPrefix("&"),
                    !listValue.hasPrefix("*"),
                    !listValue.hasPrefix("!")
                else {
                    throw CommunitySkillPackageError
                        .invalidManifest(
                            "YAML anchors, aliases, and tags are not supported"
                        )
                }
                lists[listPath, default: []]
                    .append(
                        cleanScalar(
                            listValue
                        )
                    )
                continue
            }
            guard
                let separator =
                    trimmed.firstIndex(
                        of: ":"
                    )
            else {
                throw CommunitySkillPackageError
                    .invalidManifest(
                        "missing ':' on line \(lineNumber + 1)"
                    )
            }
            let key =
                String(
                    trimmed[..<separator]
                )
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
            let rawValue =
                String(
                    trimmed[
                        trimmed.index(
                            after: separator
                        )...
                    ]
                )
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
            guard
                !rawValue.hasPrefix("&"),
                !rawValue.hasPrefix("*"),
                !rawValue.hasPrefix("!")
            else {
                throw CommunitySkillPackageError
                    .invalidManifest(
                        "YAML anchors, aliases, and tags are not supported"
                    )
            }
            guard
                key.range(
                    of:
                        #"^[A-Za-z][A-Za-z0-9]*$"#,
                    options:
                        .regularExpression
                ) != nil
            else {
                throw CommunitySkillPackageError
                    .invalidManifest(
                        "invalid key on line \(lineNumber + 1)"
                    )
            }

            let path: String
            switch indent {
            case 0:
                guard
                    allowedTopLevel
                        .contains(key)
                else {
                    throw CommunitySkillPackageError
                        .invalidManifest(
                            "unknown top-level key \(key)"
                        )
                }
                section = rawValue.isEmpty
                    ? key
                    : nil
                subsection = nil
                path = key
            case 2:
                guard let section else {
                    throw CommunitySkillPackageError
                        .invalidManifest(
                            "orphan key on line \(lineNumber + 1)"
                        )
                }
                subsection =
                    rawValue.isEmpty
                    ? key
                    : nil
                path =
                    "\(section).\(key)"
            default:
                guard
                    let section,
                    let subsection
                else {
                    throw CommunitySkillPackageError
                        .invalidManifest(
                            "orphan nested key on line \(lineNumber + 1)"
                        )
                }
                path =
                    "\(section).\(subsection).\(key)"
            }

            guard
                scalars[path] == nil,
                lists[path] == nil
            else {
                throw CommunitySkillPackageError
                    .invalidManifest(
                        "duplicate key \(path)"
                    )
            }
            if rawValue.isEmpty {
                listPath = path
                continue
            }
            if
                rawValue.hasPrefix("["),
                rawValue.hasSuffix("]")
            {
                let inner =
                    rawValue.dropFirst()
                        .dropLast()
                lists[path] =
                    inner.split(
                        separator: ","
                    ).map {
                        cleanScalar(
                            String($0)
                        )
                    }
                listPath = path
            } else {
                scalars[path] =
                    cleanScalar(rawValue)
                listPath = nil
            }
        }
        let allowedPaths:
            Set<String> = [
                "schemaVersion",
                "id",
                "version",
                "name",
                "author",
                "minimumAppVersion",
                "description",
                "homepage",
                "license",
                "triggers.manual",
                "triggers.defaultForBundleIdentifiers",
                "permissions.required",
                "permissions.optional",
                "context.maximumCharacters",
                "context.includeSelectionOnly",
                "output.format",
                "output.delivery",
                "output.risk",
                "validators.requireNonEmpty",
                "validators.maximumCharacters",
                "validators.preserveTechnicalLiterals",
                "validators.requireClosedMarkdownFences",
                "validators.requiredSections",
                "validators.forbiddenPhrases",
            ]
        let actualPaths =
            Set(scalars.keys)
                .union(lists.keys)
        if
            let unknown =
                actualPaths.first(
                    where: {
                        !allowedPaths
                            .contains($0)
                    }
                )
        {
            throw CommunitySkillPackageError
                .invalidManifest(
                    "unknown declaration \(unknown)"
                )
        }
        return FlatYAMLDocument(
            scalars: scalars,
            lists: lists
        )
    }

    private static func cleanScalar(
        _ value: String
    ) -> String {
        let trimmed =
            value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard trimmed.count >= 2 else {
            return trimmed
        }
        if
            (
                trimmed.hasPrefix("\"")
                    && trimmed.hasSuffix("\"")
            )
                || (
                    trimmed.hasPrefix("'")
                        && trimmed.hasSuffix("'")
                )
        {
            return String(
                trimmed.dropFirst()
                    .dropLast()
            )
        }
        return trimmed
    }
}

private enum SemanticVersion {
    static func compare(
        _ lhs: String,
        _ rhs: String
    ) -> ComparisonResult {
        let left = components(lhs)
        let right = components(rhs)
        for index in 0..<3 {
            if left.numbers[index]
                != right.numbers[index]
            {
                return left.numbers[index]
                    < right.numbers[index]
                    ? .orderedAscending
                    : .orderedDescending
            }
        }
        switch (
            left.prerelease,
            right.prerelease
        ) {
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            return .orderedDescending
        case (_, nil):
            return .orderedAscending
        case let (lhs?, rhs?):
            return lhs.compare(
                rhs,
                options: .numeric
            )
        }
    }

    private static func components(
        _ value: String
    ) -> (
        numbers: [Int],
        prerelease: String?
    ) {
        let segments =
            value.split(
                separator: "-",
                maxSplits: 1,
                omittingEmptySubsequences:
                    false
            )
        var numbers =
            segments[0].split(
                separator: "."
            ).compactMap {
                Int($0)
            }
        while numbers.count < 3 {
            numbers.append(0)
        }
        return (
            Array(numbers.prefix(3)),
            segments.count > 1
                ? String(segments[1])
                : nil
        )
    }
}
