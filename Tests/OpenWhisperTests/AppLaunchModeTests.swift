import Foundation
import Testing
@testable import OpenWhisper

struct AppLaunchModeTests {
    @Test
    func visualFeedbackAcceptanceOverridesParseWithoutChangingLaunchMode() {
        #expect(
            AppLaunchMode.visualFeedbackModeOverride(
                environment: [:],
                arguments: [
                    "OpenWhisper",
                    "--visual-feedback-mode",
                    "blue-signal-frame",
                ]
            ) == .blueSignalFrame
        )
        #expect(
            AppLaunchMode.visualFeedbackModeOverride(
                environment: [
                    "OPENWHISPER_VISUAL_FEEDBACK_MODE":
                        "hidden",
                ],
                arguments: ["OpenWhisper"]
            ) == .hidden
        )
        #expect(
            AppLaunchMode
                .feedbackSurfaceDebugOutputURL(
                    environment: [:],
                    arguments: [
                        "OpenWhisper",
                        "--feedback-surface-debug-output",
                        "/tmp/feedback.json",
                    ]
                )?.path == "/tmp/feedback.json"
        )
    }

    @Test
    func overlayDemoModeRequiresExplicitFlag() {
        #expect(AppLaunchMode.resolve(environment: [:]) == .normal)
        #expect(AppLaunchMode.resolve(environment: ["OPENWHISPER_OVERLAY_DEMO": "0"]) == .normal)
        #expect(AppLaunchMode.resolve(environment: ["OPENWHISPER_OVERLAY_DEMO": "false"]) == .normal)
    }

    @Test
    func previewDemoModeAndSnapshotOutputRequireExplicitArguments() {
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: [
                    "OpenWhisper",
                    "--preview-demo",
                    "--preview-snapshot-output",
                    "/tmp/preview.png",
                ]
            ) == .previewDemo
        )
        #expect(
            AppLaunchMode
                .previewSnapshotOutputURL(
                    environment: [:],
                    arguments: [
                        "OpenWhisper",
                        "--preview-snapshot-output=/tmp/preview.png",
                    ]
                )
                == URL(
                    fileURLWithPath:
                        "/tmp/preview.png"
                )
        )
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
    func pasteAcceptanceModeAndOutputRequireExplicitArguments() {
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["OpenWhisper", "--paste-acceptance"]
            ) == .pasteAcceptance
        )
        #expect(
            AppLaunchMode.pasteAcceptanceOutputURL(
                environment: [:],
                arguments: [
                    "OpenWhisper",
                    "--paste-acceptance-output=/tmp/paste.json",
                ]
            )?.path == "/tmp/paste.json"
        )
        #expect(
            AppLaunchMode.pasteAcceptanceTarget(
                environment: [:],
                arguments: [
                    "OpenWhisper",
                    "--paste-acceptance-target=terminal",
                ]
            ) == .terminal
        )
        #expect(
            AppLaunchMode.pasteAcceptanceTarget(
                environment: [:],
                arguments: [
                    "OpenWhisper",
                    "--paste-acceptance-target",
                    "unknown",
                ]
            ) == nil
        )
    }

    @Test
    func interactionAcceptanceRequiresAnExplicitPrivateModeFlag() {
        #expect(
            AppLaunchMode.interactionAcceptanceRequested(
                environment: [:],
                arguments: ["OpenWhisper", "--open-settings"]
            ) == false
        )
        #expect(
            AppLaunchMode.interactionAcceptanceRequested(
                environment: [
                    "OPENWHISPER_INTERACTION_ACCEPTANCE": "true",
                ]
            )
        )
        #expect(
            AppLaunchMode.interactionAcceptanceRequested(
                environment: [:],
                arguments: [
                    "OpenWhisper",
                    "--private-acceptance",
                ]
            )
        )
    }

    @Test
    func settingsModeAcceptsLaunchServicesArgument() {
        #expect(AppLaunchMode.resolve(environment: [:], arguments: ["OpenWhisper", "--settings"]) == .settings)
        #expect(AppLaunchMode.resolve(environment: [:], arguments: ["OpenWhisper", "--open-settings"]) == .settings)
    }

    @Test
    func onboardingModeAndSnapshotAcceptLaunchServicesArguments() {
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["OpenWhisper", "--onboarding"]
            ) == .onboarding
        )
        #expect(
            AppLaunchMode.onboardingSnapshotOutputURL(
                environment: [:],
                arguments: [
                    "OpenWhisper",
                    "--onboarding-snapshot-output",
                    "/tmp/openwhisper-onboarding.png",
                ]
            ) == URL(fileURLWithPath: "/tmp/openwhisper-onboarding.png")
        )
        #expect(
            AppLaunchMode.onboardingStep(
                arguments: [
                    "OpenWhisper",
                    "--onboarding-step=connect",
                ]
            ) == .connect
        )
        #expect(
            AppLaunchMode.onboardingStep(
                arguments: [
                    "OpenWhisper",
                    "--onboarding-step",
                    "practice",
                ]
            ) == .practice
        )
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
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["OpenWhisper", "--settings-pane", "advanced"]
            ) == .advancedSettings
        )
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["OpenWhisper", "--settings-pane=advanced"]
            ) == .advancedSettings
        )
    }

    @Test
    func productManagementWindowsAcceptLaunchServicesArguments() {
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["OpenWhisper", "--open-history"]
            ) == .history
        )
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["OpenWhisper", "--open-terminology"]
            ) == .terminology
        )
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["OpenWhisper", "--open-quick-add"]
            ) == .quickAdd
        )
    }

    @Test
    func productManagementSnapshotOutputsAcceptArguments() {
        #expect(
            AppLaunchMode.historySnapshotOutputURL(
                environment: [:],
                arguments: [
                    "OpenWhisper",
                    "--history-snapshot-output=/tmp/history.png",
                ]
            )?.path == "/tmp/history.png"
        )
        #expect(
            AppLaunchMode.terminologySnapshotOutputURL(
                environment: [
                    "OPENWHISPER_TERMINOLOGY_SNAPSHOT_OUTPUT": "/tmp/terminology.png",
                ]
            )?.path == "/tmp/terminology.png"
        )
        #expect(
            AppLaunchMode.quickAddSnapshotOutputURL(
                environment: [:],
                arguments: [
                    "OpenWhisper",
                    "--quick-add-snapshot-output",
                    "/tmp/quick-add.png",
                ]
            )?.path == "/tmp/quick-add.png"
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
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["OpenWhisper", "--overlay-demo-state=paste-sent"]
            ) == .overlayDemoState(.pasteSent)
        )
        #expect(
            AppLaunchMode.resolve(
                environment: ["OPENWHISPER_OVERLAY_DEMO_STATE": "copied"],
                arguments: ["OpenWhisper"]
            ) == .overlayDemoState(.copied)
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
    func visualAcceptanceAccessibilityOverridesAreExplicitAndTriState() {
        #expect(
            AppLaunchMode.visualAcceptanceDisplayOptionsOverride(
                environment: [:],
                arguments: ["OpenWhisper"]
            ) == .none
        )
        #expect(
            AppLaunchMode.visualAcceptanceDisplayOptionsOverride(
                environment: [:],
                arguments: [
                    "OpenWhisper",
                    "--visual-acceptance-reduce-motion=on",
                    "--visual-acceptance-increase-contrast",
                    "off",
                ]
            ) == AccessibilityDisplayOptionsOverride(
                reduceMotion: true,
                increaseContrast: false
            )
        )
        #expect(
            AppLaunchMode.visualAcceptanceDisplayOptionsOverride(
                environment: [
                    "OPENWHISPER_VISUAL_ACCEPTANCE_REDUCE_MOTION": "0",
                    "OPENWHISPER_VISUAL_ACCEPTANCE_INCREASE_CONTRAST": "yes",
                ]
            ) == AccessibilityDisplayOptionsOverride(
                reduceMotion: false,
                increaseContrast: true
            )
        )
        #expect(
            AppLaunchMode.visualAcceptanceDisplayOptionsOverride(
                environment: [
                    "OPENWHISPER_VISUAL_ACCEPTANCE_REDUCE_MOTION": "on",
                ],
                arguments: [
                    "OpenWhisper",
                    "--visual-acceptance-reduce-motion=off",
                ]
            ).reduceMotion == false
        )
    }

    @Test
    func accessibilityDisplayOptionsOverridePreservesUnspecifiedSystemValues() {
        let system = AccessibilityDisplayOptions(
            reduceMotion: true,
            increaseContrast: false
        )

        #expect(AccessibilityDisplayOptionsOverride.none.applying(to: system) == system)
        #expect(
            AccessibilityDisplayOptionsOverride(
                reduceMotion: false,
                increaseContrast: nil
            ).applying(to: system) == AccessibilityDisplayOptions(
                reduceMotion: false,
                increaseContrast: false
            )
        )
    }

    @Test
    func visualAcceptanceFollowupOutputAcceptsEnvironmentAndArgument() {
        #expect(
            AppLaunchMode.visualAcceptanceFollowupOutputURL(
                environment: [
                    "OPENWHISPER_VISUAL_ACCEPTANCE_FOLLOWUP_OUTPUT":
                        "/tmp/followup-environment.png",
                ]
            )?.path == "/tmp/followup-environment.png"
        )
        #expect(
            AppLaunchMode.visualAcceptanceFollowupOutputURL(
                environment: [:],
                arguments: [
                    "OpenWhisper",
                    "--visual-acceptance-followup-output=/tmp/followup-argument.png",
                ]
            )?.path == "/tmp/followup-argument.png"
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
    func settingsSnapshotSizeAcceptsBoundedEnvironmentAndArguments() {
        #expect(
            AppLaunchMode.settingsSnapshotSize(
                environment: [
                    "OPENWHISPER_SETTINGS_SNAPSHOT_SIZE": "980x720",
                ]
            ) == SettingsSnapshotSize(width: 980, height: 720)
        )
        #expect(
            AppLaunchMode.settingsSnapshotSize(
                environment: [:],
                arguments: [
                    "OpenWhisper",
                    "--settings-snapshot-size",
                    "820×560",
                ]
            ) == SettingsSnapshotSize(width: 820, height: 560)
        )
        #expect(
            AppLaunchMode.settingsSnapshotSize(
                environment: [:],
                arguments: [
                    "OpenWhisper",
                    "--settings-snapshot-size=1200x800",
                ]
            ) == SettingsSnapshotSize(width: 1_200, height: 800)
        )
        #expect(
            AppLaunchMode.settingsSnapshotSize(
                environment: [
                    "OPENWHISPER_SETTINGS_SNAPSHOT_SIZE": "819x560",
                ]
            ) == nil
        )
        #expect(
            AppLaunchMode.settingsSnapshotSize(
                environment: [
                    "OPENWHISPER_SETTINGS_SNAPSHOT_SIZE": "not-a-size",
                ]
            ) == nil
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

@Test
func settingsSnapshotOutputImplicitlyOpensSettings() {
    #expect(
        AppLaunchMode.resolve(
            environment: [
                "OPENWHISPER_SETTINGS_SNAPSHOT_OUTPUT":
                    "/tmp/settings.png",
            ],
            arguments: ["OpenWhisper"]
        ) == .settings
    )
}
