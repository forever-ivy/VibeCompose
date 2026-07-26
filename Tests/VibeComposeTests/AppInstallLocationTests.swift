import Foundation
import Testing
@testable import VibeCompose

struct AppInstallLocationTests {
    @Test
    func distBuildsAreRejectedForNormalLaunches() {
        let blocker = AppInstallLocation.launchBlocker(
            bundleURL: URL(fileURLWithPath: "/Users/tester/Projects/vibecompose/dist/VibeCompose.app")
        )

        #expect(blocker != nil)
        #expect(blocker?.message.contains("/Applications/VibeCompose.app") == true)
        #expect(blocker?.message.contains("/Users/tester/Projects/vibecompose/dist/VibeCompose.app") == true)
    }

    @Test
    func installedApplicationsPathIsAccepted() {
        let blocker = AppInstallLocation.launchBlocker(
            bundleURL: URL(fileURLWithPath: "/Applications/VibeCompose.app")
        )

        #expect(blocker == nil)
    }
}
