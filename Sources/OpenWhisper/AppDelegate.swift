import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private let authManager = ChatGPTAuthManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = AppCoordinator(authManager: authManager)
        coordinator?.start(
            launchMode: AppLaunchMode.resolve(
                environment: ProcessInfo.processInfo.environment,
                arguments: ProcessInfo.processInfo.arguments
            )
        )
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }
}
