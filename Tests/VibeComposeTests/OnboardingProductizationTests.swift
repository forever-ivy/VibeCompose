import Foundation
import Testing
@testable import VibeCompose

@Test
func onboardingStateShowsUntilTheCurrentFlowIsCompleted() throws {
    let suiteName = "VibeComposeTests.Onboarding.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = OnboardingStateStore(defaults: defaults)
    #expect(store.shouldPresent())
    store.markCompleted()
    #expect(store.shouldPresent() == false)
    #expect(
        defaults.integer(forKey: OnboardingStateStore.completionKey)
            == OnboardingStateStore.currentFlowVersion
    )
}

@Test
func privateAcceptanceDoesNotPersistOnboardingCompletion() throws {
    let suiteName =
        "VibeComposeTests.Onboarding.Private.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = OnboardingStateStore(defaults: defaults)
    store.markCompleted(if: false)

    #expect(store.shouldPresent())
    #expect(
        defaults.object(
            forKey: OnboardingStateStore.completionKey
        ) == nil
    )
}

@Test
func onboardingSourceKeepsMicrophoneRequiredAndPasteOptional() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/VibeCompose/OnboardingWindowController.swift"
        ),
        encoding: .utf8
    )
    let visualSystemSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/VibeCompose/VibeComposeVisualSystem.swift"
        ),
        encoding: .utf8
    )

    #expect(source.contains("case welcome"))
    #expect(source.contains("case connect"))
    #expect(source.contains("case microphone"))
    #expect(source.contains("case practice"))
    #expect(
        source.contains(
            "Microphone access is required only while you record a dictation."
        )
    )
    #expect(source.contains("Clipboard Mode is ready"))
    #expect(source.contains("Enable Automatic Paste"))
    #expect(source.contains("TextEditor(text: $practiceText)"))
    #expect(source.contains("onRequestMicrophoneAccess"))
    #expect(source.contains("permissionMonitor.requestMicrophoneAccess"))
    #expect(
        source.contains(
            "VibeCompose still cannot confirm microphone access."
        )
    )
    #expect(source.contains("AccessibilityPermission.guideAccess()"))
    // Onboarding is a solid wizard plate — materials must not sample the
    // desktop wallpaper (grainy/speckle artifacts on macOS 26).
    #expect(source.contains("window.isOpaque = true"))
    #expect(source.contains("window.backgroundColor = .windowBackgroundColor"))
    #expect(source.contains("OnboardingProductDemo"))
    // Live material fills (not comments) must stay out of the wizard stage.
    #expect(!source.contains(".fill(.ultraThinMaterial)"))
    #expect(!source.contains(".glassEffect("))
    // GlassEffectContainer can swallow hits for solid CTAs on macOS 26.
    #expect(!source.contains("GlassEffectContainer"))
    // Mandatory first-run: block dismissal until Finish Setup.
    #expect(source.contains("blocksUntilCompleted"))
    #expect(source.contains("windowShouldClose"))
    // First click on every CTA must work — window is key + centered on the
    // active screen (not only NSWindow.center on the primary display).
    #expect(source.contains("centerOnActiveScreen"))
    #expect(source.contains("override var canBecomeKey: Bool { true }"))
    #expect(source.contains("NSApp.activate(ignoringOtherApps: true)"))
    #expect(source.contains("acceptsFirstMouse"))
    #expect(source.contains("OnboardingHostingView"))
    // CTAs use PrimitiveButtonStyle so the action rides a real Button, not a
    // custom gesture that can miss first-click on macOS 26.
    #expect(source.contains("VibeComposeOnboardingCTAButtonStyle"))
    #expect(
        visualSystemSource.contains(
            "struct VibeComposeOnboardingCTAButtonStyle: PrimitiveButtonStyle"
        )
    )
    #expect(
        visualSystemSource.contains(
            "struct VibeComposeOnboardingSecondaryButtonStyle: PrimitiveButtonStyle"
        )
    )
}

@Test
func onboardingStepsExposeStableAcceptanceArguments() {
    #expect(OnboardingStep.welcome.launchArgumentValue == "welcome")
    #expect(OnboardingStep.showcase.launchArgumentValue == "showcase")
    #expect(OnboardingStep.connect.launchArgumentValue == "connect")
    #expect(OnboardingStep.microphone.launchArgumentValue == "microphone")
    #expect(OnboardingStep.practice.launchArgumentValue == "practice")
    #expect(OnboardingStep.fromLaunchArgument("account") == .connect)
    #expect(OnboardingStep.fromLaunchArgument("mic") == .microphone)
    #expect(OnboardingStep.fromLaunchArgument("skills") == .showcase)
    #expect(OnboardingStep.fromLaunchArgument("modes") == .showcase)
    #expect(
        OnboardingStep.fromLaunchArgument("paste_and_practice")
            == .practice
    )
    #expect(OnboardingStep.fromLaunchArgument("unknown") == nil)
}
