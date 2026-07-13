import Foundation

protocol Transcriber: Sendable {
    func transcribe(_ audio: RecordedAudio) async throws -> TranscriptionResult
}

protocol DictationPreparing: Sendable {
    func prepare(audio: RecordedAudio) async throws -> PreparedDictation
}

protocol TranscriptNormalizing: Sendable {
    func normalize(
        text: String,
        importedEntries: [TerminologyEntry],
        hintTerms: [String]
    ) -> NormalizationResult
}

struct DictationMetrics: Sendable, Equatable {
    let transcription: TranscriptionMetrics
    let normalizationMs: Int
    let polishMs: Int
    let textPolishAttempted: Bool
    let textPolishDecisionReason: TextPolishDecisionReason?
    let textPolishProvider: TextPolishProviderID?
    let textPolishErrorMessage: String?
    let estimatedPolishInputTokens: Int
    let estimatedPolishOutputTokens: Int

    init(
        transcription: TranscriptionMetrics,
        normalizationMs: Int,
        polishMs: Int = 0,
        textPolishAttempted: Bool = false,
        textPolishDecisionReason: TextPolishDecisionReason? = nil,
        textPolishProvider: TextPolishProviderID? = nil,
        textPolishErrorMessage: String? = nil,
        estimatedPolishInputTokens: Int = 0,
        estimatedPolishOutputTokens: Int = 0
    ) {
        self.transcription = transcription
        self.normalizationMs = normalizationMs
        self.polishMs = polishMs
        self.textPolishAttempted = textPolishAttempted
        self.textPolishDecisionReason = textPolishDecisionReason
        self.textPolishProvider = textPolishProvider
        self.textPolishErrorMessage = textPolishErrorMessage
        self.estimatedPolishInputTokens = estimatedPolishInputTokens
        self.estimatedPolishOutputTokens = estimatedPolishOutputTokens
    }
}

struct PreparedDictation: Sendable, Equatable {
    let rawText: String
    let finalText: String
    let normalizationApplied: Bool
    let exactReplacementCount: Int
    let fuzzyReplacementCount: Int
    let metrics: DictationMetrics
}

struct DictationPipeline: DictationPreparing {
    let transcriber: any Transcriber
    let normalizer: any TranscriptNormalizing
    let importedEntries: [TerminologyEntry]
    let hintTerms: [String]
    var textPolisher: (any TextPolishing)?
    var textPolishConfig: TextPolishConfig = .init()
    var textPolishDecisionEngine: any TextPolishDeciding =
        TextPolishDecisionEngine()
    var dictationMode: DictationMode = .direct
    var literalTokenizer: TechnicalLiteralTokenizer = .init()

    func prepare(audio: RecordedAudio) async throws -> PreparedDictation {
        let transcription = try await transcriber.transcribe(audio)
        let normalizationStarted = DispatchTime.now().uptimeNanoseconds
        let prePolish = normalizer.normalize(
            text: transcription.text,
            importedEntries: importedEntries,
            hintTerms: hintTerms
        )
        var normalizationMs = elapsedMilliseconds(since: normalizationStarted)

        var finalText = prePolish.text
        var textPolishAttempted = false
        var textPolishProvider: TextPolishProviderID?
        var textPolishErrorMessage: String?
        var estimatedPolishInputTokens = 0
        var estimatedPolishOutputTokens = 0
        var polishMs = 0

        let textPolishDecision = textPolishDecisionEngine.decide(
            normalizedText: prePolish.text,
            audioDurationMs: transcription.metrics.audioDurationMs,
            mode: dictationMode,
            config: textPolishConfig,
            providerAvailable: textPolisher != nil
        )

        if textPolishDecision.shouldPolish, let textPolisher {
            textPolishAttempted = true
            let polishStarted = DispatchTime.now().uptimeNanoseconds
            do {
                let literalTokenization = literalTokenizer.tokenize(
                    prePolish.text,
                    style: .modelSafe
                )
                let polished = try await textPolisher.polish(
                    text: literalTokenization.maskedText,
                    terminologyEntries: importedEntries,
                    hintTerms: hintTerms
                )
                polishMs = elapsedMilliseconds(since: polishStarted)
                estimatedPolishInputTokens = polished.estimatedInputTokens
                estimatedPolishOutputTokens = polished.estimatedOutputTokens

                guard let literalSafePolishedText = literalTokenization.restoringLiterals(
                    in: polished.text
                ) else {
                    textPolishErrorMessage = L10n.text(
                        "AI Polish changed a protected technical literal; OpenWhisper used the normalized transcript instead."
                    )
                    return fallbackPreparedDictation(
                        transcription: transcription,
                        prePolish: prePolish,
                        normalizationMs: normalizationMs,
                        polishMs: polishMs,
                        textPolishDecisionReason: textPolishDecision.reason,
                        textPolishErrorMessage: textPolishErrorMessage,
                        estimatedPolishInputTokens: estimatedPolishInputTokens,
                        estimatedPolishOutputTokens: estimatedPolishOutputTokens
                    )
                }

                guard !isSuspiciousPolishTruncation(
                    original: prePolish.text,
                    polished: literalSafePolishedText
                ) else {
                    textPolishErrorMessage = L10n.text(
                        "AI Polish output looked truncated; OpenWhisper used the normalized transcript instead."
                    )
                    return fallbackPreparedDictation(
                        transcription: transcription,
                        prePolish: prePolish,
                        normalizationMs: normalizationMs,
                        polishMs: polishMs,
                        textPolishDecisionReason: textPolishDecision.reason,
                        textPolishErrorMessage: textPolishErrorMessage,
                        estimatedPolishInputTokens: estimatedPolishInputTokens,
                        estimatedPolishOutputTokens: estimatedPolishOutputTokens
                    )
                }

                textPolishProvider = polished.provider

                let postPolishStarted = DispatchTime.now().uptimeNanoseconds
                let postPolish = normalizer.normalize(
                    text: literalSafePolishedText,
                    importedEntries: importedEntries,
                    hintTerms: hintTerms
                )
                normalizationMs += elapsedMilliseconds(since: postPolishStarted)
                finalText = postPolish.text
            } catch {
                polishMs = elapsedMilliseconds(since: polishStarted)
                textPolishErrorMessage = error.localizedDescription
            }
        }

        return PreparedDictation(
            rawText: transcription.text,
            finalText: finalText,
            normalizationApplied: prePolish.applied || finalText != prePolish.text,
            exactReplacementCount: prePolish.exactReplacementCount,
            fuzzyReplacementCount: prePolish.fuzzyReplacementCount,
            metrics: DictationMetrics(
                transcription: transcription.metrics,
                normalizationMs: normalizationMs,
                polishMs: polishMs,
                textPolishAttempted: textPolishAttempted,
                textPolishDecisionReason: textPolishDecision.reason,
                textPolishProvider: textPolishProvider,
                textPolishErrorMessage: textPolishErrorMessage,
                estimatedPolishInputTokens: estimatedPolishInputTokens,
                estimatedPolishOutputTokens: estimatedPolishOutputTokens
            )
        )
    }

    private func fallbackPreparedDictation(
        transcription: TranscriptionResult,
        prePolish: NormalizationResult,
        normalizationMs: Int,
        polishMs: Int,
        textPolishDecisionReason: TextPolishDecisionReason?,
        textPolishErrorMessage: String?,
        estimatedPolishInputTokens: Int,
        estimatedPolishOutputTokens: Int
    ) -> PreparedDictation {
        PreparedDictation(
            rawText: transcription.text,
            finalText: prePolish.text,
            normalizationApplied: prePolish.applied,
            exactReplacementCount: prePolish.exactReplacementCount,
            fuzzyReplacementCount: prePolish.fuzzyReplacementCount,
            metrics: DictationMetrics(
                transcription: transcription.metrics,
                normalizationMs: normalizationMs,
                polishMs: polishMs,
                textPolishAttempted: true,
                textPolishDecisionReason: textPolishDecisionReason,
                textPolishProvider: nil,
                textPolishErrorMessage: textPolishErrorMessage,
                estimatedPolishInputTokens: estimatedPolishInputTokens,
                estimatedPolishOutputTokens: estimatedPolishOutputTokens
            )
        )
    }

    private func elapsedMilliseconds(since start: UInt64) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }

    private func isSuspiciousPolishTruncation(original: String, polished: String) -> Bool {
        let originalCount = meaningfulCharacterCount(original)
        let polishedCount = meaningfulCharacterCount(polished)

        guard originalCount >= 80 else {
            return false
        }
        guard polishedCount < max(40, Int(Double(originalCount) * 0.35)) else {
            return false
        }

        let originalTerminators = sentenceTerminatorCount(original)
        let polishedTerminators = sentenceTerminatorCount(polished)
        return originalTerminators >= 3 && polishedTerminators <= 1
    }

    private func meaningfulCharacterCount(_ text: String) -> Int {
        text.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }.count
    }

    private func sentenceTerminatorCount(_ text: String) -> Int {
        text.reduce(0) { count, character in
            "。！？!?；;\n".contains(character) ? count + 1 : count
        }
    }
}
