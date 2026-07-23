import Foundation
import Testing
@testable import VibeWhisper

@Test
func latencyRecorderAppendsJsonlSamples() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let recorder = LatencyRecorder(directoryURL: root)

    try recorder.record(
        .init(
            timestamp: Date(),
            audioDurationMs: 3_000,
            audioBytes: 42_000,
            provider: "chatGPTManagedAuth",
            textPolishProvider: "chatGPTAuth",
            authMs: 120,
            transcribeMs: 850,
            normalizationMs: 2,
            polishMs: 300,
            textPolishAttempted: true,
            textPolishDecisionReason:
                TextPolishDecisionReason.runAgentPlan.rawValue,
            estimatedPolishInputTokens: 1_200,
            estimatedPolishOutputTokens: 400,
            injectMs: 40,
            totalProcessingMs: 1_012,
            resultStatus: TextDeliveryStatus.insertedAndVerified,
            errorCategory: nil
        )
    )

    let contents = try String(contentsOf: root.appendingPathComponent("latency.jsonl"), encoding: .utf8)
    #expect(contents.contains("\"provider\":\"chatGPTManagedAuth\""))
    #expect(contents.contains("\"textPolishProvider\":\"chatGPTAuth\""))
    #expect(contents.contains("\"textPolishAttempted\":true"))
    #expect(
        contents.contains(
            "\"textPolishDecisionReason\":\"run_agent_plan\""
        )
    )
    #expect(contents.contains("\"transcribeMs\":850"))
    #expect(contents.contains("\"estimatedPolishInputTokens\":1200"))
}
