import Foundation
import Testing
@testable import VibeCompose

@Test
func configStoreMigratesPreRenameConfigAndLeavesRollbackCopyIntact() throws {
    let fixture = try ProductDataMigrationFixture()
    defer { fixture.remove() }

    var legacyConfig = AppConfig()
    legacyConfig.appLanguage = .english
    legacyConfig.transcription.hintTerms = ["legacy-term"]
    try fixture.writeConfig(legacyConfig, to: fixture.legacyDirectoryURL)

    let loaded = try fixture.store.load()

    #expect(loaded.appLanguage == .english)
    #expect(loaded.transcription.hintTerms == ["legacy-term"])
    #expect(
        FileManager.default.fileExists(
            atPath: fixture.legacyDirectoryURL
                .appendingPathComponent("config.json").path
        )
    )
    #expect(
        FileManager.default.fileExists(
            atPath: fixture.markerURL.path
        )
    )
    #expect(try fixture.permissions(of: fixture.store.directoryURL) == 0o700)
    #expect(try fixture.permissions(of: fixture.store.configURL) == 0o600)
    #expect(try fixture.permissions(of: fixture.markerURL) == 0o600)
}

@Test
func configStoreMergesPreRenameConfigWithoutOverwritingCurrentChoices() throws {
    let fixture = try ProductDataMigrationFixture()
    defer { fixture.remove() }

    var legacyConfig = AppConfig()
    legacyConfig.appLanguage = .english
    legacyConfig.transcription.hintTerms = ["legacy-term"]
    legacyConfig.transcription.feedbackSoundsEnabled = false
    try fixture.writeConfig(legacyConfig, to: fixture.legacyDirectoryURL)

    var currentConfig = AppConfig()
    currentConfig.appLanguage = .simplifiedChinese
    currentConfig.privacy.historyEnabled = false
    try fixture.writeConfig(currentConfig, to: fixture.store.directoryURL)

    let loaded = try fixture.store.load()

    #expect(loaded.appLanguage == .simplifiedChinese)
    #expect(loaded.privacy.historyEnabled == false)
    #expect(loaded.transcription.hintTerms == ["legacy-term"])
    #expect(loaded.transcription.feedbackSoundsEnabled == false)
}

@Test
func configStoreCanonicalizesPreRenameBuiltInSkillReferencesAfterMarkerExists() throws {
    let fixture = try ProductDataMigrationFixture()
    defer { fixture.remove() }

    let currentSkillID = SkillRegistry.codePromptSkillID
    let preRenameSkillID = preRenameBuiltInSkillID(for: currentSkillID)
    let preRenameDirectSkillID = preRenameBuiltInSkillID(
        for: SkillRegistry.directSkillID
    )
    let currentDefinition = try #require(
        SkillRegistry.builtIn.definition(id: currentSkillID)
    )
    let currentInstallationID = InstalledSkillIdentity.normalized(
        definition: currentDefinition,
        sourceID: "builtin"
    ).id
    let preRenameInstallationID = StableIdentifier.uuid(
        namespace: "\(LegacyProductIdentity.name).InstalledSkillIdentity",
        components: [
            "builtin",
            nil,
            preRenameSkillID,
            "1.0.0",
        ]
    )
    let preRenameRuleInstallationID = StableIdentifier.uuid(
        namespace: "\(LegacyProductIdentity.name).AppSkillRule.Installation",
        components: [preRenameSkillID]
    )
    let customSkillID = "com.example.skill.custom"
    let customInstallationID = try #require(
        UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")
    )
    let capsuleID = try #require(StyleCapsuleRegistry.builtIn.first?.id)

    var config = AppConfig()
    config.transcription.skills.defaultSkillID = preRenameSkillID
    config.transcription.skills.defaultSkillInstallationID =
        preRenameInstallationID
    config.transcription.skills.enabledSkillIDs = [
        SkillRegistry.directSkillID,
        preRenameDirectSkillID,
        preRenameSkillID,
        customSkillID,
    ]
    config.transcription.skills.applicationRules = [
        AppSkillRule(
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            skillID: preRenameSkillID,
            skillInstallationID: preRenameRuleInstallationID
        ),
    ]
    config.context.permissionGrants = [
        SkillPermissionGrant(
            skillID: preRenameSkillID,
            capability: .selection,
            scope: .alwaysAllow
        ),
        SkillPermissionGrant(
            skillID: customSkillID,
            capability: .selection,
            scope: .denied
        ),
    ]
    config.context.recentReceipts = [
        ContextReceipt(
            sessionID: UUID(),
            installationID: preRenameRuleInstallationID,
            requestedSources: [.selection],
            grantedSources: [.selection],
            deniedSources: [],
            characterCounts: [ContextSourceKind.selection.rawValue: 42]
        ),
    ]
    config.styleCapsules.skillAssignments = [
        StyleCapsuleAssignment(
            skillID: preRenameSkillID,
            capsuleID: capsuleID
        ),
        StyleCapsuleAssignment(
            skillID: customSkillID,
            capsuleID: capsuleID
        ),
    ]
    config.communitySkills.activeVersions = [
        CommunitySkillVersionSelection(
            skillID: preRenameSkillID,
            version: "1.0.0"
        ),
        CommunitySkillVersionSelection(
            skillID: customSkillID,
            version: "2.0.0"
        ),
    ]
    config.skillEcosystem.favoriteInstallationIDs = [
        preRenameInstallationID,
        currentInstallationID,
        customInstallationID,
    ]
    config.skillEcosystem.recentInstallationIDs = [
        preRenameRuleInstallationID,
        currentInstallationID,
        customInstallationID,
    ]
    config.skillEcosystem.collections = [
        SkillCollection(
            name: "Writing",
            summary: "Built-in and custom Skills",
            category: "Productivity",
            items: [
                SkillCollectionItem(
                    installationID: preRenameInstallationID,
                    portableName: "Code Prompt"
                ),
                SkillCollectionItem(
                    installationID: currentInstallationID,
                    portableName: "Code Prompt"
                ),
                SkillCollectionItem(
                    installationID: customInstallationID,
                    portableName: "Custom"
                ),
            ]
        ),
    ]
    try fixture.writeConfig(config, to: fixture.store.directoryURL)
    try fixture.write(
        "{}",
        relativePath: ProductDataMigration.markerFileName,
        under: fixture.store.directoryURL
    )

    let loaded = try fixture.store.load()

    #expect(loaded.transcription.skills.defaultSkillID == currentSkillID)
    #expect(
        loaded.transcription.skills.defaultSkillInstallationID
            == currentInstallationID
    )
    #expect(
        loaded.transcription.skills.enabledSkillIDs == [
            SkillRegistry.directSkillID,
            currentSkillID,
            customSkillID,
        ]
    )
    #expect(loaded.transcription.skills.applicationRules.count == 1)
    #expect(
        loaded.transcription.skills.applicationRules.first?.skillID
            == currentSkillID
    )
    #expect(
        loaded.transcription.skills.applicationRules.first?
            .skillInstallationID == currentInstallationID
    )
    #expect(
        loaded.context.permissionGrants.map(\.skillID) == [
            currentSkillID,
            customSkillID,
        ]
    )
    #expect(
        loaded.context.recentReceipts.first?.installationID
            == currentInstallationID
    )
    #expect(
        loaded.styleCapsules.skillAssignments.map(\.skillID) == [
            currentSkillID,
            customSkillID,
        ]
    )
    #expect(
        loaded.communitySkills.activeVersions.map(\.skillID) == [
            currentSkillID,
            customSkillID,
        ]
    )
    #expect(
        Set(loaded.skillEcosystem.favoriteInstallationIDs) == [
            currentInstallationID,
            customInstallationID,
        ]
    )
    #expect(
        loaded.skillEcosystem.recentInstallationIDs == [
            currentInstallationID,
            customInstallationID,
        ]
    )
    let collectionItems = try #require(
        loaded.skillEcosystem.collections.first?.items
    )
    #expect(collectionItems.count == 2)
    #expect(
        Set(collectionItems.map(\.installationID)) == [
            currentInstallationID,
            customInstallationID,
        ]
    )

    let firstCanonicalData = try Data(contentsOf: fixture.store.configURL)
    let loadedAgain = try fixture.store.load()
    let secondCanonicalData = try Data(contentsOf: fixture.store.configURL)
    #expect(loadedAgain == loaded)
    #expect(secondCanonicalData == firstCanonicalData)
}

@Test
func configStoreMergesJSONLAndCopiesMissingPreRenameSkillFiles() throws {
    let fixture = try ProductDataMigrationFixture()
    defer { fixture.remove() }

    try fixture.write(
        """
        {"id":"old"}
        {"id":"shared"}
        """,
        relativePath: "transcription-history.jsonl",
        under: fixture.legacyDirectoryURL
    )
    try fixture.write(
        """
        {"id":"shared"}
        {"id":"new"}
        """,
        relativePath: "transcription-history.jsonl",
        under: fixture.store.directoryURL
    )
    try fixture.write(
        "legacy instructions",
        relativePath: "Skills/Installed/example/SKILL.md",
        under: fixture.legacyDirectoryURL
    )
    try fixture.write(
        "legacy resource",
        relativePath: "Skills/Installed/example/reference.txt",
        under: fixture.legacyDirectoryURL
    )
    try fixture.write(
        "current instructions",
        relativePath: "Skills/Installed/example/SKILL.md",
        under: fixture.store.directoryURL
    )

    _ = try fixture.store.load()

    let mergedHistory = try String(
        contentsOf: fixture.store.directoryURL
            .appendingPathComponent("transcription-history.jsonl"),
        encoding: .utf8
    )
    #expect(
        mergedHistory.split(separator: "\n").map(String.init) == [
            #"{"id":"old"}"#,
            #"{"id":"shared"}"#,
            #"{"id":"new"}"#,
        ]
    )
    #expect(
        try fixture.read(
            relativePath: "Skills/Installed/example/SKILL.md",
            under: fixture.store.directoryURL
        ) == "current instructions"
    )
    #expect(
        try fixture.read(
            relativePath: "Skills/Installed/example/reference.txt",
            under: fixture.store.directoryURL
        ) == "legacy resource"
    )

    try fixture.write(
        #"{"id":"late"}"#,
        relativePath: "transcription-history.jsonl",
        under: fixture.legacyDirectoryURL,
        append: true
    )
    _ = try fixture.store.load()
    let afterSecondLoad = try String(
        contentsOf: fixture.store.directoryURL
            .appendingPathComponent("transcription-history.jsonl"),
        encoding: .utf8
    )
    #expect(!afterSecondLoad.contains(#""late""#))
}

@Test
func configStoreNeverFollowsSymlinkedPreRenameContainer() throws {
    let fixture = try ProductDataMigrationFixture(createLegacyDirectory: false)
    defer { fixture.remove() }
    let outsideDirectory = fixture.rootURL
        .appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(
        at: outsideDirectory,
        withIntermediateDirectories: true
    )
    try fixture.write(
        """
        {
          "transcription": {
            "hintTerms": ["must-not-import"]
          }
        }
        """,
        relativePath: "config.json",
        under: outsideDirectory
    )
    try FileManager.default.createDirectory(
        at: fixture.legacyDirectoryURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
        at: fixture.legacyDirectoryURL,
        withDestinationURL: outsideDirectory
    )

    let loaded = try fixture.store.load()

    #expect(loaded.transcription.hintTerms.isEmpty)
    #expect(
        !FileManager.default.fileExists(
            atPath: fixture.store.directoryURL
                .appendingPathComponent("outside").path
        )
    )
    #expect(
        !FileManager.default.fileExists(
            atPath: fixture.markerURL.path
        )
    )
}

private func preRenameBuiltInSkillID(for currentSkillID: String) -> String {
    let currentPrefix = "app.\(ProductIdentity.slug).skill."
    let preRenamePrefix = LegacyProductIdentity.defaultBundleIdentifier
        .replacingOccurrences(of: ".mac", with: ".skill.")
    precondition(currentSkillID.hasPrefix(currentPrefix))
    return preRenamePrefix + currentSkillID.dropFirst(currentPrefix.count)
}

private struct ProductDataMigrationFixture {
    let rootURL: URL
    let legacyDirectoryURL: URL
    let store: ConfigStore

    init(createLegacyDirectory: Bool = true) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "VibeComposeDataMigration-\(UUID().uuidString)",
                isDirectory: true
            )
        rootURL = root
        store = ConfigStore(
            fileManager: .default,
            homeDirectoryURL: root
        )
        legacyDirectoryURL = root
            .appendingPathComponent(
                "Library/Application Support",
                isDirectory: true
            )
            .appendingPathComponent(
                ["Vibe", "Whisper"].joined(),
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        if createLegacyDirectory {
            try FileManager.default.createDirectory(
                at: legacyDirectoryURL,
                withIntermediateDirectories: true
            )
        }
    }

    var markerURL: URL {
        store.directoryURL.appendingPathComponent(
            ".identity-migration-v1.json"
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func writeConfig(_ config: AppConfig, to directoryURL: URL) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(
            to: directoryURL.appendingPathComponent("config.json"),
            options: [.atomic]
        )
    }

    func write(
        _ value: String,
        relativePath: String,
        under directoryURL: URL,
        append: Bool = false
    ) throws {
        let url = directoryURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = Data((value + "\n").utf8)
        if append, FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
    }

    func read(relativePath: String, under directoryURL: URL) throws -> String {
        try String(
            contentsOf: directoryURL.appendingPathComponent(relativePath),
            encoding: .utf8
        ).trimmingCharacters(in: .newlines)
    }

    func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
