import Foundation

enum ProductIdentity {
    static let name = "VibeCompose"
    static let slug = "vibecompose"
    static let defaultBundleIdentifier = "app.vibecompose.mac"
    static let keychainService = "\(defaultBundleIdentifier).ChatGPTSession"
    static let recoveryAPIKeychainService =
        "\(defaultBundleIdentifier).OpenAICompatibleAPIKey"
    /// Separate Keychain account for polish Own-API credentials.
    static let polishAPIKeychainService =
        "\(defaultBundleIdentifier).OpenAICompatiblePolishAPIKey"
    static let oauthCallbackQueueLabel = "\(defaultBundleIdentifier).oauth-callback"

    static let installedAppURL = URL(fileURLWithPath: "/Applications/\(name).app")

    static var runtimeVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.1.0"
    }

    static var userAgent: String {
        "\(name)/\(runtimeVersion)"
    }

    static func applicationSupportURL(homeDirectoryURL: URL) -> URL {
        homeDirectoryURL
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    static func recoveryURL(homeDirectoryURL: URL) -> URL {
        applicationSupportURL(homeDirectoryURL: homeDirectoryURL)
            .appendingPathComponent("Recovery", isDirectory: true)
    }
}
