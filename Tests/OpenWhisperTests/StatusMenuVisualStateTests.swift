import Testing
@testable import OpenWhisper

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
