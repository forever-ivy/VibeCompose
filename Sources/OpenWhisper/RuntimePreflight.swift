import Foundation

enum RuntimePreflightIssue: Equatable, Sendable {
    case chatGPTLoginRequired
    case chatGPTSessionExpired
    case chatGPTSessionUnavailable(String)
    case missingTranscriptionAuthToken(String)

    var message: String {
        switch self {
        case .chatGPTLoginRequired:
            return L10n.text("Connect ChatGPT with the default browser OAuth flow before recording.")
        case .chatGPTSessionExpired:
            return L10n.text("OpenWhisper saved a ChatGPT session, but it has expired. Refresh or sign in again.")
        case .chatGPTSessionUnavailable(let detail):
            return detail
        case .missingTranscriptionAuthToken(let envName):
            return L10n.format("Set environment variable %@ before recording.", envName)
        }
    }
}

enum RuntimePreflight {
    static func issues(
        for config: AppConfig,
        environment: [String: String],
        authSnapshotProvider: (() -> ChatGPTAuthSnapshot)? = nil
    ) -> [RuntimePreflightIssue] {
        var issues: [RuntimePreflightIssue] = []
        let provider = authSnapshotProvider ?? defaultAuthSnapshotProvider

        if config.transcription.provider == .chatGPTManagedAuth {
            appendChatGPTAuthIssues(into: &issues, authSnapshotProvider: provider)
        } else if config.transcription.provider == .openAICompatible {
            let envName = normalizedEnvName(config.transcription.openAIAuthTokenEnv)
            let token = environment[envName]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if token.isEmpty {
                issues.append(.missingTranscriptionAuthToken(envName))
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

    private static func normalizedEnvName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "OPENAI_API_KEY" : trimmed
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
}
