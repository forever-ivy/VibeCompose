import Foundation
import Testing
@testable import VibeWhisper

struct AppInstallLocationTests {
    @Test
    func distBuildsAreRejectedForNormalLaunches() {
        let blocker = AppInstallLocation.launchBlocker(
            bundleURL: URL(fileURLWithPath: "/Users/tester/Projects/vibewhisper/dist/VibeWhisper.app")
        )

        #expect(blocker != nil)
        #expect(blocker?.message.contains("/Applications/VibeWhisper.app") == true)
        #expect(blocker?.message.contains("/Users/tester/Projects/vibewhisper/dist/VibeWhisper.app") == true)
    }

    @Test
    func installedApplicationsPathIsAccepted() {
        let blocker = AppInstallLocation.launchBlocker(
            bundleURL: URL(fileURLWithPath: "/Applications/VibeWhisper.app")
        )

        #expect(blocker == nil)
    }
}
