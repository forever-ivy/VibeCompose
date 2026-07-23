import AppKit
import Testing
@testable import VibeWhisper

@Test
func statusMenuVisualStatesExposeStableLabels() {
    #expect(StatusMenuVisualState.ready.menuLabel == "OW")
    #expect(StatusMenuVisualState.setupRequired.menuLabel == "SET")
    #expect(StatusMenuVisualState.recording.menuLabel == "REC")
    #expect(StatusMenuVisualState.processing.menuLabel == "Working")
    #expect(StatusMenuVisualState.error.menuLabel == "ERR")
}

@Test
func statusMenuVisualStateMarksAttentionStates() {
    #expect(StatusMenuVisualState.ready.usesTemplateAttention == false)
    #expect(StatusMenuVisualState.recording.usesTemplateAttention == true)
    #expect(StatusMenuVisualState.processing.usesTemplateAttention == true)
    #expect(StatusMenuVisualState.error.usesTemplateAttention == true)
}

@Test @MainActor
func statusMenuRendererProducesNativeTemplateImage() {
    let image = VibeWhisperStatusIconRenderer.image(
        for: .ready
    )

    #expect(image.size == NSSize(width: 18, height: 18))
    #expect(image.isTemplate)
}

@Test @MainActor
func statusMenuCanRebuildLocalizedItemsRepeatedly() {
    let controller = StatusMenuController(
        openHistoryHandler: {},
        openQuickAddHandler: {},
        openTerminologyHandler: {},
        openSettingsHandler: {},
        checkForUpdatesHandler: {},
        quitHandler: {}
    )

    controller.reloadLocalization()
    controller.reloadLocalization()
}
