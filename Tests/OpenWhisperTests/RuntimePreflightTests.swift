import Foundation
import Testing
@testable import OpenWhisper

@Test
func preflightRequiresChatGPTLoginForOpenWhisperDefaults() {
    let issues = RuntimePreflight.issues(
        for: AppConfig(),
        environment: [:],
        authSnapshotProvider: {
            ChatGPTAuthSnapshot(state: .signedOut, detail: "", userEmail: nil)
        }
    )

    #expect(issues == [.chatGPTLoginRequired])
}

@Test
func preflightFlagsExpiredChatGPTSession() {
    let issues = RuntimePreflight.issues(
        for: AppConfig(),
        environment: [:],
        authSnapshotProvider: {
            ChatGPTAuthSnapshot(state: .expired, detail: "expired", userEmail: "user@example.com")
        }
    )

    #expect(issues == [.chatGPTSessionExpired])
}

@Test
func preflightRequiresOpenAIKeyInRecoveryMode() {
    var config = AppConfig()
    config.transcription.provider = .openAICompatible

    let issues = RuntimePreflight.issues(for: config, environment: [:])

    #expect(issues == [.missingTranscriptionAuthToken("OPENAI_API_KEY")])
}

@Test
func legacyCleanupConfigDoesNotAddDesktopHostRequirementToRecoveryMode() {
    var config = AppConfig()
    config.transcription.provider = .openAICompatible

    let issues = RuntimePreflight.issues(
        for: config,
        environment: ["OPENAI_API_KEY": "test-key"],
        authSnapshotProvider: {
            ChatGPTAuthSnapshot(state: .signedOut, detail: "", userEmail: nil)
        }
    )

    #expect(issues.isEmpty)
}
