import Foundation
import Testing
@testable import OpenWhisper

struct AppInstallLocationTests {
    @Test
    func distBuildsAreRejectedForNormalLaunches() {
        let blocker = AppInstallLocation.launchBlocker(
            bundleURL: URL(fileURLWithPath: "/Users/tester/Projects/openwhisper/dist/OpenWhisper.app")
        )

        #expect(blocker != nil)
        #expect(blocker?.message.contains("/Applications/OpenWhisper.app") == true)
        #expect(blocker?.message.contains("/Users/tester/Projects/openwhisper/dist/OpenWhisper.app") == true)
    }

    @Test
    func installedApplicationsPathIsAccepted() {
        let blocker = AppInstallLocation.launchBlocker(
            bundleURL: URL(fileURLWithPath: "/Applications/OpenWhisper.app")
        )

        #expect(blocker == nil)
    }
}
