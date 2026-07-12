import Foundation
import Testing
@testable import OpenWhisper

private enum RecoveryCredentialTestError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "test Keychain unavailable"
    }
}

@Test
func preflightRequiresChatGPTLoginForOpenWhisperDefaults() {
    let issues = RuntimePreflight.issues(
        for: AppConfig(),
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

    let issues = RuntimePreflight.issues(
        for: config,
        recoveryCredentialAvailable: { false }
    )

    #expect(issues == [.missingOpenAICompatibleAPIKey])
}

@Test
func recoveryModePassesWithAKeychainCredential() {
    var config = AppConfig()
    config.transcription.provider = .openAICompatible

    let issues = RuntimePreflight.issues(
        for: config,
        authSnapshotProvider: {
            ChatGPTAuthSnapshot(state: .signedOut, detail: "", userEmail: nil)
        },
        recoveryCredentialAvailable: { true }
    )

    #expect(issues.isEmpty)
}

@Test
func recoveryPreflightRequiresKeychainAvailabilitySignal() {
    var config = AppConfig()
    config.transcription.provider = .openAICompatible

    let issues = RuntimePreflight.issues(
        for: config,
        recoveryCredentialAvailable: { false }
    )

    #expect(issues == [.missingOpenAICompatibleAPIKey])
}

@Test
func recoveryPreflightSurfacesKeychainAccessFailures() {
    var config = AppConfig()
    config.transcription.provider = .openAICompatible

    let issues = RuntimePreflight.issues(
        for: config,
        recoveryCredentialAvailable: {
            throw RecoveryCredentialTestError.unavailable
        }
    )

    #expect(
        issues
            == [
                .openAICompatibleCredentialUnavailable(
                    "test Keychain unavailable"
                ),
            ]
    )
}
