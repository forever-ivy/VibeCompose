import ApplicationServices
import Foundation
import Testing
@testable import VibeWhisper

@Test
func ordinaryContextSettingsExposeOnlyAvailableSources() {
    let visible = ContextSourceKind
        .userVisibleSettingsSources

    #expect(!visible.isEmpty)
    #expect(
        visible.allSatisfy {
            $0.isAvailableInCurrentRuntime
        }
    )
    #expect(visible.contains(.voice))
    #expect(visible.contains(.selection))
    #expect(!visible.contains(.focusedParagraph))
    #expect(!visible.contains(.openFile))
    #expect(!visible.contains(.terminalSession))
    #expect(!visible.contains(.browserPage))
    #expect(!visible.contains(.clipboard))
}

@Test
func contextReceiptRecordsRedactedPerSourceDecisions() throws {
    let installationID = UUID()
    let sessionID = UUID()
    let request = ContextRequest(
        required: [.voice, .selection],
        optional: [.focusedParagraph, .styleCapsule]
    )
    let selection = ContextSnapshotItem(
        source: .selection,
        content: "selected text",
        contentSHA256: SelectionContextSnapshot.digest(
            for: "selected text"
        )
    )
    let snapshot = ContextSnapshot(
        sessionID: sessionID,
        installationID: installationID,
        items: [selection]
    )
    let receipt = ContextReceipt.from(
        request: request,
        snapshot: snapshot,
        deniedSources: [.styleCapsule],
        unavailableSources: [.focusedParagraph]
    )

    let bySource = Dictionary(
        uniqueKeysWithValues: receipt.decisions.map {
            ($0.source, $0)
        }
    )
    #expect(bySource[.voice]?.decisionCode == "granted")
    #expect(bySource[.selection]?.decisionCode == "granted")
    #expect(bySource[.focusedParagraph]?.decisionCode == "unavailable")
    #expect(bySource[.styleCapsule]?.decisionCode == "denied")
    #expect(bySource[.selection]?.characterCount == "selected text".count)
    #expect(receipt.deniedSources.contains(.focusedParagraph))
    #expect(receipt.deniedSources.contains(.styleCapsule))

    let data = try JSONEncoder().encode(receipt)
    let decoded = try JSONDecoder().decode(ContextReceipt.self, from: data)
    #expect(decoded.decisions == receipt.decisions)
    #expect(!String(decoding: data, as: UTF8.self).contains("selected text"))
}

@MainActor
private final class FakeContextPermissionPrompter:
    ContextPermissionPrompting
{
    var choice:
        ContextAuthorizationChoice
    private(set) var requests:
        [ContextPermissionRequest] = []

    init(
        choice:
            ContextAuthorizationChoice
    ) {
        self.choice = choice
    }

    func requestPermission(
        _ request:
            ContextPermissionRequest
    ) async -> ContextAuthorizationChoice {
        requests.append(request)
        return choice
    }
}

private func contextTestTarget()
    -> FocusedAXElementReference
{
    let element =
        AXUIElementCreateSystemWide()
    return FocusedAXElementReference(
        processIdentifier: 42,
        element: element,
        window: nil,
        identity:
            FocusedTargetIdentity(
                elementHash: 42,
                role: "AXTextArea",
                subrole: nil,
                identifier: "editor",
                windowHash: nil
            )
    )
}

private func contextTestSnapshot()
    -> SelectionContextSnapshot
{
    contextTestSnapshot(
        text: "Keep API v2 and 2026-07-14."
    )
}

private func contextTestSnapshot(
    text: String
) -> SelectionContextSnapshot {
    return SelectionContextSnapshot(
        target: contextTestTarget(),
        selectedRange:
            CFRange(
                location: 0,
                length:
                    (text as NSString)
                        .length
            ),
        selectedText: text,
        textDigest:
            SelectionContextSnapshot
                .digest(for: text)
    )
}

@Test
func contextConfigBoundsAndDeduplicatesPermissionGrants()
    throws
{
    let config = ContextConfig(
        maximumSelectionCharacters:
            100_000,
        permissionGrants: [
            SkillPermissionGrant(
                skillID:
                    SkillRegistry
                        .contextRewriteSkillID,
                capability: .selection,
                scope: .alwaysAllow
            ),
            SkillPermissionGrant(
                skillID:
                    SkillRegistry
                        .contextRewriteSkillID,
                capability: .selection,
                scope: .denied
            ),
            SkillPermissionGrant(
                skillID: "bad id",
                capability: .selection,
                scope: .alwaysAllow
            ),
            SkillPermissionGrant(
                skillID:
                    SkillRegistry
                        .contextReplySkillID,
                capability: .voice,
                scope: .alwaysAllow
            ),
        ]
    )

    #expect(
        config.maximumSelectionCharacters
            == 20_000
    )
    #expect(
        config.permissionGrants.count
            == 1
    )
    #expect(
        config.scope(
            skillID:
                SkillRegistry
                    .contextRewriteSkillID,
            capability: .selection
        ) == .alwaysAllow
    )

    var appConfig = AppConfig()
    appConfig.context = config
    let data = try JSONEncoder()
        .encode(appConfig)
    let decoded = try JSONDecoder()
        .decode(
            AppConfig.self,
            from: data
        )
    #expect(decoded.context == config)
}

@MainActor
@Test
func contextBrokerReadsSelectionOnlyAfterExplicitPermission()
    async
{
    let snapshot =
        contextTestSnapshot()
    var captureCount = 0
    let provider =
        SelectionContextProvider(
            capture: { _, _ in
                captureCount += 1
                return .captured(
                    snapshot
                )
            },
            verify: { _ in
                .unchanged
            }
        )
    let prompter =
        FakeContextPermissionPrompter(
            choice: .allowOnce
        )
    let plan =
        SkillResolver().resolve(
            manualSkillID:
                SkillRegistry
                    .contextRewriteSkillID,
            config: SkillsConfig(),
            launchAppContext: nil
        )

    let prepared =
        await ContextBroker(
            selectionProvider:
                provider
        ).prepare(
            plan: plan,
            launchAppContext:
                LaunchAppContext(
                    bundleIdentifier:
                        "com.apple.TextEdit",
                    localizedName:
                        "TextEdit",
                    processIdentifier: 42,
                    focusedTarget:
                        snapshot.target
                ),
            contextConfig:
                ContextConfig(),
            privacyConfig:
                PrivacyConfig(),
            permissionPrompter:
                prompter
        )

    #expect(
        prompter.requests.count == 1
    )
    #expect(captureCount == 1)
    #expect(
        prepared.reason == .captured
    )
    #expect(prepared.blocksExecution == false)
    #expect(
        prepared.promptContext
            .selection
            == snapshot.selectedText
    )
    #expect(
        prepared
            .persistentGrant == nil
    )
}

@MainActor
@Test
func builtInSelectionSkillsReceiveTheCapturedSelection()
    async
{
    let selectedText =
        "Please keep API v2 available until 2026-08-01."
    let snapshot = contextTestSnapshot(
        text: selectedText
    )
    let provider = SelectionContextProvider(
        capture: { _, _ in .captured(snapshot) },
        verify: { _ in .unchanged }
    )

    for skillID in [
        SkillRegistry.contextReplySkillID,
        SkillRegistry.contextRewriteSkillID,
    ] {
        let plan = SkillResolver().resolve(
            manualSkillID: skillID,
            config: SkillsConfig(),
            launchAppContext: nil
        )
        var config = ContextConfig()
        config.setScope(
            .alwaysAllow,
            skillID: skillID,
            capability: .selection
        )

        let prepared = await ContextBroker(
            selectionProvider: provider
        ).prepare(
            plan: plan,
            launchAppContext: nil,
            contextConfig: config,
            privacyConfig: PrivacyConfig(),
            permissionPrompter:
                FakeContextPermissionPrompter(
                    choice: .allowOnce
                )
        )

        #expect(!prepared.blocksExecution)
        #expect(prepared.reason == .captured)
        #expect(
            prepared.promptContext.selection
                == selectedText
        )
        #expect(
            prepared.contextSnapshot?
                .content(for: .selection)
                == selectedText
        )
    }
}

@MainActor
@Test
func contextBrokerFallsBackToClipboardForAXOpaqueHosts()
    async
{
    let selectedText =
        "VibeWhisper WeChat selection acceptance."
    let snapshot = contextTestSnapshot(
        text: selectedText
    )
    var axCaptureCount = 0
    var clipboardCaptureCount = 0
    let provider = SelectionContextProvider(
        capture: { _, _ in
            axCaptureCount += 1
            return .unavailable
        },
        clipboardCapture: { _, _ in
            clipboardCaptureCount += 1
            return .captured(snapshot)
        },
        verify: { _ in .unchanged }
    )
    let plan = SkillResolver().resolve(
        manualSkillID:
            SkillRegistry.contextRewriteSkillID,
        config: SkillsConfig(),
        launchAppContext: nil
    )
    var config = ContextConfig()
    config.setScope(
        .alwaysAllow,
        skillID: plan.skill.id,
        capability: .selection
    )

    let prepared = await ContextBroker(
        selectionProvider: provider
    ).prepare(
        plan: plan,
        launchAppContext:
            LaunchAppContext(
                bundleIdentifier:
                    "com.tencent.xinWeChat",
                localizedName: "WeChat",
                processIdentifier: 42
            ),
        contextConfig: config,
        privacyConfig: PrivacyConfig(),
        permissionPrompter:
            FakeContextPermissionPrompter(
                choice: .allowOnce
            )
    )

    #expect(axCaptureCount == 1)
    #expect(clipboardCaptureCount == 1)
    #expect(prepared.reason == .captured)
    #expect(!prepared.blocksExecution)
    #expect(
        prepared.promptContext.selection
            == selectedText
    )
}

@MainActor
@Test
func contextBrokerDoesNotCopyWhenAXConfirmsNoSelection()
    async
{
    var clipboardCaptureCount = 0
    let provider = SelectionContextProvider(
        capture: { _, _ in .noSelection },
        clipboardCapture: { _, _ in
            clipboardCaptureCount += 1
            return .captured(
                contextTestSnapshot()
            )
        },
        verify: { _ in .unchanged }
    )
    let plan = SkillResolver().resolve(
        manualSkillID:
            SkillRegistry.contextReplySkillID,
        config: SkillsConfig(),
        launchAppContext: nil
    )
    var config = ContextConfig()
    config.setScope(
        .alwaysAllow,
        skillID: plan.skill.id,
        capability: .selection
    )

    let prepared = await ContextBroker(
        selectionProvider: provider
    ).prepare(
        plan: plan,
        launchAppContext: nil,
        contextConfig: config,
        privacyConfig: PrivacyConfig(),
        permissionPrompter:
            FakeContextPermissionPrompter(
                choice: .allowOnce
            )
    )

    #expect(clipboardCaptureCount == 0)
    #expect(prepared.reason == .noSelection)
    #expect(prepared.blocksExecution)
}

@MainActor
@Test
func whitespaceOnlySelectionIsTreatedAsMissingContext()
    async
{
    let snapshot = contextTestSnapshot(
        text: " \n\t "
    )
    let provider = SelectionContextProvider(
        capture: { _, _ in .captured(snapshot) },
        verify: { _ in .unchanged }
    )
    let plan = SkillResolver().resolve(
        manualSkillID:
            SkillRegistry.contextRewriteSkillID,
        config: SkillsConfig(),
        launchAppContext: nil
    )
    var config = ContextConfig()
    config.setScope(
        .alwaysAllow,
        skillID: plan.skill.id,
        capability: .selection
    )

    let prepared = await ContextBroker(
        selectionProvider: provider
    ).prepare(
        plan: plan,
        launchAppContext: nil,
        contextConfig: config,
        privacyConfig: PrivacyConfig(),
        permissionPrompter:
            FakeContextPermissionPrompter(
                choice: .allowOnce
            )
    )

    #expect(prepared.reason == .noSelection)
    #expect(prepared.blocksExecution)
    #expect(
        prepared.blockedRequiredSources
            == [.selection]
    )
    #expect(prepared.promptContext.selection == nil)
    #expect(
        prepared.contextSnapshot?
            .content(for: .selection) == nil
    )
}

@MainActor
@Test
func ordinarySkillDoesNotCaptureSelectionContext()
    async
{
    var captureCount = 0
    let plan = SkillResolver().resolve(
        manualSkillID:
            SkillRegistry.directSkillID,
        config: SkillsConfig(),
        launchAppContext: nil
    )

    let prepared = await ContextBroker(
        selectionProvider:
            SelectionContextProvider(
                capture: { _, _ in
                    captureCount += 1
                    return .captured(
                        contextTestSnapshot()
                    )
                },
                verify: { _ in .unchanged }
            )
    ).prepare(
        plan: plan,
        launchAppContext: nil,
        contextConfig: ContextConfig(),
        privacyConfig: PrivacyConfig(),
        permissionPrompter:
            FakeContextPermissionPrompter(
                choice: .allowOnce
            )
    )

    #expect(captureCount == 0)
    #expect(prepared.reason == .notRequested)
    #expect(!prepared.blocksExecution)
    #expect(prepared.promptContext.selection == nil)
}

@MainActor
@Test
func contextBrokerNeverReadsSensitiveOrDeniedSelection()
    async
{
    var captureCount = 0
    let provider =
        SelectionContextProvider(
            capture: { _, _ in
                captureCount += 1
                return .noSelection
            },
            verify: { _ in
                .unchanged
            }
        )
    let prompter =
        FakeContextPermissionPrompter(
            choice: .allowOnce
        )
    let plan =
        SkillResolver().resolve(
            manualSkillID:
                SkillRegistry
                    .contextReplySkillID,
            config: SkillsConfig(),
            launchAppContext: nil
        )
    var deniedConfig = ContextConfig()
    deniedConfig.setScope(
        .denied,
        skillID: plan.skill.id,
        capability: .selection
    )

    let denied =
        await ContextBroker(
            selectionProvider:
                provider
        ).prepare(
            plan: plan,
            launchAppContext: nil,
            contextConfig:
                deniedConfig,
            privacyConfig:
                PrivacyConfig(),
            permissionPrompter:
                prompter
        )
    #expect(
        denied.reason
            == .permissionDenied
    )
    #expect(denied.blocksExecution)
    #expect(denied.blockedRequiredSources == [.selection])
    #expect(captureCount == 0)
    #expect(prompter.requests.isEmpty)

    let sensitive =
        await ContextBroker(
            selectionProvider:
                provider
        ).prepare(
            plan: plan,
            launchAppContext:
                LaunchAppContext(
                    bundleIdentifier:
                        "com.1password.1password",
                    localizedName:
                        "1Password",
                    processIdentifier: 42
                ),
            contextConfig:
                ContextConfig(),
            privacyConfig:
                PrivacyConfig(),
            permissionPrompter:
                prompter
        )
    #expect(
        sensitive.reason
            == .sensitiveApplication
    )
    #expect(sensitive.blocksExecution)
    #expect(captureCount == 0)
}

@MainActor
@Test
func requiredSelectionBlocksWhileOptionalSelectionDegrades()
    async
{
    let provider = SelectionContextProvider(
        capture: { _, _ in .noSelection },
        verify: { _ in .unchanged }
    )
    let prompter = FakeContextPermissionPrompter(
        choice: .allowOnce
    )
    let requiredPlan = SkillResolver().resolve(
        manualSkillID:
            SkillRegistry.contextRewriteSkillID,
        config: SkillsConfig(),
        launchAppContext: nil
    )
    let required = await ContextBroker(
        selectionProvider: provider
    ).prepare(
        plan: requiredPlan,
        launchAppContext: nil,
        contextConfig: ContextConfig(),
        privacyConfig: PrivacyConfig(),
        permissionPrompter: prompter
    )

    #expect(required.reason == .noSelection)
    #expect(required.blocksExecution)
    #expect(required.blockedRequiredSources == [.selection])
    #expect(required.emptySources == [.selection])
    #expect(required.blockedMessage?.contains("selected text") == true)

    let optionalSkill = SkillDefinition(
        id: "com.example.optional-selection",
        version: "1.0.0",
        name: "Optional Selection",
        optionalCapabilities: [.selection],
        promptInstruction: "Use selection when available.",
        output: SkillOutputContract(
            format: .plainText,
            delivery: .automaticPasteWhenVerified,
            risk: .low
        )
    )
    let optionalPlan = ResolvedSkillExecutionPlan(
        skill: optionalSkill,
        source: .manual,
        matchedApplicationRuleID: nil
    )
    let optional = await ContextBroker(
        selectionProvider: provider
    ).prepare(
        plan: optionalPlan,
        launchAppContext: nil,
        contextConfig: ContextConfig(),
        privacyConfig: PrivacyConfig(),
        permissionPrompter: prompter
    )

    #expect(optional.reason == .noSelection)
    #expect(optional.blocksExecution == false)
    #expect(optional.blockedRequiredSources.isEmpty)
}

@MainActor
@Test
func requiredAndOptionalSelectionCaptureDecisionMatrix() async {
    let requiredPlan = SkillResolver().resolve(
        manualSkillID: SkillRegistry.contextRewriteSkillID,
        config: SkillsConfig(),
        launchAppContext: nil
    )
    let optionalSkill = SkillDefinition(
        id: "com.example.optional-selection-matrix",
        version: "1.0.0",
        name: "Optional Selection Matrix",
        optionalCapabilities: [.selection],
        promptInstruction: "Use selection when present.",
        output: SkillOutputContract(
            format: .plainText,
            delivery: .previewThenPaste,
            risk: .low
        )
    )
    let optionalPlan = ResolvedSkillExecutionPlan(
        skill: optionalSkill,
        source: .manual,
        matchedApplicationRuleID: nil
    )
    let cases: [
        (
            SelectionContextCaptureResult,
            ContextPreparationReason,
            String
        )
    ] = [
        (.noSelection, .noSelection, "empty"),
        (.unavailable, .unavailable, "unavailable"),
        (
            .tooLarge(actual: 9_000, maximum: 6_000),
            .selectionTooLarge,
            "empty"
        ),
    ]

    for (captureResult, expectedReason, decisionCode) in cases {
        let broker = ContextBroker(
            selectionProvider: SelectionContextProvider(
                capture: { _, _ in captureResult },
                verify: { _ in .unchanged }
            )
        )
        let required = await broker.prepare(
            plan: requiredPlan,
            launchAppContext: nil,
            contextConfig: ContextConfig(),
            privacyConfig: PrivacyConfig(),
            permissionPrompter: FakeContextPermissionPrompter(
                choice: .allowOnce
            )
        )
        #expect(required.reason == expectedReason)
        #expect(required.blocksExecution)
        #expect(required.blockedRequiredSources == [.selection])
        #expect(
            required.contextReceipt?.decisions.first {
                $0.source == .selection
            }?.decisionCode == decisionCode
        )

        let optional = await broker.prepare(
            plan: optionalPlan,
            launchAppContext: nil,
            contextConfig: ContextConfig(),
            privacyConfig: PrivacyConfig(),
            permissionPrompter: FakeContextPermissionPrompter(
                choice: .allowOnce
            )
        )
        #expect(optional.reason == expectedReason)
        #expect(!optional.blocksExecution)
        #expect(optional.blockedRequiredSources.isEmpty)
        #expect(
            optional.contextReceipt?.decisions.first {
                $0.source == .selection
            }?.decisionCode == decisionCode
        )
    }
}

@MainActor
@Test
func deniedOptionalSelectionDegradesWithoutProviderBlocking() async {
    let skill = SkillDefinition(
        id: "com.example.optional-selection-denied",
        version: "1.0.0",
        name: "Optional Selection Denied",
        optionalCapabilities: [.selection],
        promptInstruction: "Use selection when allowed.",
        output: SkillOutputContract(
            format: .plainText,
            delivery: .previewThenPaste,
            risk: .low
        )
    )
    let plan = ResolvedSkillExecutionPlan(
        skill: skill,
        source: .manual,
        matchedApplicationRuleID: nil
    )
    var config = ContextConfig()
    config.setScope(
        .denied,
        skillID: skill.id,
        capability: .selection
    )
    let prepared = await ContextBroker(
        selectionProvider: SelectionContextProvider(
            capture: { _, _ in
                Issue.record(
                    "Denied optional Context must not be captured"
                )
                return .noSelection
            },
            verify: { _ in .unchanged }
        )
    ).prepare(
        plan: plan,
        launchAppContext: nil,
        contextConfig: config,
        privacyConfig: PrivacyConfig(),
        permissionPrompter: FakeContextPermissionPrompter(
            choice: .allowOnce
        )
    )

    #expect(!prepared.blocksExecution)
    #expect(prepared.deniedSources == [.selection])
    #expect(
        prepared.contextReceipt?.decisions.first {
            $0.source == .selection
        }?.decisionCode == "denied"
    )
}

@MainActor
@Test
func contextBrokerReturnsPersistentGrantOnlyForAlwaysAllow()
    async
{
    let snapshot =
        contextTestSnapshot()
    let prompter =
        FakeContextPermissionPrompter(
            choice: .alwaysAllow
        )
    let plan =
        SkillResolver().resolve(
            manualSkillID:
                SkillRegistry
                    .contextRewriteSkillID,
            config: SkillsConfig(),
            launchAppContext: nil
        )
    let prepared =
        await ContextBroker(
            selectionProvider:
                SelectionContextProvider(
                    capture: { _, _ in
                        .captured(snapshot)
                    },
                    verify: { _ in
                        .unchanged
                    }
                )
        ).prepare(
            plan: plan,
            launchAppContext:
                LaunchAppContext(
                    bundleIdentifier:
                        "com.apple.TextEdit",
                    localizedName:
                        "TextEdit",
                    processIdentifier: 42,
                    focusedTarget:
                        snapshot.target
                ),
            contextConfig:
                ContextConfig(),
            privacyConfig:
                PrivacyConfig(),
            permissionPrompter:
                prompter
        )

    #expect(
        prepared.persistentGrant
            == SkillPermissionGrant(
                skillID:
                    SkillRegistry
                        .contextRewriteSkillID,
                capability: .selection,
                scope: .alwaysAllow
            )
    )
}

@Test
func selectionContextDigestChangesWhenSelectionTextChanges() {
    #expect(
        SelectionContextSnapshot.digest(
            for: "alpha"
        )
            != SelectionContextSnapshot
                .digest(for: "beta")
    )
}
