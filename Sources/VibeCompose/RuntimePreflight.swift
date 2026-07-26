import Foundation

enum RuntimePreflightIssue: Equatable, Sendable {
    case chatGPTLoginRequired
    case chatGPTSessionExpired
    case chatGPTSessionUnavailable(String)
    case missingOpenAICompatibleAPIKey
    case openAICompatibleCredentialUnavailable(String)

    var message: String {
        switch self {
        case .chatGPTLoginRequired:
            return L10n.text("Connect ChatGPT with the default browser OAuth flow before recording.")
        case .chatGPTSessionExpired:
            return L10n.text("VibeCompose saved a ChatGPT session, but it has expired. Refresh or sign in again.")
        case .chatGPTSessionUnavailable(let detail):
            return detail
        case .missingOpenAICompatibleAPIKey:
            return L10n.text(
                "Save an OpenAI-Compatible API key in Keychain before recording."
            )
        case .openAICompatibleCredentialUnavailable(let detail):
            return L10n.format(
                "VibeCompose could not access the OpenAI-Compatible API key in Keychain: %@",
                detail
            )
        }
    }
}

enum RuntimePreflight {
    static func issues(
        for config: AppConfig,
        authSnapshotProvider: (() -> ChatGPTAuthSnapshot)? = nil,
        recoveryCredentialAvailable: (() throws -> Bool)? = nil
    ) -> [RuntimePreflightIssue] {
        var issues: [RuntimePreflightIssue] = []
        let provider = authSnapshotProvider ?? defaultAuthSnapshotProvider
        let credentialAvailable = recoveryCredentialAvailable
            ?? defaultRecoveryCredentialAvailability

        if config.transcription.provider == .chatGPTManagedAuth {
            appendChatGPTAuthIssues(into: &issues, authSnapshotProvider: provider)
        } else if config.transcription.provider == .openAICompatible {
            do {
                if try !credentialAvailable() {
                    issues.append(.missingOpenAICompatibleAPIKey)
                }
            } catch {
                issues.append(
                    .openAICompatibleCredentialUnavailable(
                        error.localizedDescription
                    )
                )
            }
        }

        return issues
    }

    static func summary(for issues: [RuntimePreflightIssue]) -> String? {
        guard let firstIssue = issues.first else {
            return nil
        }

        if issues.count == 1 {
            return firstIssue.message
        }

        return L10n.format(
            "%@ %ld more setting issue(s) need attention.",
            firstIssue.message,
            issues.count - 1
        )
    }

    private static func appendChatGPTAuthIssues(
        into issues: inout [RuntimePreflightIssue],
        authSnapshotProvider: () -> ChatGPTAuthSnapshot
    ) {
        for issue in chatGPTAuthIssues(authSnapshotProvider: authSnapshotProvider) where !issues.contains(issue) {
            issues.append(issue)
        }
    }

    private static func chatGPTAuthIssues(
        authSnapshotProvider: () -> ChatGPTAuthSnapshot
    ) -> [RuntimePreflightIssue] {
        let snapshot = authSnapshotProvider()
        switch snapshot.state {
        case .ready:
            return []
        case .signedOut:
            return [.chatGPTLoginRequired]
        case .expired:
            return [.chatGPTSessionExpired]
        case .unavailable:
            return [.chatGPTSessionUnavailable(snapshot.detail)]
        }
    }

    private static func defaultAuthSnapshotProvider() -> ChatGPTAuthSnapshot {
        ChatGPTAuthManager().authSnapshot()
    }

    private static func defaultRecoveryCredentialAvailability() throws -> Bool {
        try KeychainOpenAICompatibleCredentialStore().hasAPIKey()
    }
}
