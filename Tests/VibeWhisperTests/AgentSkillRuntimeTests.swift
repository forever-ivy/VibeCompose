import CryptoKit
import Foundation
import Testing
@testable import VibeWhisper

private func agentSkillTestRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    return url
}

@discardableResult
private func writeAgentSkill(
    at root: URL,
    name: String = "portable-writer",
    version: String = "1.2.3",
    allowedTools: String? = nil,
    instructions: String = "Rewrite the transcript as a concise implementation task.",
    profile: String? = nil,
    resources: [String: Data] = [:]
) throws -> URL {
    let directory = root.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    let skill = [
        "---",
        "name: \(name)",
        "description: A portable Agent Skill used by VibeWhisper tests",
        allowedTools.map { "allowed-tools: \($0)" },
        "metadata:",
        "  version: \(version)",
        "  author: Test Publisher",
        "---",
        "",
        instructions,
        "",
    ].compactMap { $0 }.joined(separator: "\n")
    try Data(skill.utf8).write(
        to: directory.appendingPathComponent("SKILL.md")
    )
    if let profile {
        try Data(profile.utf8).write(
            to: directory.appendingPathComponent("vibewhisper.yaml")
        )
    }
    for (relativePath, data) in resources {
        let url = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }
    return directory
}

private func createSkillArchive(
    source: URL,
    destination: URL
) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = [
        "-c", "-k", "--keepParent", source.path, destination.path,
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CommunitySkillPackageError.invalidPackage("test archive failed")
    }
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

@Test
func standardAgentSkillLoadsWithPortableSafeDefaults() throws {
    let root = try agentSkillTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = try writeAgentSkill(at: root)

    let package = try AgentSkillPackageLoader().load(from: url)
    let normalized = try AgentSkillNormalizer().normalize(package: package)

    #expect(normalized.format == .agentSkillsStandard)
    #expect(normalized.compatibility.level == .portable)
    #expect(normalized.compatibility.runtimeStatus == .compatible)
    #expect(normalized.profile == .safeDefault)
    #expect(normalized.definition.output.delivery == .previewThenPaste)
    #expect(normalized.installation.portableName == "portable-writer")
}

@Test
func standardSkillResourcesAreBoundAfterInstructionsAndScriptsStayQuarantined()
    throws
{
    let root = try agentSkillTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let profile = """
    context:
      required: [voice]
      optional: [selection]
    resources:
      references: [references/format.md]
    output:
      format: markdown
      delivery: previewThenPaste
      risk: medium
    validators:
      requireNonEmpty: true
      maximumCharacters: 8000
    """
    let url = try writeAgentSkill(
        at: root,
        profile: profile,
        resources: [
            "references/format.md": Data("Use headings: Goal and Tests.".utf8),
            "scripts/build.sh": Data("#!/bin/sh\necho blocked\n".utf8),
        ]
    )
    let package = try AgentSkillPackageLoader().load(from: url)
    let normalized = try AgentSkillNormalizer().normalize(package: package)

    #expect(normalized.compatibility.runtimeStatus == .compatible)
    #expect(normalized.compatibility.level == .vendorExtended)
    #expect(
        normalized.compatibility.quarantinedResources
            == ["scripts/build.sh"]
    )
    #expect(normalized.resources.map(\.descriptor.relativePath) == ["references/format.md"])

    let plan = ResolvedSkillExecutionPlan(
        skill: normalized.definition,
        source: .manual,
        matchedApplicationRuleID: nil,
        installation: normalized.installation,
        package: normalized.package,
        profile: normalized.profile,
        resources: normalized.resources
    )
    let prompt = SkillPromptCompiler().compile(
        transcript: "Implement it",
        terminologyEntries: [],
        config: TextPolishConfig(),
        plan: plan
    )[0].content
    let skill = try #require(prompt.range(of: SkillPromptCompiler.skillMarker))
    let resources = try #require(prompt.range(of: SkillPromptCompiler.resourcesMarker))
    #expect(skill.lowerBound < resources.lowerBound)
    #expect(prompt.contains("Use headings: Goal and Tests."))
    #expect(!prompt.contains("echo blocked"))
}

@Test
func toolOrExecutableDependentStandardSkillsInstallButCannotActivate() throws {
    let root = try agentSkillTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let toolURL = try writeAgentSkill(
        at: root,
        name: "tool-dependent",
        allowedTools: "Shell",
        resources: ["scripts/run.sh": Data("#!/bin/sh\n".utf8)]
    )
    let executableURL = try writeAgentSkill(
        at: root,
        name: "script-dependent",
        instructions: "Run the script scripts/run.sh before writing output.",
        resources: ["scripts/run.sh": Data("#!/bin/sh\n".utf8)]
    )
    let support = root.appendingPathComponent("Support", isDirectory: true)
    let store = SkillPackageStore(applicationSupportURL: support)

    let tool = try store.install(from: toolURL)
    let executable = try store.install(from: executableURL)
    #expect(tool.compatibility.level == .toolDependent)
    #expect(executable.compatibility.level == .executableDependent)
    #expect(tool.compatibility.runtimeStatus == .incompatible)
    #expect(executable.compatibility.runtimeStatus == .incompatible)
    #expect(!tool.isActive)
    #expect(!executable.isActive)
    #expect(store.loadInventory(config: .init()).activeDefinitions.isEmpty)
}

@Test
func openWhisperProfileRejectsUnknownNestedKeys() throws {
    let root = try agentSkillTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = try writeAgentSkill(
        at: root,
        profile: """
        context:
          required: [voice]
          arbitraryRead: true
        """
    )
    let package = try AgentSkillPackageLoader().load(from: url)
    #expect(throws: AgentSkillPackageError.self) {
        try AgentSkillNormalizer().normalize(package: package)
    }
}

@Test
func standardSkillZipUsesTheSameScannerAndPrivateInstallationStore() throws {
    let root = try agentSkillTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try writeAgentSkill(at: root, name: "archive-writer")
    let archive = root.appendingPathComponent("archive-writer.zip")
    try createSkillArchive(source: source, destination: archive)
    let store = SkillPackageStore(
        applicationSupportURL: root.appendingPathComponent("Support")
    )

    let inspected = try store.inspect(packageURL: archive)
    let installed = try store.install(from: archive)

    #expect(inspected.format == .agentSkillsStandard)
    #expect(installed.contentSHA256 == inspected.contentSHA256)
    #expect(installed.packageURL.path.contains("Skills/Installed"))
    let attributes = try FileManager.default.attributesOfItem(
        atPath: installed.packageURL.appendingPathComponent("SKILL.md").path
    )
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test
func skillCreatorExportsAReimportableStandardPackage() throws {
    let root = try agentSkillTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var draft = SkillCreatorDraft.template(.codingPrompt)
    draft.references["format.md"] = "Use Goal, Constraints, and Acceptance Criteria."
    draft.goldenCasesJSONL =
        ##"{"transcript":"Build it","expectedOutput":"# Goal\nBuild it"}"##
    let creator = SkillCreator()
    let report = creator.validate(draft)
    #expect(report.isValid)

    let destination = root.appendingPathComponent("Exported", isDirectory: true)
    let exported = try creator.export(draft, to: destination)
    let reimported = try AgentSkillPackageLoader().load(from: destination)
    #expect(exported.contentSHA256 == reimported.contentSHA256)
    #expect(reimported.resources.contains { $0.relativePath == "references/format.md" })
    #expect(reimported.resources.contains { $0.relativePath == "tests/golden.jsonl" })
}

@Test
func collectionsRemainDiscoveryMetadataAndDoNotMergeSkillIdentity() {
    let first = UUID()
    let second = UUID()
    let collection = SkillCollection(
        name: "Developer Pack",
        summary: "Two independent Skills",
        category: "Development",
        items: [
            SkillCollectionItem(installationID: first, portableName: "one"),
            SkillCollectionItem(installationID: second, portableName: "two"),
            SkillCollectionItem(installationID: first, portableName: "duplicate"),
        ]
    )
    #expect(collection.items.count == 2)
    #expect(Set(collection.items.map(\.installationID)) == [first, second])
}

@Test
func signedRegistryVerifiesCachesInstallsAndPreservesSignedIdentity() async throws {
    let root = try agentSkillTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let sourceDirectory = try writeAgentSkill(at: root, name: "registry-writer")
    let standardPackage = try AgentSkillPackageLoader().load(from: sourceDirectory)
    let archiveURL = root.appendingPathComponent("registry-writer.zip")
    try createSkillArchive(source: sourceDirectory, destination: archiveURL)
    let archiveData = try Data(contentsOf: archiveURL)

    let indexURL = URL(string: "https://registry.example/index.json")!
    let remoteArchiveURL = URL(string: "https://registry.example/registry-writer.zip")!
    let privateKey = Curve25519.Signing.PrivateKey()
    let source = TrustedSkillRegistrySource(
        name: "Test Registry",
        indexURL: indexURL,
        publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString(),
        isEnabled: true,
        teamAllowlistedPublisherIDs: ["publisher.test"]
    )
    let registryPackage = TrustedSkillRegistryPackage(
        packageID: "registry.test.writer",
        portableName: "registry-writer",
        version: "1.2.3",
        revision: "revision-1",
        publisherID: "publisher.test",
        archiveURL: remoteArchiveURL,
        archiveSHA256: sha256(archiveData),
        contentSHA256: standardPackage.contentSHA256,
        minimumAppVersion: "0.1.0",
        isRevoked: false,
        replacesRevision: nil
    )
    let index = TrustedSkillRegistryIndex(
        schemaVersion: 1,
        registryID: "registry.test",
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        keyID: "test-key-1",
        packages: [registryPackage],
        collections: [],
        revokedRevisions: []
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let indexData = try encoder.encode(index)
    let signature = try privateKey.signature(for: indexData)
    let responses: [URL: Data] = [
        indexURL: indexData,
        indexURL.appendingPathExtension("sig"): signature,
        remoteArchiveURL: archiveData,
    ]
    let client = TrustedSkillRegistryClient(
        applicationSupportURL: root.appendingPathComponent("Support"),
        fetch: { url in
            guard let data = responses[url] else {
                throw TrustedSkillRegistryError.transport("missing fixture")
            }
            return data
        }
    )
    let store = SkillPackageStore(
        applicationSupportURL: root.appendingPathComponent("Support")
    )
    let installed = try await client.install(
        packageID: registryPackage.packageID,
        source: source,
        remoteRegistryEnabled: true,
        store: store
    )
    #expect(installed.installation.packageID == registryPackage.packageID)
    #expect(installed.installation.revision == registryPackage.revision)
    #expect(installed.installation.publisher == registryPackage.publisherID)

    let reloaded = try #require(
        store.loadInventory(config: .init()).packages.first
    )
    #expect(reloaded.installation == installed.installation)

    var tampered = indexData
    tampered.append(0x20)
    #expect(throws: TrustedSkillRegistryError.self) {
        try TrustedSkillRegistryVerifier().verify(
            indexData: tampered,
            signature: signature,
            source: source
        )
    }
}

@Test
func contextReceiptsAndSerializedPlansNeverPersistContextText() throws {
    let plan = ResolvedSkillExecutionPlan.direct
    let secret = "private selected text"
    let snapshot = ContextSnapshot(
        installationID: plan.installation.id,
        items: [
            ContextSnapshotItem(
                source: .selection,
                content: secret,
                contentSHA256: SelectionContextSnapshot.digest(for: secret)
            ),
        ]
    )
    let receipt = ContextReceipt.from(
        request: ContextRequest(optional: [.selection]),
        snapshot: snapshot
    )
    let receiptJSON = String(
        data: try JSONEncoder().encode(receipt),
        encoding: .utf8
    ) ?? ""
    #expect(!receiptJSON.contains(secret))
    #expect(receipt.characterCounts["selection"] == secret.count)

    let frozen = plan.freezing(contextSnapshot: snapshot)
    let planJSON = String(
        data: try JSONEncoder().encode(frozen),
        encoding: .utf8
    ) ?? ""
    #expect(!planJSON.contains(secret))
    #expect(!planJSON.contains("contextSnapshot"))
}
