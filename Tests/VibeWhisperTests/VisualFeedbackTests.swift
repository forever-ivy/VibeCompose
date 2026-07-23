import AppKit
import Foundation
import Testing
@testable import VibeWhisper

@Test
func brandSelectionPaletteMatchesTheApprovedReferenceArtwork()
    throws
{
    let blue = try #require(
        VibeWhisperPalette.brandBlue
            .usingColorSpace(.sRGB)
    )
    let selection = try #require(
        VibeWhisperPalette.sidebarSelectionLightColor
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
            "Sources/VibeWhisper/AppDelegate.swift"
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
func skillConfirmationAlwaysShowsCapsuleEvenWhenDictationHUDIsHidden()
{
    let feedback = FeedbackSurfaceController(
        escapeMonitorFactory: { _ in
            FakeEscapeMonitor()
        }
    )
    defer { feedback.hide() }
    var config = VisualFeedbackConfig()
    config.mode = .hidden
    feedback.updateVisualFeedbackConfiguration(config)

    feedback.showConfirmation(title: "Email Reply")
    let confirmation = feedback.debugSnapshot
    #expect(confirmation.mode == .hidden)
    #expect(confirmation.refinedHUDIsVisible)
    #expect(!confirmation.aiActivityGlowIsVisible)
    #expect(!confirmation.escapeCancellationIsActive)
}

@MainActor
@Test
func refinedHUDShowsCapsuleConfirmationWithSkillName()
{
    let feedback = FeedbackSurfaceController(
        escapeMonitorFactory: { _ in
            FakeEscapeMonitor()
        }
    )
    defer { feedback.hide() }
    var config = VisualFeedbackConfig()
    config.mode = .refinedHUD
    feedback.updateVisualFeedbackConfiguration(config)

    feedback.showConfirmation(title: "Email Reply")
    let confirmation = feedback.debugSnapshot
    #expect(confirmation.mode == .refinedHUD)
    #expect(confirmation.refinedHUDIsVisible)
    #expect(!confirmation.aiActivityGlowIsVisible)
    #expect(!confirmation.escapeCancellationIsActive)
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
func activityGlowUsesSoftTwoLayerSystemLightRendering()
{
    let dark = AIActivityGlowVisualProfile.resolve(
        state: .recording,
        intensity: .standard,
        target: .activeDisplay,
        increaseContrast: false,
        isDarkAppearance: true
    )
    let light = AIActivityGlowVisualProfile.resolve(
        state: .recording,
        intensity: .standard,
        target: .activeDisplay,
        increaseContrast: false,
        isDarkAppearance: false
    )

    #expect(dark.segmentCount == 20)
    #expect(dark.layerStyles.count == 2)
    #expect(dark.layerStyles.map(\.blurRadius) == [30, 10])
    #expect(
        dark.layerStyles.map(\.lineWidthMultiplier)
            == [1, 0.4]
    )
    // Dark: softer luminous edge.
    #expect(dark.layerStyles[0].opacity == Float(0.18))
    #expect(dark.layerStyles[1].opacity == Float(0.44))
    // Light: denser so the edge still reads on pale wallpapers.
    #expect(light.layerStyles[0].opacity > dark.layerStyles[0].opacity)
    #expect(light.layerStyles[1].opacity > dark.layerStyles[1].opacity)
    #expect(light.layerStyles.map(\.blurRadius) == [26, 8])
    #expect(dark.breathing?.animatedLayerCount == 1)
    #expect(dark.breathing?.minimumOpacityMultiplier == 0.9)
    #expect(dark.breathing?.colorShiftFraction == 0.05)
    #expect(dark.breathing?.halfCycleDuration == 2.4)
    // Headless fallback: flat rectangle (no live NSScreen chrome).
    #expect(dark.edgeInset == 2.5)
    #expect(dark.topCornerRadius == 0)
    #expect(dark.bottomCornerRadius == 0)
    #expect(dark.chrome.topCutout == nil)
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
    // Default focused-window chrome is a modest continuous radius.
    #expect(profile.topCornerRadius >= 10)
    #expect(profile.topCornerRadius <= 16)
    #expect(profile.bottomCornerRadius == profile.topCornerRadius)
    #expect(profile.chrome.topCutout == nil)
}

@Test
func focusedWindowChromeScalesWithWindowSizeAndFullscreen()
{
    let small = DisplayChromeGeometry.forFocusedWindow(
        bloomReach: 40,
        windowSize: CGSize(width: 320, height: 240),
        isFullscreen: false
    )
    let large = DisplayChromeGeometry.forFocusedWindow(
        bloomReach: 40,
        windowSize: CGSize(width: 1600, height: 1000),
        isFullscreen: false
    )
    let fullscreen = DisplayChromeGeometry.forFocusedWindow(
        bloomReach: 40,
        windowSize: CGSize(width: 1728, height: 1117),
        isFullscreen: true
    )

    #expect(small.topLeadingRadius >= 10)
    #expect(large.topLeadingRadius >= small.topLeadingRadius)
    #expect(large.topLeadingRadius <= 16)
    // Fullscreen windows read as display edges — no window radius, no cutout.
    #expect(fullscreen.topLeadingRadius == 0)
    #expect(fullscreen.bottomTrailingRadius == 0)
    #expect(fullscreen.topCutout == nil)
    #expect(fullscreen.edgeInset < small.edgeInset)
}

@Test
func focusedWindowFrameTargetIsNoLongerMarkedExperimental()
{
    #expect(BlueSignalFrameTarget.focusedWindow.title == "Focused window")
    #expect(
        BlueSignalFrameTarget.focusedWindow.title.contains("Experimental")
            == false
    )
    #expect(
        BlueSignalFrameTarget.focusedWindow.detail
            .contains("Accessibility")
    )
}

@Test
func activityGlowAdaptsChromeForNotchedAndFlatDisplays()
{
    // Flat external monitor: sharp corners, no camera housing cutout.
    let flat = DisplayChromeGeometry(
        edgeInset: 2.5,
        topLeadingRadius: 0,
        topTrailingRadius: 0,
        bottomLeadingRadius: 0,
        bottomTrailingRadius: 0,
        topCutout: nil
    )
    let flatProfile = AIActivityGlowVisualProfile.resolve(
        state: .recording,
        intensity: .standard,
        target: .activeDisplay,
        increaseContrast: false,
        chrome: flat
    )
    #expect(flatProfile.chrome.topCutout == nil)
    #expect(flatProfile.topCornerRadius == 0)

    // Notched MacBook: rounded bezel + top-center Dynamic Island / notch.
    let notched = DisplayChromeGeometry(
        edgeInset: 3,
        topLeadingRadius: 22,
        topTrailingRadius: 22,
        bottomLeadingRadius: 22,
        bottomTrailingRadius: 22,
        topCutout: .init(
            centerX: 720,
            width: 180,
            height: 34,
            cornerRadius: 12
        )
    )
    let notchedProfile = AIActivityGlowVisualProfile.resolve(
        state: .recording,
        intensity: .standard,
        target: .activeDisplay,
        increaseContrast: false,
        chrome: notched
    )
    #expect(notchedProfile.chrome.topCutout?.width == 180)
    #expect(notchedProfile.chrome.topCutout?.height == 34)
    #expect(notchedProfile.topCornerRadius == 22)
    #expect(notchedProfile.bottomCornerRadius == 22)
}

@Test
func activityGlowUsesAsymmetricAppleStyleAppearanceTiming()
{
    #expect(
        AIActivityGlowTransitionProfile.paletteCrossfadeDuration == 0.38
    )
    #expect(AIActivityGlowTransitionProfile.appearance.duration == 0.48)
    #expect(AIActivityGlowTransitionProfile.disappearance.duration == 0.36)
    #expect(
        AIActivityGlowTransitionProfile.appearance.controlPoint1
            == CGPoint(x: 0.16, y: 1)
    )
    #expect(
        AIActivityGlowTransitionProfile.disappearance.controlPoint2
            == CGPoint(x: 0.68, y: 1)
    )
    #expect(AIActivityGlowTransitionProfile.revealDuration == 0.52)
    #expect(AIActivityGlowTransitionProfile.revealScaleFrom == 0.978)
    #expect(AIActivityGlowTransitionProfile.revealScalePeak == 1.006)
    #expect(AIActivityGlowTransitionProfile.exitDuration == 0.34)
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
    try await Task.sleep(for: .milliseconds(500))

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
            "vibewhisper.edgeGlow.ambientBreathing"
        )
    )
    #expect(
        initial.animationKeys.contains(
            "vibewhisper.edgeGlow.ambientColorBreathing"
        )
    )
    // First show also plays the soft reveal bloom.
    #expect(
        initial.animationKeys.contains(
            "vibewhisper.edgeGlow.revealScale"
        )
        || initial.animationKeys.contains(
            "vibewhisper.edgeGlow.revealFade"
        )
    )
    #expect(
        initial.animationKeys.contains(where: {
            $0.contains("traveling")
                || $0.contains("Shimmer")
                || $0.contains("colorFlow")
        }) == false
    )
    // Recording system-light profile breathes only the outer bloom layer.
    #expect(initial.ambientBreathingLayerCount == 1)
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
            "vibewhisper.edgeGlow.paletteCrossfade"
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
    let subtle = AIActivityGlowVisualProfile.resolve(
        state: .recording,
        intensity: .subtle,
        target: .activeDisplay,
        increaseContrast: false
    )

    #expect(recording.baseLineWidth == 13)
    #expect(subtle.baseLineWidth < recording.baseLineWidth)
    #expect(expressive.baseLineWidth > recording.baseLineWidth)
    // Intensity scales presence (opacity), not only stroke width.
    #expect(
        expressive.layerStyles[0].opacity
            > recording.layerStyles[0].opacity
    )
    #expect(
        subtle.layerStyles[0].opacity
            < recording.layerStyles[0].opacity
    )
    #expect(recording.breathing?.halfCycleDuration == 2.4)
    #expect(processing.breathing?.animatedLayerCount == 2)
    #expect(processing.breathing?.halfCycleDuration == 1.7)
    #expect(processing.breathing?.minimumOpacityMultiplier == 0.86)
    #expect(recording.breathing?.colorShiftFraction == 0.05)
    #expect(processing.breathing?.colorShiftFraction == 0.07)
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
    #expect(settle?.scalePeak == 1.01)
    #expect(settle?.peakOpacity == 1)
    #expect(settle?.scaleDuration == 0.4)
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
            "vibewhisper-edgeglow-\(UUID().uuidString).png"
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
