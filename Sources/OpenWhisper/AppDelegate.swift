import AppKit

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
        self.authManager = authManager
        coordinator = AppCoordinator(authManager: authManager)
        coordinator?.start(launchMode: launchMode)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutdown()
    }
}
