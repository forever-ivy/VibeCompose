import Foundation
import Testing
@testable import VibeCompose

@Test
func pasteAcceptanceEvidenceRoundTripsWithoutTranscriptContent() throws {
    let evidence = PasteAcceptanceEvidence(
        generatedAt: Date(timeIntervalSince1970: 1_783_900_000),
        targetApplication: "TextEdit",
        targetBundleIdentifier: "com.apple.TextEdit",
        targetProcessIdentifier: 123,
        focusedRole: "AXTextArea",
        accessibilityTrusted: true,
        targetCaptured: true,
        resultStatus: TextDeliveryStatus.insertedAndVerified,
        expectedTextObserved: true,
        executionProofObserved: false,
        clipboardState: "restored",
        originalClipboardRestored: true,
        passed: true,
        error: nil
    )

    let data = try JSONEncoder().encode(evidence)
    let decoded = try JSONDecoder().decode(
        PasteAcceptanceEvidence.self,
        from: data
    )

    #expect(decoded == evidence)
    #expect(!String(decoding: data, as: UTF8.self).contains("transcript"))
}

@Test
func pasteAcceptanceEvaluationKeepsTextEditStrictAndTerminalProvable() {
    #expect(
        PasteAcceptanceEvaluation.passed(
            target: .textEdit,
            outcome: .insertedAndVerified,
            expectedTextObserved: true,
            executionProofObserved: false,
            clipboardState: "restored",
            originalClipboardRestored: true
        )
    )
    #expect(
        PasteAcceptanceEvaluation.passed(
            target: .textEdit,
            outcome: .pasteDispatchedClipboardRetained,
            expectedTextObserved: true,
            executionProofObserved: false,
            clipboardState: "transcript_retained",
            originalClipboardRestored: true
        ) == false
    )
    #expect(
        PasteAcceptanceEvaluation.passed(
            target: .terminal,
            outcome: .pasteDispatchedClipboardRetained,
            expectedTextObserved: false,
            executionProofObserved: true,
            clipboardState: "transcript_retained",
            originalClipboardRestored: true
        )
    )
    #expect(
        PasteAcceptanceEvaluation.passed(
            target: .terminal,
            outcome: .insertedAndVerified,
            expectedTextObserved: true,
            executionProofObserved: false,
            clipboardState: "restored",
            originalClipboardRestored: true
        ) == false
    )
}
