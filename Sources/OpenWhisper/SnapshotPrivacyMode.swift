import Foundation

struct SnapshotPrivacyMode: Equatable, Sendable {
    let isEnabled: Bool

    static let disabled = SnapshotPrivacyMode(isEnabled: false)

    static func resolve(
        environment: [String: String],
        arguments: [String]
    ) -> SnapshotPrivacyMode {
        let hasSnapshotOutput =
            AppLaunchMode.settingsSnapshotOutputURL(
                environment: environment,
                arguments: arguments
            ) != nil
            || AppLaunchMode.onboardingSnapshotOutputURL(
                environment: environment,
                arguments: arguments
            ) != nil
            || AppLaunchMode.historySnapshotOutputURL(
                environment: environment,
                arguments: arguments
            ) != nil
            || AppLaunchMode.terminologySnapshotOutputURL(
                environment: environment,
                arguments: arguments
            ) != nil
            || AppLaunchMode.quickAddSnapshotOutputURL(
                environment: environment,
                arguments: arguments
            ) != nil
            || AppLaunchMode.accessibilityAuditOutputURL(
                environment: environment,
                arguments: arguments
            ) != nil

        return SnapshotPrivacyMode(isEnabled: hasSnapshotOutput)
    }

    func presentationConfig(liveConfig: AppConfig) -> AppConfig {
        isEnabled ? AppConfig() : liveConfig
    }

    func presentationAuthManager(
        liveAuthManager: any ChatGPTAuthProviding
    ) -> ChatGPTAuthManager {
        if isEnabled {
            return ChatGPTAuthManager(
                store: InMemoryChatGPTSessionStore()
            )
        }

        if let concrete = liveAuthManager as? ChatGPTAuthManager {
            return concrete
        }
        return ChatGPTAuthManager()
    }

    func presentationCredentialStore(
        liveCredentialStore: any OpenAICompatibleCredentialPersisting
    ) -> any OpenAICompatibleCredentialPersisting {
        if isEnabled {
            return InMemoryOpenAICompatibleCredentialStore()
        }
        return liveCredentialStore
    }

    func presentationDiagnosticsDirectoryURL(
        liveDirectoryURL: URL
    ) -> URL? {
        isEnabled ? nil : liveDirectoryURL
    }

    func loadPresentationRecords<Record>(
        _ loader: () -> [Record]
    ) -> [Record] {
        isEnabled ? [] : loader()
    }
}
