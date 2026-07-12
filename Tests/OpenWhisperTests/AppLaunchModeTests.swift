import Testing
@testable import OpenWhisper

struct AppLaunchModeTests {
    @Test
    func overlayDemoModeRequiresExplicitFlag() {
        #expect(AppLaunchMode.resolve(environment: [:]) == .normal)
        #expect(AppLaunchMode.resolve(environment: ["OPENWHISPER_OVERLAY_DEMO": "0"]) == .normal)
        #expect(AppLaunchMode.resolve(environment: ["OPENWHISPER_OVERLAY_DEMO": "false"]) == .normal)
    }

    @Test
    func overlayDemoModeAcceptsCommonTruthyFlags() {
        #expect(AppLaunchMode.resolve(environment: ["OPENWHISPER_OVERLAY_DEMO": "1"]) == .overlayDemo)
        #expect(AppLaunchMode.resolve(environment: ["OPENWHISPER_OVERLAY_DEMO": "true"]) == .overlayDemo)
        #expect(AppLaunchMode.resolve(environment: ["OPENWHISPER_OVERLAY_DEMO": "demo"]) == .overlayDemo)
    }

    @Test
    func overlayDemoModeAcceptsLaunchServicesArgument() {
        #expect(AppLaunchMode.resolve(environment: [:], arguments: ["OpenWhisper", "--overlay-demo"]) == .overlayDemo)
        #expect(AppLaunchMode.resolve(environment: [:], arguments: ["OpenWhisper", "--openwhisper-overlay-demo"]) == .overlayDemo)
    }

    @Test
    func settingsModeAcceptsLaunchServicesArgument() {
        #expect(AppLaunchMode.resolve(environment: [:], arguments: ["OpenWhisper", "--settings"]) == .settings)
        #expect(AppLaunchMode.resolve(environment: [:], arguments: ["OpenWhisper", "--open-settings"]) == .settings)
    }

    @Test
    func accessibilityGuideModeAcceptsLaunchServicesArgument() {
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["OpenWhisper", "--guide-accessibility"]
            ) == .accessibilityGuide
        )
    }

    @Test
    func overlayDemoModeAcceptsSpecificVisualStateArgument() {
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["OpenWhisper", "--overlay-demo-state", "retryable-error"]
            ) == .overlayDemoState(.retryableError)
        )
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["OpenWhisper", "--overlay-demo-state=processing"]
            ) == .overlayDemoState(.processing)
        )
        #expect(
            AppLaunchMode.resolve(
                environment: ["OPENWHISPER_OVERLAY_DEMO_STATE": "result"],
                arguments: ["OpenWhisper"]
            ) == .overlayDemoState(.result)
        )
    }

    @Test
    func benchmarkModeHasPriorityWhenExplicitlyEnabled() {
        #expect(AppLaunchMode.resolve(environment: ["OPENWHISPER_BENCHMARK": "1"]) == .benchmark)
        #expect(
            AppLaunchMode.resolve(
                environment: [
                    "OPENWHISPER_BENCHMARK": "true",
                    "OPENWHISPER_OVERLAY_DEMO": "1",
                ],
                arguments: ["OpenWhisper", "--overlay-demo"]
            ) == .benchmark
        )
    }
}
