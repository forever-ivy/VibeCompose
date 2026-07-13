import Foundation
import Testing
@testable import OpenWhisper

@Test
func snapshotPrivacyModeRecognizesEveryProductSurfaceCapture() {
    let cases: [([String: String], [String])] = [
        (["OPENWHISPER_SETTINGS_SNAPSHOT_OUTPUT": "/tmp/settings.png"], []),
        (["OPENWHISPER_ONBOARDING_SNAPSHOT_OUTPUT": "/tmp/onboarding.png"], []),
        (["OPENWHISPER_HISTORY_SNAPSHOT_OUTPUT": "/tmp/history.png"], []),
        (["OPENWHISPER_TERMINOLOGY_SNAPSHOT_OUTPUT": "/tmp/terminology.png"], []),
        (["OPENWHISPER_QUICK_ADD_SNAPSHOT_OUTPUT": "/tmp/quick-add.png"], []),
        (["OPENWHISPER_ACCESSIBILITY_AUDIT_OUTPUT": "/tmp/audit.json"], []),
        (["OPENWHISPER_INTERACTION_ACCEPTANCE": "true"], []),
        ([:], ["--settings-snapshot-output=/tmp/settings.png"]),
        ([:], ["--history-snapshot-output", "/tmp/history.png"]),
        ([:], ["--open-settings", "--interaction-acceptance"]),
    ]

    for (environment, arguments) in cases {
        #expect(
            SnapshotPrivacyMode.resolve(
                environment: environment,
                arguments: arguments
            ).isEnabled
        )
    }

    #expect(
        SnapshotPrivacyMode.resolve(
            environment: [:],
            arguments: ["--open-settings"]
        ) == .disabled
    )
}

@Test
func snapshotPrivacyModeReplacesUserConfigurationWithDefaults() {
    var liveConfig = AppConfig()
    liveConfig.transcription.openAITranscriptionURL =
        "https://private.example.test/audio"
    liveConfig.transcription.hintTerms = ["Private Project"]
    liveConfig.transcription.terminology.entries = [
        TerminologyEntry(
            type: .correction,
            original: "SecretTerm",
            replacement: "SecretReplacement",
            aliases: [],
            isEnabled: true,
            source: "manual",
            usageCount: 0,
            createdAt: "2026-07-13T00:00:00Z"
        ),
    ]
    liveConfig.transcription.terminology.lastImportedSource =
        "/Users/example/private-terms.txt"
    liveConfig.privacy.additionalSensitiveAppBundleIdentifiers = [
        "com.example.private",
    ]

    let sanitized = SnapshotPrivacyMode(isEnabled: true)
        .presentationConfig(liveConfig: liveConfig)

    #expect(sanitized == AppConfig())
    #expect(sanitized.transcription.hintTerms.isEmpty)
    #expect(sanitized.transcription.terminology.entries.isEmpty)
    #expect(sanitized.transcription.terminology.lastImportedSource == nil)
    #expect(
        sanitized.privacy.additionalSensitiveAppBundleIdentifiers.isEmpty
    )
    #expect(
        SnapshotPrivacyMode.disabled.presentationConfig(
            liveConfig: liveConfig
        ) == liveConfig
    )
}

@Test
func snapshotPrivacyModeDoesNotInvokeUserRecordLoaders() {
    var loadCount = 0
    let privateRecords = SnapshotPrivacyMode(isEnabled: true)
        .loadPresentationRecords {
            loadCount += 1
            return ["private transcript"]
        }

    #expect(privateRecords.isEmpty)
    #expect(loadCount == 0)

    let liveRecords = SnapshotPrivacyMode.disabled
        .loadPresentationRecords {
            loadCount += 1
            return ["live transcript"]
        }

    #expect(liveRecords == ["live transcript"])
    #expect(loadCount == 1)
}

@Test
func snapshotPrivacyModeUsesEmptyInMemoryCredentials() throws {
    let liveSession = ChatGPTSession(
        accessToken: "private-access-token",
        accessTokenExpiresAt: Date().addingTimeInterval(3_600),
        cookies: [],
        userEmail: "private@example.test",
        updatedAt: Date()
    )
    let liveAuthManager = ChatGPTAuthManager(
        store: InMemoryChatGPTSessionStore(session: liveSession)
    )
    let liveCredentialStore =
        InMemoryOpenAICompatibleCredentialStore(apiKey: "private-api-key")

    let mode = SnapshotPrivacyMode(isEnabled: true)
    let isolatedAuthManager = mode.presentationAuthManager(
        liveAuthManager: liveAuthManager
    )
    let isolatedCredentialStore = mode.presentationCredentialStore(
        liveCredentialStore: liveCredentialStore
    )

    #expect(isolatedAuthManager.authSnapshot().state == .signedOut)
    #expect(isolatedAuthManager.authSnapshot().userEmail == nil)
    #expect(try isolatedCredentialStore.hasAPIKey() == false)
    #expect(
        mode.presentationDiagnosticsDirectoryURL(
            liveDirectoryURL: URL(fileURLWithPath: "/private/diagnostics")
        ) == nil
    )

    let normalAuthManager = SnapshotPrivacyMode.disabled
        .presentationAuthManager(liveAuthManager: liveAuthManager)
    let normalCredentialStore = SnapshotPrivacyMode.disabled
        .presentationCredentialStore(
            liveCredentialStore: liveCredentialStore
        )

    #expect(normalAuthManager === liveAuthManager)
    #expect(normalAuthManager.authSnapshot().userEmail == "private@example.test")
    #expect(try normalCredentialStore.loadAPIKey() == "private-api-key")
    #expect(
        SnapshotPrivacyMode.disabled.presentationDiagnosticsDirectoryURL(
            liveDirectoryURL: URL(fileURLWithPath: "/live/diagnostics")
        ) == URL(fileURLWithPath: "/live/diagnostics")
    )
}
