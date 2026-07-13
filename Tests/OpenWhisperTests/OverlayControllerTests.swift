import AppKit
import CoreGraphics
import Testing
@testable import OpenWhisper

@Test
func minimalOverlayPresetUsesNineBarVoiceGlyph() {
    let preset = OverlayStylePreset.dictationHUD

    #expect(preset.primaryPillWidth == 284)
    #expect(preset.primaryPillHeight == 44)
    #expect(preset.errorPillWidth == 320)
    #expect(preset.errorPillHeight == 56)
    #expect(preset.cornerRadius == 16)
    #expect(preset.topInset == 16)
    #expect(preset.waveformBarCount == 9)
    #expect(preset.showsTranscriptPreview == false)
    #expect(preset.inlineCancelControlSize == 14)
    #expect(preset.timerFontSize == 10)
    #expect(preset.errorAutoHideDelay == 5)
}

@Test
func overlayStatesStillDifferentiateLeadingVisualFamilies() {
    #expect(OverlayVisualState.recording(levels: Array(repeating: 0.2, count: 9), elapsedText: "00:03").leadingVisual == .waveform)
    #expect(OverlayVisualState.processing.leadingVisual == .waveform)
    #expect(OverlayVisualState.success(.inserted).leadingVisual == .icon(symbolName: "checkmark.circle.fill"))
    #expect(OverlayVisualState.success(.pasteSent).leadingVisual == .icon(symbolName: "arrow.right.circle.fill"))
    #expect(OverlayVisualState.success(.copied).leadingVisual == .icon(symbolName: "doc.on.clipboard.fill"))
    #expect(OverlayVisualState.error("Microphone permission is missing").leadingVisual == .icon(symbolName: "exclamationmark.triangle.fill"))
}

@Test
func overlayStatesStayCompactExceptErrors() {
    #expect(OverlayVisualState.recording(levels: Array(repeating: 0.2, count: 9), elapsedText: "00:03").allowsSupplementaryText == false)
    #expect(OverlayVisualState.processing.allowsSupplementaryText == false)
    #expect(OverlayVisualState.success(.inserted).allowsSupplementaryText == false)
    #expect(OverlayVisualState.error("Microphone permission is missing").allowsSupplementaryText == true)
}

@Test
func recordingOverlayStateShowsCancelControlAndTimer() {
    let state = OverlayVisualState.recording(
        levels: Array(repeating: 0.2, count: 9),
        elapsedText: "00:07"
    )

    #expect(state.showsCancelControl == true)
    #expect(state.trailingText == "00:07")
}

@Test
func processingOverlayStateShowsCancelControlWithoutTimer() {
    #expect(OverlayVisualState.processing.showsCancelControl == true)
    #expect(OverlayVisualState.processing.trailingText == nil)
}

@Test
func successAndOrdinaryErrorStatesRemainNonInteractive() {
    #expect(OverlayVisualState.success(.inserted).showsCancelControl == false)
    #expect(OverlayVisualState.error("boom").showsCancelControl == false)
    #expect(OverlayVisualState.error("boom").showsRetryControl == false)
}

@Test
func retryableErrorStateShowsRetryControlWithoutCancelControl() {
    let state = OverlayVisualState.retryableError("Cloudflare 403")

    #expect(state.showsCancelControl == false)
    #expect(state.showsRetryControl == true)
    #expect(state.trailingText == nil)
}

@Test
func overlayErrorMessageIsCollapsedToSingleShortLine() {
    let state = OverlayVisualState.error("Microphone permission is missing.\nGrant access in Settings and try again after restarting OpenWhisper.")

    #expect(state.supplementaryText == "Microphone permission is missing. Grant access in Settings and try…")
}

@Test
func waveformNormalizerClampsSilenceAndLoudInput() {
    #expect(WaveformNormalizer.normalizedLevel(fromAveragePower: -160) == 0.08)
    #expect(WaveformNormalizer.normalizedLevel(fromAveragePower: 0) == 1)
}

@Test
func waveformNormalizerRecordingProfileStaysSymmetricAndWithinBounds() {
    let smoothed = WaveformNormalizer.smoothedLevels(
        previous: Array(repeating: 0.12, count: 9),
        targetLevel: 0.9,
        barCount: 9
    )

    #expect(smoothed.count == 9)
    #expect(smoothed.allSatisfy { $0 >= 0.08 && $0 <= 1 })
    #expect(smoothed[4] > smoothed[0])
    #expect(smoothed[4] > smoothed[8])
    #expect(abs(smoothed[0] - smoothed[8]) < 0.0001)
}

@Test
func waveformNormalizerProcessingPulseTravelsAcrossTheGlyph() {
    let early = WaveformNormalizer.processingPulseLevels(frame: 0, barCount: 9)
    let later = WaveformNormalizer.processingPulseLevels(frame: 5, barCount: 9)

    #expect(early.count == 9)
    #expect(later.count == 9)
    #expect(early.allSatisfy { $0 >= 0.08 && $0 <= 1 })
    #expect(later.allSatisfy { $0 >= 0.08 && $0 <= 1 })
    #expect(early != later)
    #expect(early.max() != later.max())
}

@Test
func waveformNormalizerPadsMissingSamplesToTheRequestedWaveCount() {
    let smoothed = WaveformNormalizer.smoothedLevels(
        previous: [0.2, 0.3, 0.4],
        targetLevel: 0.6,
        barCount: 9
    )

    #expect(smoothed.count == 9)
    #expect(smoothed.allSatisfy { $0 >= 0.08 && $0 <= 1 })
}

@Test
func overlayPrimaryStatesUseStableGeometryAndErrorsHaveRoomForRecoveryCopy() {
    let preset = OverlayStylePreset.dictationHUD
    let recordingSize = preset.size(
        for: .recording(
            levels: Array(repeating: 0.2, count: 9),
            elapsedText: "00:07"
        )
    )

    #expect(recordingSize == preset.size(for: .processing))
    #expect(recordingSize == preset.size(for: .success(.inserted)))
    #expect(preset.size(for: .error("boom")).width == preset.errorPillWidth)
    #expect(preset.size(for: .error("boom")).height == preset.errorPillHeight)
    #expect(recordingSize.width >= preset.inlineControlReservedWidth)
}

@Test
func reducedMotionProcessingProfileIsStaticCenteredAndVisible() {
    let levels = WaveformNormalizer.reducedMotionProcessingLevels(barCount: 9)

    #expect(levels.count == 9)
    #expect(levels.allSatisfy { $0 >= 0.08 && $0 <= 1 })
    #expect(levels[4] > levels[0])
    #expect(abs(levels[0] - levels[8]) < 0.0001)
}

@MainActor
@Test
func overlayControllerIncreaseContrastStrengthensShellTextAndControls() {
    let standard = OverlayController(
        accessibilityDisplayOptionsProvider: {
            AccessibilityDisplayOptions(
                reduceMotion: false,
                increaseContrast: false
            )
        }
    )
    let increased = OverlayController(
        accessibilityDisplayOptionsProvider: {
            AccessibilityDisplayOptions(
                reduceMotion: false,
                increaseContrast: true
            )
        }
    )
    defer {
        standard.hide()
        increased.hide()
    }

    standard.showRetryableError("Cloudflare 403")
    increased.showRetryableError("Cloudflare 403")

    let standardAppearance = standard.debugSnapshot.accessibilityAppearance
    let increasedAppearance = increased.debugSnapshot.accessibilityAppearance
    #expect(
        increasedAppearance.backgroundBorderWidth
            > standardAppearance.backgroundBorderWidth
    )
    #expect(
        increasedAppearance.backgroundBorderAlpha
            > standardAppearance.backgroundBorderAlpha
    )
    #expect(standardAppearance.detailUsesPrimaryText == false)
    #expect(increasedAppearance.detailUsesPrimaryText == true)
    #expect(increasedAppearance.timerOpacity > standardAppearance.timerOpacity)
    #expect(
        increasedAppearance.cancelControlOpacity
            > standardAppearance.cancelControlOpacity
    )
    #expect(
        increasedAppearance.retryControlOpacity
            > standardAppearance.retryControlOpacity
    )
    #expect(
        increasedAppearance.waveformBaseOpacity
            > standardAppearance.waveformBaseOpacity
    )
}

@MainActor
@Test
func overlayControllerReducedMotionUsesStaticProcessingWaveform() async {
    let overlay = OverlayController(
        accessibilityDisplayOptionsProvider: {
            AccessibilityDisplayOptions(
                reduceMotion: true,
                increaseContrast: false
            )
        }
    )
    defer { overlay.hide() }

    overlay.showProcessing()
    let initial = overlay.debugSnapshot
    try? await Task.sleep(nanoseconds: 180_000_000)
    let followup = overlay.debugSnapshot

    #expect(initial.processingAnimationIsActive == false)
    #expect(followup.processingAnimationIsActive == false)
    #expect(
        initial.displayedLevels
            == WaveformNormalizer.reducedMotionProcessingLevels(barCount: 9)
    )
    #expect(followup.displayedLevels == initial.displayedLevels)
}

@Test
func overlayPresentationGenerationRejectsStaleCompletions() {
    var generation = OverlayPresentationGeneration()
    let first = generation.beginPresentation()
    let second = generation.beginPresentation()

    #expect(first != second)
    #expect(generation.isCurrent(first) == false)
    #expect(generation.isCurrent(second))
}

@MainActor
@Test
func overlayPanelPlacementStaysNearTopEdge() {
    let preset = OverlayStylePreset.dictationHUD
    let visibleFrame = CGRect(x: 40, y: 30, width: 1440, height: 860)
    let frame = OverlayController.panelFrame(
        for: preset.size(for: .processing),
        in: visibleFrame,
        topInset: preset.topInset
    )

    #expect(
        frame.maxY
            == visibleFrame.maxY
                - preset.topInset
    )
    #expect(abs(frame.midX - visibleFrame.midX) < 0.0001)
}

@MainActor
@Test
func overlayControllerUsesIntegratedSessionControlInsideMainPanel() {
    let overlay = OverlayController()
    let snapshot = overlay.debugSnapshot

    #expect(snapshot.usesIntegratedSessionControl == true)
    #expect(snapshot.hasDetachedClosePanel == false)
    #expect(snapshot.panelIgnoresMouseEvents == false)
}

@MainActor
@Test
func overlayControllerOnlyShowsInlineCancelControlForActiveSessionStates() {
    let overlay = OverlayController()

    overlay.showRecording(elapsedText: "00:04")
    #expect(overlay.debugSnapshot.isCancelControlVisible == true)
    #expect(overlay.debugSnapshot.isTimerVisible == true)

    overlay.showProcessing()
    #expect(overlay.debugSnapshot.isCancelControlVisible == true)
    #expect(overlay.debugSnapshot.isTimerVisible == false)

    overlay.showResult(text: "Done", outcome: .insertedAndVerified)
    #expect(overlay.debugSnapshot.isCancelControlVisible == false)
    #expect(overlay.debugSnapshot.isRetryControlVisible == false)
}

@MainActor
@Test
func overlayControllerRetryableErrorShowsRetryControlOnly() {
    let overlay = OverlayController()
    defer { overlay.hide() }

    overlay.showResult(text: "Done", outcome: .insertedAndVerified)
    let resultGeneration = overlay.debugSnapshot.presentationGeneration
    overlay.showRetryableError("Cloudflare 403")

    #expect(overlay.debugSnapshot.isCancelControlVisible == false)
    #expect(overlay.debugSnapshot.isRetryControlVisible == true)
    #expect(overlay.debugSnapshot.presentationGeneration > resultGeneration)
    #expect(overlay.debugSnapshot.panelIsVisible)
}

@MainActor
@Test
func overlayControllerCancelControlRoutesClickIntoOnCancel() {
    var cancelCallCount = 0
    var cancelSource: OverlayCancelSource?
    let overlay = OverlayController(onCancel: { source in
        cancelCallCount += 1
        cancelSource = source
    })

    overlay.showRecording(elapsedText: "00:04")

    #expect(overlay.debugSimulateCancelControlClick() == true)
    #expect(cancelCallCount == 1)
    #expect(cancelSource == .inlineClose)
}

@Test
func overlayRecordingCopyExplainsHowToSubmitForTranscription() {
    let state = OverlayVisualState.recording(
        levels: Array(repeating: 0.2, count: 9),
        elapsedText: "00:04"
    )

    #expect(state.label == "F5 again to transcribe")
}

@MainActor
@Test
func overlayControllerRetryControlRoutesClickIntoOnRetry() {
    var retryCallCount = 0
    let overlay = OverlayController(onRetry: {
        retryCallCount += 1
    })

    overlay.showRetryableError("Cloudflare 403")

    #expect(overlay.debugSimulateRetryControlClick() == true)
    #expect(retryCallCount == 1)
}

@MainActor
@Test
func overlayControllerWritesSelfRenderedPNGSnapshot() throws {
    let overlay = OverlayController()
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("openwhisper-overlay-\(UUID().uuidString).png")
    defer {
        overlay.hide()
        try? FileManager.default.removeItem(at: outputURL)
    }

    overlay.showRetryableError("Cloudflare 403")
    try overlay.writeSnapshot(to: outputURL)

    let data = try Data(contentsOf: outputURL)
    let bitmap = try #require(NSBitmapImageRep(data: data))
    #expect(data.count > 1_000)
    #expect(bitmap.pixelsWide > 0)
    #expect(bitmap.pixelsHigh > 0)
}
