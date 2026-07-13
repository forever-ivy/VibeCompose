import Foundation
import Testing
@testable import OpenWhisper

@Test
func onboardingStateShowsUntilTheCurrentFlowIsCompleted() throws {
    let suiteName = "OpenWhisperTests.Onboarding.\(UUID().uuidString)"
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
        "OpenWhisperTests.Onboarding.Private.\(UUID().uuidString)"
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
func onboardingSourceKeepsPermissionsRequiredAndOptional() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/OpenWhisper/OnboardingWindowController.swift"
        ),
        encoding: .utf8
    )

    #expect(source.contains("case welcome"))
    #expect(source.contains("case connect"))
    #expect(source.contains("case microphone"))
    #expect(source.contains("case practice"))
    #expect(source.contains("Microphone is required"))
    #expect(source.contains("Accessibility is optional"))
    #expect(source.contains("TextEditor(text: $practiceText)"))
    #expect(source.contains("onRequestMicrophoneAccess"))
    #expect(source.contains("permissionMonitor.requestMicrophoneAccess"))
    #expect(
        source.contains(
            "OpenWhisper still cannot confirm microphone access."
        )
    )
    #expect(source.contains("AccessibilityPermission.guideAccess()"))
}

@Test
func onboardingStepsExposeStableAcceptanceArguments() {
    #expect(OnboardingStep.welcome.launchArgumentValue == "welcome")
    #expect(OnboardingStep.connect.launchArgumentValue == "connect")
    #expect(OnboardingStep.microphone.launchArgumentValue == "microphone")
    #expect(OnboardingStep.practice.launchArgumentValue == "practice")
    #expect(OnboardingStep.fromLaunchArgument("account") == .connect)
    #expect(OnboardingStep.fromLaunchArgument("mic") == .microphone)
    #expect(
        OnboardingStep.fromLaunchArgument("paste_and_practice")
            == .practice
    )
    #expect(OnboardingStep.fromLaunchArgument("unknown") == nil)
}
