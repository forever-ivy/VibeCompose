import Foundation
import Testing
@testable import OpenWhisper

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
        clipboardState: "restored",
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
