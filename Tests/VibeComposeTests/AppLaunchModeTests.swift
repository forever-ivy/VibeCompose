import Foundation
import Testing
@testable import VibeCompose

struct AppLaunchModeTests {
    @Test
    func visualFeedbackAcceptanceOverridesParseWithoutChangingLaunchMode() {
        #expect(
            AppLaunchMode.visualFeedbackModeOverride(
                environment: [:],
                arguments: [
                    "VibeCompose",
                    "--visual-feedback-mode",
                    "blue-signal-frame",
                ]
            ) == .aiActivityGlow
        )
        #expect(
            AppLaunchMode.visualFeedbackModeOverride(
                environment: [
                    "VIBECOMPOSE_VISUAL_FEEDBACK_MODE":
                        "hidden",
                ],
                arguments: ["VibeCompose"]
            ) == .hidden
        )
        #expect(
            AppLaunchMode
                .feedbackSurfaceDebugOutputURL(
                    environment: [:],
                    arguments: [
                        "VibeCompose",
                        "--feedback-surface-debug-output",
                        "/tmp/feedback.json",
                    ]
                )?.path == "/tmp/feedback.json"
        )
    }

    @Test
    func overlayDemoModeRequiresExplicitFlag() {
        #expect(AppLaunchMode.resolve(environment: [:]) == .normal)
        #expect(AppLaunchMode.resolve(environment: ["VIBECOMPOSE_OVERLAY_DEMO": "0"]) == .normal)
        #expect(AppLaunchMode.resolve(environment: ["VIBECOMPOSE_OVERLAY_DEMO": "false"]) == .normal)
    }

    @Test
    func previewDemoModeAndSnapshotOutputRequireExplicitArguments() {
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: [
                    "VibeCompose",
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
                        "VibeCompose",
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
    func previewDemoScenarioDefaultsAndParsesExplicitValues() {
        #expect(
            AppLaunchMode.previewDemoScenario(arguments: [])
                == .replace
        )
        #expect(
            AppLaunchMode.previewDemoScenario(
                arguments: [
                    "VibeCompose",
                    "--preview-demo-scenario",
                    "paste",
                ]
            ) == .paste
        )
        #expect(
            AppLaunchMode.previewDemoScenario(
                arguments: [
                    "VibeCompose",
                    "--preview-demo-scenario=fallback",
                ]
            ) == .fallback
        )
        #expect(
            AppLaunchMode.previewDemoScenario(
                arguments: [
                    "VibeCompose",
                    "--preview-demo-scenario=unknown",
                ]
            ) == .replace
        )
    }

    @Test
    func overlayDemoModeAcceptsCommonTruthyFlags() {
        #expect(AppLaunchMode.resolve(environment: ["VIBECOMPOSE_OVERLAY_DEMO": "1"]) == .overlayDemo)
        #expect(AppLaunchMode.resolve(environment: ["VIBECOMPOSE_OVERLAY_DEMO": "true"]) == .overlayDemo)
        #expect(AppLaunchMode.resolve(environment: ["VIBECOMPOSE_OVERLAY_DEMO": "demo"]) == .overlayDemo)
    }

    @Test
    func overlayDemoModeAcceptsLaunchServicesArgument() {
        #expect(AppLaunchMode.resolve(environment: [:], arguments: ["VibeCompose", "--overlay-demo"]) == .overlayDemo)
        #expect(AppLaunchMode.resolve(environment: [:], arguments: ["VibeCompose", "--vibecompose-overlay-demo"]) == .overlayDemo)
    }

    @Test
    func pasteAcceptanceModeAndOutputRequireExplicitArguments() {
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["VibeCompose", "--paste-acceptance"]
            ) == .pasteAcceptance
        )
        #expect(
            AppLaunchMode.pasteAcceptanceOutputURL(
                environment: [:],
                arguments: [
                    "VibeCompose",
                    "--paste-acceptance-output=/tmp/paste.json",
                ]
            )?.path == "/tmp/paste.json"
        )
        #expect(
            AppLaunchMode.pasteAcceptanceTarget(
                environment: [:],
                arguments: [
                    "VibeCompose",
                    "--paste-acceptance-target=terminal",
                ]
            ) == .terminal
        )
        #expect(
            AppLaunchMode.pasteAcceptanceTarget(
                environment: [:],
                arguments: [
                    "VibeCompose",
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
                arguments: ["VibeCompose", "--open-settings"]
            ) == false
        )
        #expect(
            AppLaunchMode.interactionAcceptanceRequested(
                environment: [
                    "VIBECOMPOSE_INTERACTION_ACCEPTANCE": "true",
                ]
            )
        )
        #expect(
            AppLaunchMode.interactionAcceptanceRequested(
                environment: [:],
                arguments: [
                    "VibeCompose",
                    "--private-acceptance",
                ]
            )
        )
    }

    @Test
    func settingsModeAcceptsLaunchServicesArgument() {
        #expect(AppLaunchMode.resolve(environment: [:], arguments: ["VibeCompose", "--settings"]) == .settings)
        #expect(AppLaunchMode.resolve(environment: [:], arguments: ["VibeCompose", "--open-settings"]) == .settings)
    }

    @Test
    func onboardingModeAndSnapshotAcceptLaunchServicesArguments() {
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["VibeCompose", "--onboarding"]
            ) == .onboarding
        )
        #expect(
            AppLaunchMode.onboardingSnapshotOutputURL(
                environment: [:],
                arguments: [
                    "VibeCompose",
                    "--onboarding-snapshot-output",
                    "/tmp/vibecompose-onboarding.png",
                ]
            ) == URL(fileURLWithPath: "/tmp/vibecompose-onboarding.png")
        )
        #expect(
            AppLaunchMode.onboardingStep(
                arguments: [
                    "VibeCompose",
                    "--onboarding-step=connect",
                ]
            ) == .connect
        )
        #expect(
            AppLaunchMode.onboardingStep(
                arguments: [
                    "VibeCompose",
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
                arguments: ["VibeCompose", "--settings-pane", "privacy"]
            ) == .privacySettings
        )
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["VibeCompose", "--settings-pane=privacy"]
            ) == .privacySettings
        )
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["VibeCompose", "--settings-pane", "advanced"]
            ) == .advancedSettings
        )
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["VibeCompose", "--settings-pane=advanced"]
            ) == .advancedSettings
        )
    }

    @Test
    func productManagementWindowsAcceptLaunchServicesArguments() {
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["VibeCompose", "--open-history"]
            ) == .history
        )
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["VibeCompose", "--open-terminology"]
            ) == .terminology
        )
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["VibeCompose", "--open-quick-add"]
            ) == .quickAdd
        )
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["VibeCompose", "--open-skill-library"]
            ) == .skillLibrary
        )
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["VibeCompose", "--open-skill-switcher"]
            ) == .skillSwitcher
        )
        #expect(
            AppLaunchMode.skillLibrarySection(
                arguments: [
                    "VibeCompose",
                    "--skill-library-section=created",
                ]
            ) == .created
        )
    }

    @Test
    func productManagementSnapshotOutputsAcceptArguments() {
        #expect(
            AppLaunchMode.historySnapshotOutputURL(
                environment: [:],
                arguments: [
                    "VibeCompose",
                    "--history-snapshot-output=/tmp/history.png",
                ]
            )?.path == "/tmp/history.png"
        )
        #expect(
            AppLaunchMode.terminologySnapshotOutputURL(
                environment: [
                    "VIBECOMPOSE_TERMINOLOGY_SNAPSHOT_OUTPUT": "/tmp/terminology.png",
                ]
            )?.path == "/tmp/terminology.png"
        )
        #expect(
            AppLaunchMode.quickAddSnapshotOutputURL(
                environment: [:],
                arguments: [
                    "VibeCompose",
                    "--quick-add-snapshot-output",
                    "/tmp/quick-add.png",
                ]
            )?.path == "/tmp/quick-add.png"
        )
        #expect(
            AppLaunchMode.skillLibrarySnapshotOutputURL(
                environment: [:],
                arguments: [
                    "VibeCompose",
                    "--skill-library-snapshot-output",
                    "/tmp/skill-library.png",
                ]
            )?.path == "/tmp/skill-library.png"
        )
        #expect(
            AppLaunchMode.skillSwitcherSnapshotOutputURL(
                environment: [
                    "VIBECOMPOSE_SKILL_SWITCHER_SNAPSHOT_OUTPUT":
                        "/tmp/skill-switcher.png",
                ]
            )?.path == "/tmp/skill-switcher.png"
        )
    }

    @Test
    func accessibilityGuideModeAcceptsLaunchServicesArgument() {
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["VibeCompose", "--guide-accessibility"]
            ) == .accessibilityGuide
        )
    }

    @Test
    func overlayDemoModeAcceptsSpecificVisualStateArgument() {
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["VibeCompose", "--overlay-demo-state", "retryable-error"]
            ) == .overlayDemoState(.retryableError)
        )
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["VibeCompose", "--overlay-demo-state=processing"]
            ) == .overlayDemoState(.processing)
        )
        #expect(
            AppLaunchMode.resolve(
                environment: ["VIBECOMPOSE_OVERLAY_DEMO_STATE": "result"],
                arguments: ["VibeCompose"]
            ) == .overlayDemoState(.result)
        )
        #expect(
            AppLaunchMode.resolve(
                environment: [:],
                arguments: ["VibeCompose", "--overlay-demo-state=paste-sent"]
            ) == .overlayDemoState(.pasteSent)
        )
        #expect(
            AppLaunchMode.resolve(
                environment: ["VIBECOMPOSE_OVERLAY_DEMO_STATE": "copied"],
                arguments: ["VibeCompose"]
            ) == .overlayDemoState(.copied)
        )
    }

    @Test
    func visualAcceptanceOutputAcceptsEnvironmentAndLaunchServicesArgument() {
        #expect(
            AppLaunchMode.visualAcceptanceOutputURL(
                environment: [
                    "VIBECOMPOSE_VISUAL_ACCEPTANCE_OUTPUT": "/tmp/environment.png",
                ]
            )?.path == "/tmp/environment.png"
        )
        #expect(
            AppLaunchMode.visualAcceptanceOutputURL(
                environment: [:],
                arguments: [
                    "VibeCompose",
                    "--visual-acceptance-output",
                    "/tmp/argument.png",
                ]
            )?.path == "/tmp/argument.png"
        )
        #expect(
            AppLaunchMode.visualAcceptanceOutputURL(
                environment: [:],
                arguments: [
                    "VibeCompose",
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
                arguments: ["VibeCompose"]
            ) == .none
        )
        #expect(
            AppLaunchMode.visualAcceptanceDisplayOptionsOverride(
                environment: [:],
                arguments: [
                    "VibeCompose",
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
                    "VIBECOMPOSE_VISUAL_ACCEPTANCE_REDUCE_MOTION": "0",
                    "VIBECOMPOSE_VISUAL_ACCEPTANCE_INCREASE_CONTRAST": "yes",
                ]
            ) == AccessibilityDisplayOptionsOverride(
                reduceMotion: false,
                increaseContrast: true
            )
        )
        #expect(
            AppLaunchMode.visualAcceptanceDisplayOptionsOverride(
                environment: [
                    "VIBECOMPOSE_VISUAL_ACCEPTANCE_REDUCE_MOTION": "on",
                ],
                arguments: [
                    "VibeCompose",
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
                    "VIBECOMPOSE_VISUAL_ACCEPTANCE_FOLLOWUP_OUTPUT":
                        "/tmp/followup-environment.png",
                ]
            )?.path == "/tmp/followup-environment.png"
        )
        #expect(
            AppLaunchMode.visualAcceptanceFollowupOutputURL(
                environment: [:],
                arguments: [
                    "VibeCompose",
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
                    "VIBECOMPOSE_SETTINGS_SNAPSHOT_OUTPUT": "/tmp/settings-environment.png",
                ]
            )?.path == "/tmp/settings-environment.png"
        )
        #expect(
            AppLaunchMode.settingsSnapshotOutputURL(
                environment: [:],
                arguments: [
                    "VibeCompose",
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
                    "VIBECOMPOSE_SETTINGS_SNAPSHOT_SIZE": "980x720",
                ]
            ) == SettingsSnapshotSize(width: 980, height: 720)
        )
        #expect(
            AppLaunchMode.settingsSnapshotSize(
                environment: [:],
                arguments: [
                    "VibeCompose",
                    "--settings-snapshot-size",
                    "820×560",
                ]
            ) == SettingsSnapshotSize(width: 820, height: 560)
        )
        #expect(
            AppLaunchMode.settingsSnapshotSize(
                environment: [:],
                arguments: [
                    "VibeCompose",
                    "--settings-snapshot-size=1200x800",
                ]
            ) == SettingsSnapshotSize(width: 1_200, height: 800)
        )
        #expect(
            AppLaunchMode.settingsSnapshotSize(
                environment: [
                    "VIBECOMPOSE_SETTINGS_SNAPSHOT_SIZE": "819x560",
                ]
            ) == nil
        )
        #expect(
            AppLaunchMode.settingsSnapshotSize(
                environment: [
                    "VIBECOMPOSE_SETTINGS_SNAPSHOT_SIZE": "not-a-size",
                ]
            ) == nil
        )
    }

    @Test
    func settingsSnapshotLanguageIsExplicitAndBounded() {
        #expect(
            AppLaunchMode.settingsSnapshotLanguage(
                environment: [
                    "VIBECOMPOSE_SETTINGS_SNAPSHOT_LANGUAGE": "zh-Hans",
                ]
            ) == .simplifiedChinese
        )
        #expect(
            AppLaunchMode.settingsSnapshotLanguage(
                environment: [:],
                arguments: [
                    "VibeCompose",
                    "--settings-snapshot-language=en",
                ]
            ) == .english
        )
        #expect(
            AppLaunchMode.settingsSnapshotLanguage(
                environment: [:],
                arguments: [
                    "VibeCompose",
                    "--settings-snapshot-language",
                    "unsupported",
                ]
            ) == nil
        )
    }

    @Test
    func snapshotLanguageSupportsAllPrivateSnapshotSurfaces() {
        #expect(
            AppLaunchMode.snapshotLanguage(
                environment: [
                    "VIBECOMPOSE_SNAPSHOT_LANGUAGE": "zh-Hans",
                ]
            ) == .simplifiedChinese
        )
        #expect(
            AppLaunchMode.snapshotLanguage(
                environment: [:],
                arguments: ["--snapshot-language=en"]
            ) == .english
        )
        #expect(
            AppLaunchMode.snapshotLanguage(
                environment: [:],
                arguments: ["--snapshot-language", "system"]
            ) == .system
        )
        #expect(
            AppLaunchMode.snapshotLanguage(
                environment: [:],
                arguments: ["--snapshot-language=unsupported"]
            ) == nil
        )
    }

    @Test
    func benchmarkModeHasPriorityWhenExplicitlyEnabled() {
        #expect(AppLaunchMode.resolve(environment: ["VIBECOMPOSE_BENCHMARK": "1"]) == .benchmark)
        #expect(
            AppLaunchMode.resolve(
                environment: [
                    "VIBECOMPOSE_BENCHMARK": "true",
                    "VIBECOMPOSE_OVERLAY_DEMO": "1",
                ],
                arguments: ["VibeCompose", "--overlay-demo"]
            ) == .benchmark
        )
    }
}

@Test
func settingsSnapshotOutputImplicitlyOpensSettings() {
    #expect(
        AppLaunchMode.resolve(
            environment: [
                "VIBECOMPOSE_SETTINGS_SNAPSHOT_OUTPUT":
                    "/tmp/settings.png",
            ],
            arguments: ["VibeCompose"]
        ) == .settings
    )
}
