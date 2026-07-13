import AppKit
import Foundation
import Testing
@testable import OpenWhisper

@Test
func appDelegateUsesUnifiedFeedbackSurfaceAtRuntime() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/OpenWhisper/AppDelegate.swift"
        ),
        encoding: .utf8
    )

    #expect(
        source.contains(
            "let overlay = FeedbackSurfaceController("
        )
    )
    #expect(
        !source.contains(
            "let overlay = OverlayController("
        )
    )
}

@Test
func visualFeedbackConfigurationDefaultsAndRoundTrips()
    throws
{
    let config = VisualFeedbackConfig()
    #expect(config.mode == .refinedHUD)
    #expect(config.intensity == .standard)
    #expect(config.frameTarget == .activeDisplay)
    #expect(config.showStatusText)
    #expect(!config.completionNotificationEnabled)
    #expect(!config.alwaysReduceMotion)

    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(
        VisualFeedbackConfig.self,
        from: data
    )
    #expect(decoded == config)
}

@Test
func visualFeedbackConfigurationFallsBackFromUnknownEnumValues()
    throws
{
    let data = """
    {
      "mode": "future-mode",
      "intensity": "future-intensity",
      "frameTarget": "future-target"
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(
        VisualFeedbackConfig.self,
        from: data
    )
    #expect(decoded.mode == .refinedHUD)
    #expect(decoded.intensity == .standard)
    #expect(decoded.frameTarget == .activeDisplay)
}

@MainActor
private final class FakeEscapeMonitor {}

@MainActor
@Test
func hiddenFeedbackCreatesNoVisibleSurfaceAndKeepsEscapeCancellation()
{
    let feedback = FeedbackSurfaceController(
        escapeMonitorFactory: { _ in
            FakeEscapeMonitor()
        }
    )
    var config = VisualFeedbackConfig()
    config.mode = .hidden
    feedback.updateVisualFeedbackConfiguration(
        config
    )

    feedback.showRecording(elapsedText: "00:04")
    let recording = feedback.debugSnapshot
    #expect(recording.mode == .hidden)
    #expect(!recording.refinedHUDIsVisible)
    #expect(!recording.blueSignalFrameIsVisible)
    #expect(recording.escapeCancellationIsActive)

    feedback.showResult(
        text: "Done",
        outcome: .insertedAndVerified
    )
    let result = feedback.debugSnapshot
    #expect(!result.refinedHUDIsVisible)
    #expect(!result.blueSignalFrameIsVisible)
    #expect(!result.escapeCancellationIsActive)
    feedback.hide()
}

@MainActor
@Test
func blueSignalUsesTheFrameForActiveStatesAndTextForCopiedOutcome()
{
    let feedback = FeedbackSurfaceController(
        escapeMonitorFactory: { _ in
            FakeEscapeMonitor()
        }
    )
    var config = VisualFeedbackConfig()
    config.mode = .blueSignalFrame
    config.showStatusText = true
    feedback.updateVisualFeedbackConfiguration(
        config
    )

    feedback.showProcessing()
    let processing = feedback.debugSnapshot
    #expect(processing.blueSignalFrameIsVisible)
    #expect(!processing.refinedHUDIsVisible)
    #expect(processing.escapeCancellationIsActive)

    feedback.showResult(
        text: "Done",
        outcome: .copiedToClipboard(
            reason: .noEditableTarget
        )
    )
    let copied = feedback.debugSnapshot
    #expect(copied.blueSignalFrameIsVisible)
    #expect(copied.refinedHUDIsVisible)
    #expect(!copied.escapeCancellationIsActive)
    feedback.hide()
}

@MainActor
@Test
func blueSignalAlwaysReduceMotionDisablesContinuousAnimation()
{
    let controller = BlueSignalFrameController(
        accessibilityDisplayOptionsProvider: {
            AccessibilityDisplayOptions(
                reduceMotion: false,
                increaseContrast: false
            )
        }
    )
    var config = VisualFeedbackConfig()
    config.alwaysReduceMotion = true
    controller.show(
        state: .processing,
        level: 0,
        config: config
    )
    #expect(
        controller.debugSnapshot
            .animationIsActive == false
    )
    controller.hide()
}
