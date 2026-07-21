import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var authManager: ChatGPTAuthManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        let launchMode = AppLaunchMode.resolve(
            environment: environment,
            arguments: arguments
        )
        let snapshotPrivacyMode = SnapshotPrivacyMode.resolve(
            environment: environment,
            arguments: arguments
        )
        let authManager = snapshotPrivacyMode.isEnabled
            ? ChatGPTAuthManager(store: InMemoryChatGPTSessionStore())
            : ChatGPTAuthManager()
        let accessibilityDisplayOptionsOverride =
            AppLaunchMode.visualAcceptanceDisplayOptionsOverride(
                environment: environment,
                arguments: arguments
            )
        let overlay = FeedbackSurfaceController(
            accessibilityDisplayOptionsProvider: {
                accessibilityDisplayOptionsOverride.applying(to: .system)
            }
        )
        self.authManager = authManager
        coordinator = AppCoordinator(
            overlay: overlay,
            authManager: authManager
        )
        coordinator?.start(launchMode: launchMode)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutdown()
    }
}
