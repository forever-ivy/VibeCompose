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
    func privacySettingsModeAcceptsPaneArgument() {
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["OpenWhisper", "--settings-pane", "privacy"]
            ) == .privacySettings
        )
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["OpenWhisper", "--settings-pane=privacy"]
            ) == .privacySettings
        )
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
    func visualAcceptanceOutputAcceptsEnvironmentAndLaunchServicesArgument() {
        #expect(
            AppLaunchMode.visualAcceptanceOutputURL(
                environment: [
                    "OPENWHISPER_VISUAL_ACCEPTANCE_OUTPUT": "/tmp/environment.png",
                ]
            )?.path == "/tmp/environment.png"
        )
        #expect(
            AppLaunchMode.visualAcceptanceOutputURL(
                environment: [:],
                arguments: [
                    "OpenWhisper",
                    "--visual-acceptance-output",
                    "/tmp/argument.png",
                ]
            )?.path == "/tmp/argument.png"
        )
        #expect(
            AppLaunchMode.visualAcceptanceOutputURL(
                environment: [:],
                arguments: [
                    "OpenWhisper",
                    "--visual-acceptance-output=/tmp/inline.png",
                ]
            )?.path == "/tmp/inline.png"
        )
    }

    @Test
    func settingsSnapshotOutputAcceptsEnvironmentAndLaunchServicesArgument() {
        #expect(
            AppLaunchMode.settingsSnapshotOutputURL(
                environment: [
                    "OPENWHISPER_SETTINGS_SNAPSHOT_OUTPUT": "/tmp/settings-environment.png",
                ]
            )?.path == "/tmp/settings-environment.png"
        )
        #expect(
            AppLaunchMode.settingsSnapshotOutputURL(
                environment: [:],
                arguments: [
                    "OpenWhisper",
                    "--settings-snapshot-output",
                    "/tmp/settings-argument.png",
                ]
            )?.path == "/tmp/settings-argument.png"
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
