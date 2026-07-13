import ApplicationServices
import Foundation
import Testing
@testable import OpenWhisper

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
    let text =
        "Keep API v2 and 2026-07-14."
    return SelectionContextSnapshot(
        target: contextTestTarget(),
        selectedRange:
            CFRange(
                location: 4,
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
    #expect(captureCount == 0)
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
