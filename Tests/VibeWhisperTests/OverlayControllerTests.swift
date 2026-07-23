import AppKit
import CoreGraphics
import Testing
@testable import VibeWhisper

@Test
func nativeAppKitOverlayPresetUsesNineBarVoiceGlyph() {
    let preset = OverlayStylePreset.dictationHUD

    // Visible glass capsule is always 44×R22. Liquid Glass fills the panel;
    // pre-26 keeps a 6-pt elevation plate around that silhouette.
    let liquid = VibeWhisperFloatingChrome.usesSystemLiquidGlass
    let expectedChrome: CGFloat = liquid ? 0 : 6
    let expectedPanelHeight: CGFloat = liquid ? 44 : 56
    let expectedPanelWidth: CGFloat = liquid ? 272 : 284

    #expect(preset.primaryPillWidth == expectedPanelWidth)
    #expect(preset.primaryPillHeight == expectedPanelHeight)
    #expect(preset.errorPillWidth == expectedPanelWidth)
    #expect(preset.errorPillHeight == expectedPanelHeight)
    #expect(preset.chromeInset == expectedChrome)
    #expect(
        preset.primaryPillWidth - (preset.chromeInset * 2) == 272
    )
    #expect(
        preset.primaryPillHeight - (preset.chromeInset * 2) == 44
    )
    // True capsule: corner radius is half the visible glass height.
    #expect(
        preset.cornerRadius
            == (preset.primaryPillHeight - preset.chromeInset * 2) / 2
    )
    #expect(preset.cornerRadius == 22)
    #expect(preset.topInset == 14)
    #expect(preset.waveformBarCount == 5)
    #expect(preset.showsTranscriptPreview == false)
    #expect(preset.inlineCancelControlSize == 16)
    #expect(preset.timerFontSize == 12)
    #expect(preset.errorAutoHideDelay == 4)
    #expect(preset.leadingVisualWidth == 28)
    #expect(preset.textGap == 14)
    #expect(preset.timerOpacity == 1)
    #expect(preset.timerWidth == 36)
}

@Test
func nativeAppKitHudLeavesRoomForChineseSkillAndShortcutCopy() {
    let preset = OverlayStylePreset.dictationHUD
    let sample = "代码提示词"
    let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
    let titleWidth = (sample as NSString).size(
        withAttributes: [.font: font]
    ).width
    // Recording content can expand up to primary max; skill names must fit.
    let maxRecordingContent = preset.primaryPillWidth
        - (preset.chromeInset * 2)
    let reserved = (preset.contentPaddingH * 2)
        + preset.leadingVisualWidth
        + preset.textGap
        + preset.textGap
        + preset.timerWidth
        + preset.inlineControlGap
        + preset.inlineCancelControlSize
    let availableTitleWidth = maxRecordingContent - reserved

    #expect(titleWidth <= availableTitleWidth)
}

@Test
func overlayStatesStillDifferentiateLeadingVisualFamilies() {
    #expect(OverlayVisualState.recording(levels: Array(repeating: 0.2, count: 9), elapsedText: "00:03").leadingVisual == .waveform)
    #expect(OverlayVisualState.processing.leadingVisual == .waveform)
    #expect(OverlayVisualState.success(.inserted).leadingVisual == .icon(symbolName: "checkmark.circle.fill"))
    #expect(OverlayVisualState.success(.pasteSent).leadingVisual == .icon(symbolName: "checkmark.circle.fill"))
    #expect(OverlayVisualState.success(.copied).leadingVisual == .icon(symbolName: "doc.on.clipboard.fill"))
    #expect(
        OverlayVisualState.success(.confirmation(title: "Email Reply"))
            .leadingVisual == .icon(symbolName: "checkmark.circle.fill")
    )
    #expect(OverlayVisualState.error("Microphone permission is missing").leadingVisual == .icon(symbolName: "exclamationmark.triangle.fill"))
}

@Test
func overlayStatesUseOneLineOfVisibleCopy() {
    // Recording intentionally has no base label — the controller shows the
    // skill name (or nothing) so the voice glyph can lead without hotkey copy.
    #expect(
        OverlayVisualState.recording(
            levels: Array(repeating: 0.2, count: 9),
            elapsedText: "00:03"
        ).label.isEmpty
    )
    #expect(OverlayVisualState.processing.label == "Processing")
    #expect(OverlayVisualState.success(.inserted).label == "Done")
    #expect(OverlayVisualState.success(.pasteSent).label == "Done")
    #expect(OverlayVisualState.success(.copied).label == "Done")
    #expect(
        OverlayVisualState.success(.confirmation(title: "Email Reply"))
            .label == "Email Reply"
    )
    #expect(OverlayVisualState.error("Microphone permission is missing").label == "Error")
    #expect(OverlayVisualState.retryableError("Cloudflare 403").label == "Error")
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
func overlayErrorMessageIsCollapsedForVoiceOverAnnouncement() {
    let state = OverlayVisualState.error("Microphone permission is missing.\nGrant access in Settings and try again after restarting VibeWhisper.")

    #expect(state.supplementaryText == "Microphone permission is missing. Grant access in Settings and try…")
}

@Test
func waveformNormalizerClampsSilenceAndLoudInput() {
    #expect(WaveformNormalizer.normalizedLevel(fromAveragePower: -160) == 0.08)
    #expect(WaveformNormalizer.normalizedLevel(fromAveragePower: 0) == 1)
}

@Test
func waveformNormalizerRecordingProfileStaysSymmetricAndWithinBounds() {
    // Phase 0 keeps organic modulation deterministic; contour still peaks at center.
    let smoothed = WaveformNormalizer.smoothedLevels(
        previous: Array(repeating: 0.12, count: 9),
        targetLevel: 0.9,
        barCount: 9,
        phase: 0
    )

    #expect(smoothed.count == 9)
    #expect(smoothed.allSatisfy { $0 >= 0.08 && $0 <= 1 })
    #expect(smoothed[4] > smoothed[0])
    #expect(smoothed[4] > smoothed[8])
    // Organic multi-frequency motion intentionally breaks perfect mirror symmetry;
    // edges still share the same contour family so they stay within a close band.
    #expect(abs(smoothed[0] - smoothed[8]) < 0.18)
}

@Test
func waveformNormalizerRecordingProfileAnimatesWithPhase() {
    let quiet = WaveformNormalizer.smoothedLevels(
        previous: Array(repeating: 0.12, count: 5),
        targetLevel: 0.18,
        barCount: 5,
        phase: 0.2
    )
    let later = WaveformNormalizer.smoothedLevels(
        previous: quiet,
        targetLevel: 0.18,
        barCount: 5,
        phase: 0.55
    )
    #expect(quiet.count == 5)
    #expect(later.count == 5)
    #expect(quiet != later)
    #expect(quiet.allSatisfy { $0 >= 0.08 && $0 <= 1 })
    #expect(later.allSatisfy { $0 >= 0.08 && $0 <= 1 })
}

@Test
func waveformNormalizerProcessingPulseTravelsAcrossTheGlyph() {
    let early = WaveformNormalizer.processingPulseLevels(frame: 0, barCount: 9)
    let later = WaveformNormalizer.processingPulseLevels(frame: 5, barCount: 9)
    let continuousEarly = WaveformNormalizer.processingPulseLevels(
        time: 0,
        barCount: 9
    )
    let continuousLater = WaveformNormalizer.processingPulseLevels(
        time: 0.35,
        barCount: 9
    )

    #expect(early.count == 9)
    #expect(later.count == 9)
    #expect(early.allSatisfy { $0 >= 0.08 && $0 <= 1 })
    #expect(later.allSatisfy { $0 >= 0.08 && $0 <= 1 })
    #expect(early != later)
    #expect(continuousEarly != continuousLater)
    #expect(continuousLater.allSatisfy { $0 >= 0.08 && $0 <= 1 })
    // The continuous ridge should open a wider dynamic range than a flat bar.
    #expect((continuousLater.max() ?? 0) - (continuousLater.min() ?? 0) > 0.12)
}

@Test
func waveformNormalizerPadsMissingSamplesToTheRequestedWaveCount() {
    let smoothed = WaveformNormalizer.smoothedLevels(
        previous: [0.2, 0.3, 0.4],
        targetLevel: 0.6,
        barCount: 9,
        phase: 0
    )

    #expect(smoothed.count == 9)
    #expect(smoothed.allSatisfy { $0 >= 0.08 && $0 <= 1 })
}

@Test
func everyOverlayStateUsesAdaptiveContentFitting() {
    let preset = OverlayStylePreset.dictationHUD
    let processingTitle = "Processing"
    let processingTitleWidth = ceil(
        (processingTitle as NSString).size(
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
            ]
        ).width
    )
    let skillTitle = "代码提示词"
    let skillTitleWidth = ceil(
        (skillTitle as NSString).size(
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
            ]
        ).width
    )
    let processingSize = preset.size(
        for: .processing,
        titleWidth: processingTitleWidth
    )
    let successSize = preset.size(
        for: .success(.inserted),
        titleWidth: ceil(
            ("Done" as NSString).size(
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
                ]
            ).width
        )
    )
    let recordingSize = preset.size(
        for: .recording(
            levels: Array(repeating: 0.2, count: 5),
            elapsedText: "00:07"
        ),
        titleWidth: skillTitleWidth
    )
    let emptyRecordingSize = preset.size(
        for: .recording(
            levels: Array(repeating: 0.2, count: 5),
            elapsedText: "00:07"
        ),
        titleWidth: 0
    )
    let errorSize = preset.size(
        for: .error("boom"),
        titleWidth: ceil(
            ("Error" as NSString).size(
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
                ]
            ).width
        )
    )

    // Heights stay constant so morphs only animate width.
    #expect(processingSize.height == preset.primaryPillHeight)
    #expect(recordingSize.height == preset.primaryPillHeight)
    #expect(successSize.height == preset.primaryPillHeight)
    #expect(errorSize.height == preset.errorPillHeight)

    // Processing stays compact; recording with a skill name is wider.
    #expect(processingSize.width < recordingSize.width)
    #expect(successSize.width <= processingSize.width)
    // Empty recording (no skill) is still at least the recording minimum.
    #expect(emptyRecordingSize.width >= processingSize.width)
    #expect(recordingSize.width <= preset.primaryPillWidth)
    #expect(errorSize.width <= preset.errorPillWidth)
    #expect(processingSize.width >= preset.inlineControlReservedWidth)
}

@Test
func compactResultStatesHugShortStatusCopy() {
    let preset = OverlayStylePreset.dictationHUD
    let font = NSFont.systemFont(ofSize: 12, weight: .semibold)

    func width(of text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    // Chinese status words used in the product UI.
    let doneZH = width(of: "已完成")
    let errorZH = width(of: "错误")
    let processingZH = width(of: "处理中")

    let successSize = preset.size(
        for: .success(.copied),
        titleWidth: doneZH
    )
    let errorSize = preset.size(
        for: .error("boom"),
        titleWidth: errorZH
    )
    let processingSize = preset.size(
        for: .processing,
        titleWidth: processingZH
    )
    let emptySuccess = preset.size(
        for: .success(.copied),
        titleWidth: 0
    )

    // Success / plain error have no trailing chrome — they must hug the label
    // instead of sitting at a wide fixed floor (the old 176-pt error min).
    #expect(successSize.width < 160)
    #expect(errorSize.width < 160)
    // "已完成" is three characters; the pill must be wide enough not to clip.
    let successContent = successSize.width - preset.chromeInset * 2
    let successCore = (preset.contentPaddingH * 2)
        + preset.leadingVisualWidth
        + preset.textGap
        + doneZH
    #expect(successContent + 0.5 >= successCore)
    #expect(errorSize.width <= processingSize.width + 8)
    // Empty title still produces a minimal badge-only pill.
    #expect(emptySuccess.width < successSize.width)
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
    // Timer is full primary label opacity in every appearance path so elapsed
    // time stays readable on Liquid Glass; contrast mode does not dim it further.
    #expect(standardAppearance.timerOpacity == 1)
    #expect(increasedAppearance.timerOpacity == 1)
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
            == WaveformNormalizer.reducedMotionProcessingLevels(
                barCount: OverlayStylePreset.dictationHUD.waveformBarCount
            )
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
        edgeInset: preset.topInset,
        placement: .top
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
func overlayPanelPlacementStaysNearBottomEdge() {
    let preset = OverlayStylePreset.dictationHUD
    let visibleFrame = CGRect(x: 40, y: 30, width: 1440, height: 860)
    let frame = OverlayController.panelFrame(
        for: preset.size(for: .processing),
        in: visibleFrame,
        edgeInset: preset.topInset,
        placement: .bottom
    )

    #expect(frame.minY == visibleFrame.minY + preset.topInset)
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
func overlayControllerUsesNativeAppKitHUDMaterialWithSystemGlassWhenAvailable() {
    let overlay = OverlayController()
    defer { overlay.hide() }

    #expect(overlay.debugSnapshot.usesNativeAppKitHUDMaterial)
    #expect(
        overlay.debugSnapshot.usesLiquidGlassMaterial
            == VibeWhisperFloatingChrome.usesSystemLiquidGlass
    )
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
func overlayRecordingCopyOmitsHotkeyAndUsesSkillOnlyInController() {
    let state = OverlayVisualState.recording(
        levels: Array(repeating: 0.2, count: 9),
        elapsedText: "00:04"
    )

    #expect(state.label.isEmpty)
    #expect(
        state.label(hotkeyDisplayName: "F5").isEmpty
    )
    #expect(
        state.label(hotkeyDisplayName: "⌃M").isEmpty
    )
    #expect(OverlayVisualState.processing.label == "Processing")
    #expect(OverlaySuccessKind.inserted.label == "Done")
    #expect(OverlaySuccessKind.pasteSent.label == "Done")
    #expect(OverlaySuccessKind.copied.label == "Done")
    #expect(
        OverlaySuccessKind.confirmation(title: "Email Reply")
            .label == "Email Reply"
    )
}

@MainActor
@Test
func overlayControllerShowsCapsuleConfirmationWithSkillName() {
    let overlay = OverlayController()
    defer { overlay.hide() }

    overlay.showConfirmation(title: "Email Reply")
    let snapshot = overlay.debugSnapshot
    #expect(snapshot.panelIsVisible)
    #expect(snapshot.visibleTitle == "Email Reply")
    #expect(snapshot.isTitleHidden == false)
    #expect(snapshot.isCancelControlVisible == false)
    #expect(snapshot.isRetryControlVisible == false)
    #expect(snapshot.isTimerVisible == false)
}

@Test
func overlaySuccessConfirmationUsesSkillNameLabelAndCheckmark() {
    let state = OverlayVisualState.success(
        .confirmation(title: "Email Reply")
    )
    #expect(state.label == "Email Reply")
    #expect(
        state.leadingVisual
            == .icon(symbolName: "checkmark.circle.fill")
    )
    #expect(state.showsCancelControl == false)
    #expect(state.showsRetryControl == false)
    #expect(state.trailingText == nil)
}

@MainActor
@Test
func overlayControllerRecordingShowsSkillOnlyAndProcessingDropsSkill() {
    let overlay = OverlayController()
    defer { overlay.hide() }

    overlay.updateSkillPresentation(
        SkillRuntimePresentation(
            displayName: "代码提示词",
            source: .globalDefault
        )
    )
    overlay.showRecording(elapsedText: "00:04")
    #expect(overlay.debugSnapshot.visibleTitle == "代码提示词")
    #expect(overlay.debugSnapshot.isTitleHidden == false)
    #expect(overlay.debugSnapshot.waveformAccent == .recording)

    overlay.showProcessing()
    #expect(overlay.debugSnapshot.visibleTitle == "Processing")
    #expect(overlay.debugSnapshot.isTitleHidden == false)
    #expect(overlay.debugSnapshot.waveformAccent == .processing)

    overlay.showResult(text: "hello", outcome: .insertedAndVerified)
    #expect(overlay.debugSnapshot.visibleTitle == "Done")
    #expect(overlay.debugSnapshot.waveformAccent == .none)
}

@MainActor
@Test
func overlayControllerRecordingWithoutSkillHidesTitle() {
    let overlay = OverlayController()
    defer { overlay.hide() }

    overlay.updateSkillPresentation(nil)
    overlay.showRecording(elapsedText: "00:02")
    #expect(overlay.debugSnapshot.visibleTitle == "")
    #expect(overlay.debugSnapshot.isTitleHidden)
    #expect(overlay.debugSnapshot.waveformAccent == .recording)
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
        .appendingPathComponent("vibewhisper-overlay-\(UUID().uuidString).png")
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
