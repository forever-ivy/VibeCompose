import Foundation
import Testing
@testable import OpenWhisper

private let acceptanceTranscript = "王老师 呃 我们这周三下午三点应该可以开会 你帮我发个邮件给大家 主题就是第二版预算 review 然后附件是 budget v2.xlsx"

private struct FakeTranscriber: Transcriber {
    let result: TranscriptionResult

    func transcribe(_ audio: RecordedAudio) async throws -> TranscriptionResult {
        result
    }
}

private struct FakeTextPolisher: TextPolishing {
    let result: Result<TextPolishResult, Error>

    func polish(
        text: String,
        terminologyEntries: [TerminologyEntry],
        hintTerms: [String]
    ) async throws -> TextPolishResult {
        try result.get()
    }
}

private struct FakePolishError: Error {}

private func alwaysTextPolishConfig() -> TextPolishConfig {
    var config = TextPolishConfig()
    config.mode = .always
    return config
}

@Test
func terminologyNormalizerPreservesHintTermsWithoutModelRewrite() {
    let result = TerminologyNormalizer().normalize(
        text: "请帮我把 Budget V2.XLSX 发给大家 review 一下，顺便提一下 openwhisper 已经能用了。",
        importedEntries: [],
        hintTerms: ["budget v2.xlsx", "review", "OpenWhisper"]
    )

    #expect(result.text.contains("budget v2.xlsx"))
    #expect(result.text.contains("review"))
    #expect(result.text.contains("OpenWhisper"))
    #expect(result.applied == true)
    #expect(result.exactReplacementCount == 2)
    #expect(result.fuzzyReplacementCount == 0)
}

@Test
func terminologyNormalizerConvertsTraditionalChineseToSimplifiedChinese() {
    let result = TerminologyNormalizer().normalize(
        text: "請把這個檔案發過來，體驗一下 openwhisper。",
        importedEntries: [],
        hintTerms: ["OpenWhisper"]
    )

    #expect(result.text == "请把这个档案发过来，体验一下 OpenWhisper。")
    #expect(result.applied == true)
}

@Test
func terminologyNormalizerUsesFullWidthPunctuationWhenChineseIsPresent() {
    let result = TerminologyNormalizer().normalize(
        text: "请总结 OpenWhisper, OpenClaw works well. 还有问题吗? 不要忘了: 明天 review!",
        importedEntries: [],
        hintTerms: []
    )

    #expect(result.text == "请总结 OpenWhisper， OpenClaw works well。 还有问题吗？ 不要忘了： 明天 review！")
    #expect(result.applied == true)
}

@Test
func terminologyNormalizerPreservesTechnicalLiteralsWhenConvertingPunctuation() {
    let result = TerminologyNormalizer().normalize(
        text: "请发给我 budget v2.xlsx, API 是 https://example.com/v1/chat, 版本是 v1.2.3.",
        importedEntries: [],
        hintTerms: ["budget v2.xlsx"]
    )

    #expect(result.text == "请发给我 budget v2.xlsx， API 是 https://example.com/v1/chat， 版本是 v1.2.3。")
}

@Test
func terminologyNormalizerReplacesImportedAliasesAndSeparators() {
    let result = TerminologyNormalizer().normalize(
        text: "把 Example SDK 和 open ai compatible 都写对。",
        importedEntries: [
            TerminologyEntry(
                canonical: "ExampleSDK",
                aliases: ["Example SDK"]
            ),
            TerminologyEntry(
                canonical: "OpenAI Compatible",
                aliases: ["Open AI Compatible"]
            ),
        ],
        hintTerms: []
    )

    #expect(result.text == "把 ExampleSDK 和 OpenAI Compatible 都写对。")
    #expect(result.exactReplacementCount == 2)
    #expect(result.fuzzyReplacementCount == 0)
}

@Test
func terminologyNormalizerFuzzilyAlignsImportedTechnicalTerms() {
    let result = TerminologyNormalizer().normalize(
        text: "ExamplSDK 这次能不能和 Codex 对齐？",
        importedEntries: [
            TerminologyEntry(
                canonical: "ExampleSDK",
                aliases: ["Example SDK"]
            ),
        ],
        hintTerms: []
    )

    #expect(result.text == "ExampleSDK 这次能不能和 Codex 对齐？")
    #expect(result.exactReplacementCount == 0)
    #expect(result.fuzzyReplacementCount == 1)
}

@Test
func terminologyNormalizerFuzzilyAlignsAccentedLatinTechnicalTerms() {
    let result = TerminologyNormalizer().normalize(
        text: "Éxample SDK 和 Open Whísper 都要按术语库大小写输出。",
        importedEntries: [
            TerminologyEntry(
                canonical: "ExampleSDK",
                aliases: ["Example SDK"]
            ),
            TerminologyEntry(
                canonical: "OpenWhisper",
                aliases: ["Open Whisper"]
            ),
        ],
        hintTerms: []
    )

    #expect(result.text == "ExampleSDK 和 OpenWhisper 都要按术语库大小写输出。")
    #expect(result.fuzzyReplacementCount == 2)
}

@Test
func terminologyNormalizerDoesNotExpandStandaloneLatinInsideMixedScriptTerm() {
    let result = TerminologyNormalizer().normalize(
        text: "请打开 github 看一下。",
        importedEntries: [
            TerminologyEntry(
                canonical: "玩转GitHub",
                aliases: []
            ),
        ],
        hintTerms: []
    )

    #expect(result.text == "请打开 github 看一下。")
    #expect(result.fuzzyReplacementCount == 0)
}

@Test
func terminologyNormalizerCollapsesSpacedMixedScriptTermWithoutDuplicatePrefix() {
    let result = TerminologyNormalizer().normalize(
        text: "我们继续讲 玩转 github 这门课。",
        importedEntries: [
            TerminologyEntry(
                canonical: "玩转GitHub",
                aliases: []
            ),
        ],
        hintTerms: []
    )

    #expect(result.text == "我们继续讲 玩转GitHub 这门课。")
    #expect(result.exactReplacementCount == 1)
    #expect(result.fuzzyReplacementCount == 0)
}

@Test
func terminologyNormalizerAppliesUserCorrectionForOpenClawMisrecognition() {
    let result = TerminologyNormalizer().normalize(
        text: "现在总是把 OpenCloud 识别错，必须锁死。",
        importedEntries: [
            TerminologyEntry(
                type: .correction,
                original: "opencloud",
                replacement: "OpenClaw",
                aliases: [],
                isEnabled: true,
                source: "user",
                usageCount: 0,
                createdAt: "2026-05-07T10:00:00Z"
            ),
        ],
        hintTerms: []
    )

    #expect(result.text == "现在总是把 OpenClaw 识别错，必须锁死。")
    #expect(result.exactReplacementCount == 1)
    #expect(result.fuzzyReplacementCount == 0)
}

@Test
func terminologyNormalizerIgnoresLegacyCaseSensitiveFlagForCorrections() {
    let result = TerminologyNormalizer().normalize(
        text: "OpenCloud 仍然要替换。",
        importedEntries: [
            TerminologyEntry(
                type: .correction,
                original: "opencloud",
                replacement: "OpenClaw",
                aliases: [],
                isEnabled: true,
                source: "user",
                usageCount: 0,
                createdAt: "2026-05-07T10:00:00Z"
            ),
        ],
        hintTerms: []
    )

    #expect(result.text == "OpenClaw 仍然要替换。")
}

@Test
func terminologyNormalizerIgnoresDisabledDictionaryEntries() {
    let result = TerminologyNormalizer().normalize(
        text: "opencloud 和 openwhisper 都不要被改。",
        importedEntries: [
            TerminologyEntry(
                type: .correction,
                original: "opencloud",
                replacement: "OpenClaw",
                aliases: [],
                isEnabled: false,
                source: "user",
                usageCount: 0,
                createdAt: "2026-05-07T10:00:00Z"
            ),
            TerminologyEntry(
                type: .term,
                original: "OpenWhisper",
                replacement: nil,
                aliases: [],
                isEnabled: false,
                source: "user",
                usageCount: 0,
                createdAt: "2026-05-07T10:00:00Z"
            ),
        ],
        hintTerms: []
    )

    #expect(result.text == "opencloud 和 openwhisper 都不要被改。")
    #expect(result.exactReplacementCount == 0)
    #expect(result.fuzzyReplacementCount == 0)
}

@Test
func terminologyNormalizerAppliesCorrectionBeforeTermFuzzyAlignment() {
    let result = TerminologyNormalizer().normalize(
        text: "opencloud 必须先按 correction 变成 OpenClaw。",
        importedEntries: [
            TerminologyEntry(
                type: .term,
                original: "OpenCloud",
                replacement: nil,
                aliases: [],
                isEnabled: true,
                source: "user",
                usageCount: 0,
                createdAt: "2026-05-07T10:00:00Z"
            ),
            TerminologyEntry(
                type: .correction,
                original: "opencloud",
                replacement: "OpenClaw",
                aliases: [],
                isEnabled: true,
                source: "user",
                usageCount: 0,
                createdAt: "2026-05-07T10:00:00Z"
            ),
        ],
        hintTerms: []
    )

    #expect(result.text == "OpenClaw 必须先按 correction 变成 OpenClaw。")
    #expect(result.exactReplacementCount == 1)
    #expect(result.fuzzyReplacementCount == 0)
}

@Test
func terminologyNormalizerDoesNotDowncaseCorrectionReplacementWithLowercaseTerm() {
    let result = TerminologyNormalizer().normalize(
        text: "OpenCloud 应该变成 OpenClaw。",
        importedEntries: [
            TerminologyEntry(
                type: .correction,
                original: "opencloud",
                replacement: "OpenClaw",
                aliases: [],
                isEnabled: true,
                source: "user",
                usageCount: 0,
                createdAt: "2026-05-07T10:00:00Z"
            ),
            TerminologyEntry(
                type: .term,
                original: "openclaw",
                replacement: nil,
                aliases: [],
                isEnabled: true,
                source: "user",
                usageCount: 0,
                createdAt: "2026-05-07T10:00:00Z"
            ),
        ],
        hintTerms: []
    )

    #expect(result.text == "OpenClaw 应该变成 OpenClaw。")
}

@Test
func terminologyNormalizerAppliesUserLowercaseTermCasingForShadowd() {
    let result = TerminologyNormalizer().normalize(
        text: "ShadowD 和 SHADOWD 都应该按词库输出。",
        importedEntries: [
            TerminologyEntry(
                type: .term,
                original: "shadowd",
                replacement: nil,
                aliases: [],
                isEnabled: true,
                source: "user",
                usageCount: 0,
                createdAt: "2026-06-15T06:43:11Z"
            ),
        ],
        hintTerms: []
    )

    #expect(result.text == "shadowd 和 shadowd 都应该按词库输出。")
    #expect(result.exactReplacementCount == 2)
}

@Test
func terminologyNormalizerAppliesExplicitLowercaseCorrectionForShadowd() {
    let result = TerminologyNormalizer().normalize(
        text: "ShadowD 应该用小写。",
        importedEntries: [
            TerminologyEntry(
                type: .correction,
                original: "ShadowD",
                replacement: "shadowd",
                aliases: [],
                isEnabled: true,
                source: "user",
                usageCount: 0,
                createdAt: "2026-06-15T06:43:11Z"
            ),
        ],
        hintTerms: []
    )

    #expect(result.text == "shadowd 应该用小写。")
    #expect(result.exactReplacementCount == 1)
}

@Test
func terminologyNormalizerAvoidsFuzzyRewritesInsideProtectedLiterals() {
    let result = TerminologyNormalizer().normalize(
        text: "保留 https://example.com/AcmeWhisper 和 --acme-whisper 以及 /tmp/AcmeWhisper，不要乱改。",
        importedEntries: [
            TerminologyEntry(
                canonical: "ExampleSDK",
                aliases: ["Example SDK"]
            ),
        ],
        hintTerms: []
    )

    #expect(result.text == "保留 https://example.com/AcmeWhisper 和 --acme-whisper 以及 /tmp/AcmeWhisper，不要乱改。")
    #expect(result.fuzzyReplacementCount == 0)
}

@Test
func transcriptionPromptBuilderIncludesDirectUseGuidanceAndHintTerms() {
    let prompt = TranscriptionPromptBuilder().buildPrompt(
        hintTerms: ["budget v2.xlsx", "OpenWhisper"],
        locale: "zh-CN"
    )

    #expect(prompt.contains("输出带自然标点"))
    #expect(prompt.contains("直接粘贴使用"))
    #expect(prompt.contains("清理口头填充词"))
    #expect(prompt.contains("不要把系统界面、输入框提示、按钮文案当作语音内容输出"))
    #expect(prompt.contains("budget v2.xlsx"))
    #expect(prompt.contains("OpenWhisper"))
}

@Test
func transcriptionPromptBuilderCanDisableSpeechCleanupGuidance() {
    let prompt = TranscriptionPromptBuilder().buildPrompt(
        hintTerms: [],
        speechCleanupEnabled: false,
        locale: "zh-CN"
    )

    #expect(prompt.contains("清理口头填充词") == false)
}

@Test
func transcriptionPromptBuilderClipsAndDeduplicatesDictionaryHintTerms() {
    let prompt = TranscriptionPromptBuilder().buildPrompt(
        hintTerms: Array(repeating: "OpenClaw", count: 20) + ["ExampleSDK"],
        locale: "zh-CN"
    )

    #expect(prompt.contains("OpenClaw"))
    #expect(prompt.contains("ExampleSDK"))
    #expect(prompt.components(separatedBy: "OpenClaw").count == 2)
}

@Test
func transcriptionPromptBuilderRequestsSimplifiedChineseByDefault() {
    let prompt = TranscriptionPromptBuilder().buildPrompt(
        hintTerms: [],
        locale: "zh-CN"
    )

    #expect(prompt.contains("简体中文"))
    #expect(prompt.contains("不要输出繁体中文"))
    #expect(prompt.contains("标点随语言自动选择"))
}

@Test
func transcriptionPromptBuilderHonorsLanguageAndPunctuationPreferences() {
    let prompt = TranscriptionPromptBuilder().buildPrompt(
        hintTerms: [],
        languagePreference: .traditionalChinese,
        punctuationPreference: .halfWidth,
        locale: "zh-TW"
    )

    #expect(prompt.contains("輸出繁體中文"))
    #expect(prompt.contains("ASCII 半角标点"))
    #expect(prompt.contains("Locale: zh-TW"))
}

@Test
func dictationPipelineRunsTranscribeThenNormalizeWithoutCleanupStage() async throws {
    let pipeline = DictationPipeline(
        transcriber: FakeTranscriber(
            result: TranscriptionResult(
                text: "请把 Budget V2.XLSX 发出来，openwhisper 现在可以用了。",
                metrics: .init(
                    provider: .chatGPTManagedAuth,
                    audioDurationMs: 2_000,
                    audioBytes: 128_000,
                    authMs: 50,
                    transcribeMs: 400,
                    promptIncluded: false
                )
            )
        ),
        normalizer: TerminologyNormalizer(),
        importedEntries: [
            TerminologyEntry(
                canonical: "ExampleSDK",
                aliases: ["Example SDK"]
            ),
        ],
        hintTerms: ["budget v2.xlsx", "OpenWhisper"]
    )

    let audio = RecordedAudio(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fake.wav"),
        durationMs: 2_000
    )

    let result = try await pipeline.prepare(audio: audio)
    #expect(result.rawText == "请把 Budget V2.XLSX 发出来，openwhisper 现在可以用了。")
    #expect(result.finalText == "请把 budget v2.xlsx 发出来，OpenWhisper 现在可以用了。")
    #expect(result.metrics.normalizationMs >= 0)
    #expect(result.exactReplacementCount == 2)
    #expect(result.fuzzyReplacementCount == 0)
}

@Test
func dictationPipelineReportsExactAndFuzzyReplacementCounts() async throws {
    let pipeline = DictationPipeline(
        transcriber: FakeTranscriber(
            result: TranscriptionResult(
                text: "ExamplSDK 和 openwhisper 都得写对。",
                metrics: .init(
                    provider: .chatGPTManagedAuth,
                    audioDurationMs: 2_000,
                    audioBytes: 128_000,
                    authMs: 50,
                    transcribeMs: 400,
                    promptIncluded: false
                )
            )
        ),
        normalizer: TerminologyNormalizer(),
        importedEntries: [
            TerminologyEntry(
                canonical: "ExampleSDK",
                aliases: ["Example SDK"]
            ),
        ],
        hintTerms: ["OpenWhisper"]
    )

    let audio = RecordedAudio(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fake-2.wav"),
        durationMs: 2_000
    )

    let result = try await pipeline.prepare(audio: audio)
    #expect(result.finalText == "ExampleSDK 和 OpenWhisper 都得写对。")
    #expect(result.exactReplacementCount == 1)
    #expect(result.fuzzyReplacementCount == 1)
}

@Test
func dictationPipelineStripsTrailingCodexComposerArtifactFromFinalText() async throws {
    let pipeline = DictationPipeline(
        transcriber: FakeTranscriber(
            result: TranscriptionResult(
                text: "请把这段话发给产品同学确认一下。 Ask Codex anything. @ to use plugins or use files",
                metrics: .init(
                    provider: .chatGPTManagedAuth,
                    audioDurationMs: 2_000,
                    audioBytes: 128_000,
                    authMs: 50,
                    transcribeMs: 400,
                    promptIncluded: false
                )
            )
        ),
        normalizer: TerminologyNormalizer(),
        importedEntries: [],
        hintTerms: []
    )

    let audio = RecordedAudio(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fake-3.wav"),
        durationMs: 2_000
    )

    let result = try await pipeline.prepare(audio: audio)
    #expect(result.rawText == "请把这段话发给产品同学确认一下。 Ask Codex anything. @ to use plugins or use files")
    #expect(result.finalText == "请把这段话发给产品同学确认一下。")
    #expect(result.normalizationApplied == true)
    #expect(result.exactReplacementCount == 0)
    #expect(result.fuzzyReplacementCount == 0)
}

@Test
func dictationPipelineStripsTrailingCodexComposerArtifactWhenItAppearsOnSeparateLine() async throws {
    let pipeline = DictationPipeline(
        transcriber: FakeTranscriber(
            result: TranscriptionResult(
                text: "请把这段话发给产品同学确认一下。\nAsk Codex anything. @ to use plugins or use files",
                metrics: .init(
                    provider: .chatGPTManagedAuth,
                    audioDurationMs: 2_000,
                    audioBytes: 128_000,
                    authMs: 50,
                    transcribeMs: 400,
                    promptIncluded: false
                )
            )
        ),
        normalizer: TerminologyNormalizer(),
        importedEntries: [],
        hintTerms: []
    )

    let audio = RecordedAudio(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fake-4.wav"),
        durationMs: 2_000
    )

    let result = try await pipeline.prepare(audio: audio)
    #expect(result.finalText == "请把这段话发给产品同学确认一下。")
    #expect(result.normalizationApplied == true)
}

@Test
func dictationPipelineStripsTrailingCodexFollowUpPlaceholder() async throws {
    let pipeline = DictationPipeline(
        transcriber: FakeTranscriber(
            result: TranscriptionResult(
                text: "请把这段话发给产品同学确认一下。 Ask for follow-up changes",
                metrics: .init(
                    provider: .chatGPTManagedAuth,
                    audioDurationMs: 2_000,
                    audioBytes: 128_000,
                    authMs: 50,
                    transcribeMs: 400,
                    promptIncluded: false
                )
            )
        ),
        normalizer: TerminologyNormalizer(),
        importedEntries: [],
        hintTerms: []
    )

    let audio = RecordedAudio(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fake-5.wav"),
        durationMs: 2_000
    )

    let result = try await pipeline.prepare(audio: audio)
    #expect(result.finalText == "请把这段话发给产品同学确认一下。")
    #expect(result.normalizationApplied == true)
}

@Test
func dictationPipelineStripsTrailingCodexFollowUpPlaceholderWithZeroWidthBoundaryNoise() async throws {
    let pipeline = DictationPipeline(
        transcriber: FakeTranscriber(
            result: TranscriptionResult(
                text: "请把这段话发给产品同学确认一下。 Ask for follow-up changes\u{200B}",
                metrics: .init(
                    provider: .chatGPTManagedAuth,
                    audioDurationMs: 2_000,
                    audioBytes: 128_000,
                    authMs: 50,
                    transcribeMs: 400,
                    promptIncluded: false
                )
            )
        ),
        normalizer: TerminologyNormalizer(),
        importedEntries: [],
        hintTerms: []
    )

    let audio = RecordedAudio(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fake-6.wav"),
        durationMs: 2_000
    )

    let result = try await pipeline.prepare(audio: audio)
    #expect(result.finalText == "请把这段话发给产品同学确认一下。")
    #expect(result.normalizationApplied == true)
}

@Test
func dictationPipelineStripsTrailingCodexFollowUpPlaceholderWithAgentHint() async throws {
    let pipeline = DictationPipeline(
        transcriber: FakeTranscriber(
            result: TranscriptionResult(
                text: "请把这段话发给产品同学确认一下。 Ask for follow-up changes or use @ to tag an agent",
                metrics: .init(
                    provider: .chatGPTManagedAuth,
                    audioDurationMs: 2_000,
                    audioBytes: 128_000,
                    authMs: 50,
                    transcribeMs: 400,
                    promptIncluded: false
                )
            )
        ),
        normalizer: TerminologyNormalizer(),
        importedEntries: [],
        hintTerms: []
    )

    let audio = RecordedAudio(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fake-7.wav"),
        durationMs: 2_000
    )

    let result = try await pipeline.prepare(audio: audio)
    #expect(result.finalText == "请把这段话发给产品同学确认一下。")
    #expect(result.normalizationApplied == true)
}

@Test
func dictationPipelineStripsTrailingCodexComposerArtifactForModernLocalPlaceholder() async throws {
    let pipeline = DictationPipeline(
        transcriber: FakeTranscriber(
            result: TranscriptionResult(
                text: "请把这段话发给产品同学确认一下。 Ask Codex anything, @ add files, / for commands, $ for skills",
                metrics: .init(
                    provider: .chatGPTManagedAuth,
                    audioDurationMs: 2_000,
                    audioBytes: 128_000,
                    authMs: 50,
                    transcribeMs: 400,
                    promptIncluded: false
                )
            )
        ),
        normalizer: TerminologyNormalizer(),
        importedEntries: [],
        hintTerms: []
    )

    let audio = RecordedAudio(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fake-8.wav"),
        durationMs: 2_000
    )

    let result = try await pipeline.prepare(audio: audio)
    #expect(result.finalText == "请把这段话发给产品同学确认一下。")
    #expect(result.normalizationApplied == true)
}

@Test
func dictationPipelineRunsTextPolishBetweenNormalizationPasses() async throws {
    let pipeline = DictationPipeline(
        transcriber: FakeTranscriber(
            result: TranscriptionResult(
                text: "呃先做 openwhisper 设置页，然后不对，改成 v0.1 润色计划。",
                metrics: .init(
                    provider: .chatGPTManagedAuth,
                    audioDurationMs: 3_000,
                    audioBytes: 128_000,
                    authMs: 50,
                    transcribeMs: 400,
                    promptIncluded: false
                )
            )
        ),
        normalizer: TerminologyNormalizer(),
        importedEntries: [],
        hintTerms: ["OpenWhisper"],
        textPolisher: FakeTextPolisher(
            result: .success(
                TextPolishResult(
                    text: "- 目标：完成 openwhisper ⟪OW_LITERAL_0000⟫ 润色计划\n- 验收：长句输出分点。",
                    provider: .chatGPTAuth,
                    applied: true,
                    estimatedInputTokens: 1_200,
                    estimatedOutputTokens: 400
                )
            )
        ),
        textPolishConfig: alwaysTextPolishConfig()
    )

    let audio = RecordedAudio(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fake-polish.wav"),
        durationMs: 3_000
    )

    let result = try await pipeline.prepare(audio: audio)

    #expect(result.finalText.contains("OpenWhisper v0.1"))
    #expect(result.finalText.contains("- 目标"))
    #expect(result.metrics.textPolishAttempted)
    #expect(result.metrics.textPolishProvider == .chatGPTAuth)
    #expect(result.metrics.textPolishErrorMessage == nil)
    #expect(result.metrics.estimatedPolishInputTokens == 1_200)
    #expect(result.metrics.estimatedPolishOutputTokens == 400)
}

@Test
func dictationPipelineAutoModeSkipsShortDirectPolish() async throws {
    let pipeline = DictationPipeline(
        transcriber: FakeTranscriber(
            result: TranscriptionResult(
                text: "明天下午三点开会。",
                metrics: .init(
                    provider: .chatGPTManagedAuth,
                    audioDurationMs: 2_000,
                    audioBytes: 64_000,
                    authMs: 20,
                    transcribeMs: 300,
                    promptIncluded: true
                )
            )
        ),
        normalizer: TerminologyNormalizer(),
        importedEntries: [],
        hintTerms: [],
        textPolisher: FakeTextPolisher(
            result: .success(
                TextPolishResult(
                    text: "不应执行的重写结果。",
                    provider: .chatGPTAuth,
                    applied: true,
                    estimatedInputTokens: 100,
                    estimatedOutputTokens: 40
                )
            )
        )
    )

    let result = try await pipeline.prepare(
        audio: RecordedAudio(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("fake-auto-polish-skip.wav"),
            durationMs: 2_000
        )
    )

    #expect(result.finalText == "明天下午三点开会。")
    #expect(result.metrics.textPolishAttempted == false)
    #expect(
        result.metrics.textPolishDecisionReason == .skipShortDirect
    )
    #expect(result.metrics.estimatedPolishInputTokens == 0)
}

@Test
func dictationPipelineFallsBackToNormalizedTextWhenTextPolishFails() async throws {
    let pipeline = DictationPipeline(
        transcriber: FakeTranscriber(
            result: TranscriptionResult(
                text: "请把 openwhisper 的术语写对。",
                metrics: .init(
                    provider: .chatGPTManagedAuth,
                    audioDurationMs: 2_000,
                    audioBytes: 128_000,
                    authMs: 50,
                    transcribeMs: 400,
                    promptIncluded: false
                )
            )
        ),
        normalizer: TerminologyNormalizer(),
        importedEntries: [],
        hintTerms: ["OpenWhisper"],
        textPolisher: FakeTextPolisher(result: .failure(FakePolishError())),
        textPolishConfig: alwaysTextPolishConfig()
    )

    let audio = RecordedAudio(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fake-polish-fallback.wav"),
        durationMs: 2_000
    )

    let result = try await pipeline.prepare(audio: audio)

    #expect(result.finalText == "请把 OpenWhisper 的术语写对。")
    #expect(result.metrics.textPolishAttempted)
    #expect(result.metrics.textPolishProvider == nil)
    #expect(result.metrics.textPolishErrorMessage?.isEmpty == false)
    #expect(result.metrics.polishMs >= 0)
}

@Test
func dictationPipelineFallsBackWhenTextPolishChangesProtectedLiteralToken() async throws {
    let originalPath = "/Users/小龍/專案/config.json"
    let pipeline = DictationPipeline(
        transcriber: FakeTranscriber(
            result: TranscriptionResult(
                text: "請把 \(originalPath) 發給我。",
                metrics: .init(
                    provider: .chatGPTManagedAuth,
                    audioDurationMs: 2_000,
                    audioBytes: 128_000,
                    authMs: 50,
                    transcribeMs: 400,
                    promptIncluded: false
                )
            )
        ),
        normalizer: TerminologyNormalizer(),
        importedEntries: [],
        hintTerms: [],
        textPolisher: FakeTextPolisher(
            result: .success(
                TextPolishResult(
                    text: "请把 /Users/小龙/项目/config.json 发给我。",
                    provider: .chatGPTAuth,
                    applied: true,
                    estimatedInputTokens: 120,
                    estimatedOutputTokens: 40
                )
            )
        ),
        textPolishConfig: alwaysTextPolishConfig()
    )

    let audio = RecordedAudio(
        fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-polish-literal.wav"),
        durationMs: 2_000
    )
    let result = try await pipeline.prepare(audio: audio)

    #expect(result.finalText == "请把 \(originalPath) 发给我。")
    #expect(result.metrics.textPolishProvider == nil)
    #expect(result.metrics.textPolishErrorMessage?.contains("technical literal") == true)
}

@Test
func dictationPipelineFallsBackWhenTextPolishSuspiciouslyTruncatesLongInput() async throws {
    let transcript = """
    第一点先把 Dictation 和 AI Polish 拆开。第二点 ChatGPT 的 transcribe API 属于 ASR，不要跟二次 rewrite 混在一起。第三点 ChatGPT Auth rewrite 要单独说明。第四点如果后面有新的决定，要以后面的决定为准。
    """
    let pipeline = DictationPipeline(
        transcriber: FakeTranscriber(
            result: TranscriptionResult(
                text: transcript,
                metrics: .init(
                    provider: .chatGPTManagedAuth,
                    audioDurationMs: 12_000,
                    audioBytes: 560_000,
                    authMs: 20,
                    transcribeMs: 800,
                    promptIncluded: false
                )
            )
        ),
        normalizer: TerminologyNormalizer(),
        importedEntries: [],
        hintTerms: ["ChatGPT", "API"],
        textPolisher: FakeTextPolisher(
            result: .success(
                TextPolishResult(
                    text: "先把 Dictation 和 AI Polish 拆开。",
                    provider: .chatGPTAuth,
                    applied: true,
                    estimatedInputTokens: 1_500,
                    estimatedOutputTokens: 300
                )
            )
        ),
        textPolishConfig: alwaysTextPolishConfig()
    )

    let audio = RecordedAudio(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fake-polish-truncated.wav"),
        durationMs: 12_000
    )

    let result = try await pipeline.prepare(audio: audio)

    #expect(result.finalText.contains("ChatGPT Auth rewrite"))
    #expect(result.finalText.contains("以后面的决定为准"))
    #expect(result.metrics.textPolishAttempted)
    #expect(result.metrics.textPolishProvider == nil)
    #expect(result.metrics.textPolishErrorMessage?.contains("truncated") == true)
    #expect(result.metrics.estimatedPolishInputTokens == 1_500)
}

@Test
func dictationPipelineKeepsResequenceIntendedStepsWithPolish() async throws {
    let transcript = "我们来测试一下这个AI润色啊， 现在包括三个步骤啊，一，打开冰箱，二，然后呢再把冰箱关，呃不对，二，把大象放进去，三呢就是关上冰箱门，按这个顺序来做啊。"
    let pipeline = DictationPipeline(
        transcriber: FakeTranscriber(
            result: TranscriptionResult(
                text: transcript,
                metrics: .init(
                    provider: .chatGPTManagedAuth,
                    audioDurationMs: 9_000,
                    audioBytes: 180_000,
                    authMs: 15,
                    transcribeMs: 520,
                    promptIncluded: true
                )
            )
        ),
        normalizer: TerminologyNormalizer(),
        importedEntries: [],
        hintTerms: [],
        textPolisher: FakeTextPolisher(
            result: .success(
                TextPolishResult(
                    text: "一，打开冰箱\n二，把大象放进去\n三，关上冰箱门",
                    provider: .chatGPTAuth,
                    applied: true,
                    estimatedInputTokens: 220,
                    estimatedOutputTokens: 110
                )
            )
        ),
        textPolishConfig: alwaysTextPolishConfig()
    )

    let audio = RecordedAudio(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fake-polish-resequence.wav"),
        durationMs: 9_000
    )

    let result = try await pipeline.prepare(audio: audio)

    #expect(result.rawText == transcript)
    #expect(result.finalText.contains("把大象放进去"))
    #expect(result.finalText.contains("先" ) == false)
    #expect(result.metrics.textPolishProvider == .chatGPTAuth)
    #expect(result.metrics.polishMs >= 0)
}
