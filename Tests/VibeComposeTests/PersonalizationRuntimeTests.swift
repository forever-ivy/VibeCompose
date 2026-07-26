import Foundation
import Testing
@testable import VibeCompose

@Test
func styleCapsuleStoreRoundTripsDeletesAndKeepsSourceSamplesOut()
    throws
{
    let root = FileManager.default
        .temporaryDirectory
        .appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
    defer {
        try? FileManager.default
            .removeItem(at: root)
    }
    let store = StyleCapsuleStore(
        applicationSupportURL: root
    )
    let samples =
        """
        Ship the smallest safe change.
        - Preserve API v2.
        - Add a regression test.
        """
    let summary =
        StyleCapsuleAnalyzer.summarize(
            samples: samples
        )
    let capsule = StyleCapsule(
        id: "user.release-notes",
        name: "Release Notes",
        summary: summary,
        examples: []
    )

    try store.save(capsule)
    let loaded = try #require(
        store.loadCustom().first
    )
    #expect(loaded == capsule)
    #expect(!loaded.promptText.contains(samples))

    let attributes =
        try FileManager.default
            .attributesOfItem(
                atPath:
                    store.rootURL
                        .appendingPathComponent(
                            "user.release-notes.json"
                        ).path
            )
    #expect(
        (attributes[.posixPermissions]
            as? NSNumber)?.intValue
            == 0o600
    )

    try store.delete(
        id: capsule.id
    )
    #expect(
        try store.loadCustom()
            .isEmpty
    )
}

@Test
func styleCapsuleResolverRequiresSkillCapabilityAndAssignment()
{
    let capsule =
        StyleCapsuleRegistry
            .builtIn[0]
    var config = StyleCapsuleConfig(
        defaultCapsuleID:
            capsule.id
    )
    let direct = SkillRegistry.builtIn
        .definition(
            id:
                SkillRegistry.directSkillID
        )!
    let email = SkillRegistry.builtIn
        .definition(
            id:
                SkillRegistry.emailSkillID
        )!

    #expect(
        StyleCapsuleResolver()
            .resolve(
                config: config,
                available:
                    StyleCapsuleRegistry
                        .builtIn,
                skill: direct
            ) == nil
    )
    #expect(
        StyleCapsuleResolver()
            .resolve(
                config: config,
                available:
                    StyleCapsuleRegistry
                        .builtIn,
                skill: email
            )?.id == capsule.id
    )

    config.setCapsuleID(
        StyleCapsuleRegistry
            .teamChatID,
        for: email.id
    )
    #expect(
        StyleCapsuleResolver()
            .resolve(
                config: config,
                available:
                    StyleCapsuleRegistry
                        .builtIn,
                skill: email
            )?.id
            == StyleCapsuleRegistry
                .teamChatID
    )
}

@Test
func terminologyPacksReportConflictsAndEnforcePriority()
{
    let personalTerm =
        TerminologyEntry(
            canonical: "Postgres",
            aliases: ["post gres"],
            source: "user"
        )
    let correction =
        TerminologyEntry(
            type: .correction,
            original: "open api",
            replacement: "UserOpenAPI",
            aliases: [],
            isEnabled: true,
            source: "user",
            usageCount: 0,
            createdAt:
                "2026-07-14T00:00:00Z"
        )
    let skill = SkillDefinition(
        id: "com.example.skill.backend",
        version: "1.0.0",
        name: "Backend",
        terminologyEntries: [
            TerminologyEntry(
                canonical: "SkillOpenAPI",
                aliases: ["open api"],
                source: "skill"
            ),
        ],
        promptInstruction:
            "Keep backend terms exact.",
        output: SkillOutputContract(
            format: .plainText,
            delivery: .previewThenPaste,
            risk: .medium
        )
    )
    let resolved =
        TerminologyPackResolver()
            .resolve(
                personalEntries: [
                    personalTerm,
                    correction,
                ],
                config:
                    TerminologyPackConfig(
                        enabledPackIDs: [
                            TerminologyPackRegistry
                                .backendID,
                            TerminologyPackRegistry
                                .medicalID,
                        ]
                    ),
                skill: skill
            )

    #expect(
        resolved.enabledPackIDs
            == [
                TerminologyPackRegistry
                    .backendID,
                TerminologyPackRegistry
                    .medicalID,
            ]
    )
    #expect(
        resolved.maximumRisk == .high
    )
    #expect(
        resolved.entries.first?.type
            == .correction
    )

    let normalized =
        TerminologyNormalizer().normalize(
            text: "open api",
            importedEntries:
                resolved.entries,
            hintTerms: []
        )
    #expect(
        normalized.text
            == "UserOpenAPI"
    )
}

@Test
func medicalPackForcesPreviewWithoutChangingSkillContract()
{
    let plan =
        SkillResolver().resolve(
            manualSkillID:
                SkillRegistry.directSkillID,
            config: SkillsConfig(),
            launchAppContext: nil
        )
    let route =
        OutputRouter().route(
            plan: plan,
            automaticPasteAllowed: true,
            hasSelectionContext: false,
            additionalRisk: .high
        )
    #expect(route == .preview)
}

@Test
func personalizationConfigurationRoundTripsButFrozenAssetsDoNot()
    throws
{
    var config = AppConfig()
    config.styleCapsules =
        StyleCapsuleConfig(
            defaultCapsuleID:
                StyleCapsuleRegistry
                    .technicalWritingID
        )
    config.terminologyPacks =
        TerminologyPackConfig(
            enabledPackIDs: [
                TerminologyPackRegistry
                    .kubernetesID,
            ]
        )
    config.transcription
        .resolvedTerminologyPackIDs = [
            "temporary",
        ]
    config.transcription
        .resolvedTerminologyRisk = .high
    config.transcription
        .resolvedStyleCapsuleID =
        "temporary"

    let data = try JSONEncoder()
        .encode(config)
    let object =
        try #require(
            JSONSerialization
                .jsonObject(with: data)
                as? [String: Any]
        )
    let transcription =
        try #require(
            object["transcription"]
                as? [String: Any]
        )
    #expect(
        transcription[
            "resolvedTerminologyPackIDs"
        ] == nil
    )
    #expect(
        transcription[
            "resolvedStyleCapsuleID"
        ] == nil
    )

    let decoded =
        try JSONDecoder().decode(
            AppConfig.self,
            from: data
        )
    #expect(
        decoded.styleCapsules
            == config.styleCapsules
    )
    #expect(
        decoded.terminologyPacks
            == config.terminologyPacks
    )
    #expect(
        decoded.transcription
            .resolvedTerminologyPackIDs
            .isEmpty
    )
    #expect(
        decoded.transcription
            .resolvedTerminologyRisk
            == .low
    )
}
