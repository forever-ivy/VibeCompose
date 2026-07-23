import AppKit
import Foundation

enum AppInstallLocation {
    struct LaunchBlocker: Equatable {
        let message: String
    }

    static let applicationsURL = ProductIdentity.installedAppURL

    static func launchBlocker(bundleURL: URL = Bundle.main.bundleURL) -> LaunchBlocker? {
        let normalizedBundleURL = bundleURL.standardizedFileURL
        guard normalizedBundleURL != applicationsURL.standardizedFileURL else {
            return nil
        }

        return LaunchBlocker(
            message: L10n.format(
                "VibeWhisper must be installed to /Applications/VibeWhisper.app before it runs. This copy is at %@. Rebuild, install the packaged app to /Applications, then launch that installed copy.",
                normalizedBundleURL.path
            )
        )
    }

    static func revealApplicationsFolder(workspace: NSWorkspace = .shared) {
        workspace.open(applicationsURL.deletingLastPathComponent())
    }
}
