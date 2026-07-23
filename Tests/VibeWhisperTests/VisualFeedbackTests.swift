import AppKit
import Foundation
import Testing
@testable import OpenWhisper

@Test
func brandSelectionPaletteMatchesTheApprovedReferenceArtwork()
    throws
{
    let blue = try #require(
        OpenWhisperPalette.brandBlue
            .usingColorSpace(.sRGB)
    )
    let selection = try #require(
        OpenWhisperPalette.sidebarSelectionLightColor
            .usingColorSpace(.sRGB)
    )

    #expect(Int((blue.redComponent * 255).rounded()) == 0)
    #expect(Int((blue.greenComponent * 255).rounded()) == 116)
    #expect(Int((blue.blueComponent * 255).rounded()) == 255)
    #expect(Int((selection.redComponent * 255).rounded()) == 239)
    #expect(Int((selection.greenComponent * 255).rounded()) == 239)
    #expect(Int((selection.blueComponent * 255).rounded()) == 239)
}

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

@Test
func visualFeedbackMigratesLegacyBlueFrameAndWritesActivityGlow()
    throws
{
    let legacy = try JSONDecoder().decode(
        VisualFeedbackMode.self,
        from: Data("\"blueSignalFrame\"".utf8)
    )
    #expect(legacy == .aiActivityGlow)

    let encoded = try JSONEncoder().encode(legacy)
    #expect(String(data: encoded, encoding: .utf8) == "\"aiActivityGlow\"")
    #expect(
        VisualFeedbackMode.fromLaunchValue("blue-signal-frame")
            == .aiActivityGlow
    )
    #expect(
        VisualFeedbackMode.fromLaunchValue("ai-activity-glow")
            == .aiActivityGlow
    )
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
    #expect(!recording.aiActivityGlowIsVisible)
    #expect(recording.escapeCancellationIsActive)

    feedback.showResult(
        text: "Done",
        outcome: .insertedAndVerified
    )
    let result = feedback.debugSnapshot
    #expect(!result.refinedHUDIsVisible)
    #expect(!result.aiActivityGlowIsVisible)
    #expect(!result.escapeCancellationIsActive)
    feedback.hide()
}

@MainActor
@Test
func activityGlowUsesTheFrameForActiveStatesAndTextForCopiedOutcome()
{
    let feedback = FeedbackSurfaceController(
        escapeMonitorFactory: { _ in
            FakeEscapeMonitor()
        }
    )
    var config = VisualFeedbackConfig()
    config.mode = .aiActivityGlow
    config.showStatusText = true
    feedback.updateVisualFeedbackConfiguration(
        config
    )

    feedback.showProcessing()
    let processing = feedback.debugSnapshot
    #expect(processing.aiActivityGlowIsVisible)
    #expect(!processing.refinedHUDIsVisible)
    #expect(processing.aiActivityGlowState == .processing)
    #expect(processing.escapeCancellationIsActive)

    feedback.showResult(
        text: "Done",
        outcome: .copiedToClipboard(
            reason: .noEditableTarget
        )
    )
    let copied = feedback.debugSnapshot
    #expect(copied.aiActivityGlowIsVisible)
    #expect(copied.refinedHUDIsVisible)
    #expect(!copied.escapeCancellationIsActive)
    feedback.hide()
}

@MainActor
@Test
func activityGlowRemainsVisibleWhenRecordingTransitionsToProcessing()
    async throws
{
    let feedback = FeedbackSurfaceController(
        escapeMonitorFactory: { _ in
            FakeEscapeMonitor()
        }
    )
    defer { feedback.hide() }
    var config = VisualFeedbackConfig()
    config.mode = .aiActivityGlow
    feedback.updateVisualFeedbackConfiguration(config)

    feedback.showRecording(elapsedText: "00:04")
    feedback.updateRecording(
        level: 0.72,
        elapsedText: "00:04"
    )
    feedback.showProcessing()

    try await Task.sleep(for: .milliseconds(380))
    let processing = feedback.debugSnapshot
    #expect(processing.aiActivityGlowIsVisible)
    #expect(processing.aiActivityGlowState == .processing)
    #expect(processing.aiActivityGlowAnimationIsActive)
    #expect(!processing.refinedHUDIsVisible)
    #expect(processing.escapeCancellationIsActive)
}

@MainActor
@Test
func activityGlowAlwaysReduceMotionDisablesContinuousAnimation()
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

@Test
func activityGlowUsesFourLayerSmoothFixedGradientRendering()
{
    let profile = AIActivityGlowVisualProfile.resolve(
        state: .recording,
        intensity: .standard,
        target: .activeDisplay,
        increaseContrast: false
    )

    #expect(profile.segmentCount == 32)
    #expect(profile.layerStyles.count == 4)
    #expect(profile.layerStyles.map(\.blurRadius) == [20, 12, 4, 0])
    #expect(
        profile.layerStyles.map(\.lineWidthMultiplier)
            == [1, 0.58, 0.24, 0.12]
    )
    #expect(profile.breathing?.animatedLayerCount == 2)
    #expect(profile.breathing?.minimumOpacityMultiplier == 0.76)
    #expect(profile.breathing?.colorShiftFraction == 0.14)
    #expect(profile.edgeInset == 1.5)
    #expect(profile.topCornerRadius == 18)
    #expect(profile.bottomCornerRadius == 0)
}

@Test
func activityGlowReservesEnoughCanvasForFocusedWindowBloom()
{
    let profile = AIActivityGlowVisualProfile.resolve(
        state: .recording,
        intensity: .expressive,
        target: .focusedWindow,
        increaseContrast: false
    )
    let widestLayer = profile.layerStyles[0]
    let requiredBloomRoom = profile.baseLineWidth
        * widestLayer.lineWidthMultiplier / 2
        + widestLayer.blurRadius

    #expect(profile.edgeInset >= requiredBloomRoom + 4)
    #expect(profile.topCornerRadius == 17)
    #expect(profile.bottomCornerRadius == 0)
}

@Test
func activityGlowUsesAsymmetricAppleStyleAppearanceTiming()
{
    #expect(
        AIActivityGlowTransitionProfile.paletteCrossfadeDuration == 0.35
    )
    #expect(AIActivityGlowTransitionProfile.appearance.duration == 0.32)
    #expect(AIActivityGlowTransitionProfile.disappearance.duration == 0.28)
    #expect(
        AIActivityGlowTransitionProfile.appearance.controlPoint1
            == CGPoint(x: 0.22, y: 1)
    )
    #expect(
        AIActivityGlowTransitionProfile.disappearance.controlPoint2
            == CGPoint(x: 0.6, y: 1)
    )
}

@MainActor
@Test
func activityGlowCanReverseADisappearanceWithoutBeingOrderedOut()
    async throws
{
    let controller = BlueSignalFrameController(
        accessibilityDisplayOptionsProvider: {
            AccessibilityDisplayOptions(
                reduceMotion: false,
                increaseContrast: false
            )
        }
    )
    defer { controller.hide() }

    controller.show(
        state: .recording,
        level: 0,
        config: VisualFeedbackConfig()
    )
    controller.hide()
    #expect(controller.debugSnapshot.isVisible == false)
    #expect(controller.debugSnapshot.panelIsVisible == true)

    controller.show(
        state: .processing,
        level: 0,
        config: VisualFeedbackConfig()
    )
    try await Task.sleep(for: .milliseconds(380))

    #expect(controller.debugSnapshot.isVisible)
    #expect(controller.debugSnapshot.panelIsVisible)
}

@MainActor
@Test
func activityGlowKeepsTheCoreSteadyWhileAmbientLayersBreatheTogether()
{
    let controller = BlueSignalFrameController(
        accessibilityDisplayOptionsProvider: {
            AccessibilityDisplayOptions(
                reduceMotion: false,
                increaseContrast: false
            )
        }
    )
    defer { controller.hide() }

    controller.show(
        state: .recording,
        level: 0.1,
        config: VisualFeedbackConfig()
    )
    let initial = controller.debugSnapshot
    controller.updateRecordingLevel(0.95)
    let updated = controller.debugSnapshot

    #expect(
        initial.animationKeys.contains(
            "openwhisper.edgeGlow.ambientBreathing"
        )
    )
    #expect(
        initial.animationKeys.contains(
            "openwhisper.edgeGlow.ambientColorBreathing"
        )
    )
    #expect(
        initial.animationKeys.contains(where: {
            $0.contains("traveling")
                || $0.contains("Shimmer")
                || $0.contains("colorFlow")
        }) == false
    )
    #expect(initial.ambientBreathingLayerCount == 2)
    #expect(initial.glowOpacity == updated.glowOpacity)
}

@MainActor
@Test
func activityGlowCrossfadesStateColorsWithoutMovingTheGradient()
{
    let controller = BlueSignalFrameController(
        accessibilityDisplayOptionsProvider: {
            AccessibilityDisplayOptions(
                reduceMotion: false,
                increaseContrast: false
            )
        }
    )
    defer { controller.hide() }

    controller.show(
        state: .recording,
        level: 0,
        config: VisualFeedbackConfig()
    )
    controller.show(
        state: .processing,
        level: 0,
        config: VisualFeedbackConfig()
    )

    let animationKeys = controller.debugSnapshot.animationKeys
    #expect(
        animationKeys.contains(
            "openwhisper.edgeGlow.paletteCrossfade"
        )
    )
    #expect(
        animationKeys.contains(where: {
            $0.contains("traveling")
                || $0.contains("Shimmer")
                || $0.contains("colorFlow")
        }) == false
    )
}

@Test
func activityGlowUsesIntensityForWidthAndDistinctProcessingBreathing()
{
    let recording = AIActivityGlowVisualProfile.resolve(
        state: .recording,
        intensity: .standard,
        target: .activeDisplay,
        increaseContrast: false
    )
    let processing = AIActivityGlowVisualProfile.resolve(
        state: .processing,
        intensity: .standard,
        target: .activeDisplay,
        increaseContrast: false
    )
    let expressive = AIActivityGlowVisualProfile.resolve(
        state: .recording,
        intensity: .expressive,
        target: .activeDisplay,
        increaseContrast: false
    )

    #expect(recording.baseLineWidth == 20)
    #expect(expressive.baseLineWidth > recording.baseLineWidth)
    #expect(recording.breathing?.halfCycleDuration == 1.6)
    #expect(processing.breathing?.animatedLayerCount == 3)
    #expect(processing.breathing?.halfCycleDuration == 0.95)
    #expect(processing.breathing?.minimumOpacityMultiplier == 0.58)
    #expect(recording.breathing?.colorShiftFraction == 0.14)
    #expect(processing.breathing?.colorShiftFraction == 0.22)
}

@Test
func activityGlowTerminalStatesSettleWithoutFlashing()
{
    func motion(for state: AIActivityGlowState) -> AIActivityGlowMotion {
        AIActivityGlowVisualProfile.resolve(
            state: state,
            intensity: .standard,
            target: .activeDisplay,
            increaseContrast: false
        ).motion
    }

    #expect(motion(for: .recording) == .breathe)
    #expect(motion(for: .processing) == .breathe)
    #expect(motion(for: .success) == .settle)
    #expect(motion(for: .copied) == .settle)
    #expect(motion(for: .error) == .settle)
}

@Test
func activityGlowTerminalStatesPlayAOneShotSettlePulse()
{
    func profile(for state: AIActivityGlowState) -> AIActivityGlowVisualProfile {
        AIActivityGlowVisualProfile.resolve(
            state: state,
            intensity: .standard,
            target: .activeDisplay,
            increaseContrast: false
        )
    }

    #expect(profile(for: .recording).settle == nil)
    #expect(profile(for: .processing).settle == nil)
    #expect(profile(for: .success).settle != nil)
    #expect(profile(for: .copied).settle != nil)
    #expect(profile(for: .error).settle != nil)

    let settle = profile(for: .success).settle
    #expect(settle?.scalePeak == 1.02)
    #expect(settle?.peakOpacity == 1)
    #expect(settle?.scaleDuration == 0.46)
}

@MainActor
@Test
func activityGlowSnapshotLightsTheEdgeWithoutCrossingTheContentArea()
    throws
{
    let controller = BlueSignalFrameController(
        accessibilityDisplayOptionsProvider: {
            AccessibilityDisplayOptions(
                reduceMotion: true,
                increaseContrast: false
            )
        }
    )
    let output = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "openwhisper-edgeglow-\(UUID().uuidString).png"
        )
    defer {
        controller.hide()
        try? FileManager.default.removeItem(at: output)
    }

    controller.show(
        state: .recording,
        level: 0.72,
        config: VisualFeedbackConfig()
    )
    try controller.writeSnapshot(to: output)

    let data = try Data(contentsOf: output)
    let bitmap = try #require(NSBitmapImageRep(data: data))
    let center = try #require(
        bitmap.colorAt(
            x: bitmap.pixelsWide / 2,
            y: bitmap.pixelsHigh / 2
        )
    )
    #expect(center.alphaComponent < 0.01)

    let sampleStep = max(1, bitmap.pixelsWide / 80)
    let edgeIsLit = stride(
        from: 0,
        to: bitmap.pixelsWide,
        by: sampleStep
    ).contains { x in
        let bottom = bitmap.colorAt(x: x, y: 4)?.alphaComponent ?? 0
        let top = bitmap.colorAt(
            x: x,
            y: max(0, bitmap.pixelsHigh - 5)
        )?.alphaComponent ?? 0
        return max(bottom, top) > 0.02
    }
    #expect(edgeIsLit)
}
