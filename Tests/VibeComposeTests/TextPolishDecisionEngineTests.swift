import Testing
@testable import VibeCompose

@Test
func textPolishDecisionSkipsShortLowComplexityDirectDictation() {
    let decision = TextPolishDecisionEngine().decide(
        normalizedText: "明天下午三点开会。",
        audioDurationMs: 3_200,
        mode: .direct,
        config: TextPolishConfig(),
        providerAvailable: true
    )

    #expect(decision.shouldPolish == false)
    #expect(decision.reason == .skipShortDirect)
}

@Test
func textPolishDecisionRunsWhenSpeakerCorrectsEarlierIntent() {
    let decision = TextPolishDecisionEngine().decide(
        normalizedText: "先发布测试版，不对，改成先完成安全验收再发布。",
        audioDurationMs: 6_000,
        mode: .direct,
        config: TextPolishConfig(),
        providerAvailable: true
    )

    #expect(decision.shouldPolish)
    #expect(decision.reason == .runSelfCorrection)
}

@Test
func textPolishDecisionRunsStructuredAndTranslationIntents() {
    let structured = TextPolishDecisionEngine().decide(
        normalizedText: "请整理成目标、约束、实施步骤和验收标准。",
        audioDurationMs: 5_000,
        mode: .direct,
        config: TextPolishConfig(),
        providerAvailable: true
    )
    let translation = TextPolishDecisionEngine().decide(
        normalizedText: "把这段话翻译成英文。",
        audioDurationMs: 2_500,
        mode: .direct,
        config: TextPolishConfig(),
        providerAvailable: true
    )

    #expect(structured.reason == .runAgentPlan)
    #expect(structured.shouldPolish)
    #expect(translation.reason == .runTranslation)
    #expect(translation.shouldPolish)
}

@Test
func textPolishDecisionRunsLongOrExplicitModeDictation() {
    let longDecision = TextPolishDecisionEngine().decide(
        normalizedText: "这是一段较长但没有显式结构指令的听写内容。",
        audioDurationMs: 21_000,
        mode: .direct,
        config: TextPolishConfig(),
        providerAvailable: true
    )
    let emailDecision = TextPolishDecisionEngine().decide(
        normalizedText: "明天下午三点开会。",
        audioDurationMs: 2_000,
        mode: .email,
        config: TextPolishConfig(),
        providerAvailable: true
    )

    #expect(longDecision.reason == .runLongDictation)
    #expect(longDecision.shouldPolish)
    #expect(emailDecision.reason == .runEmail)
    #expect(emailDecision.shouldPolish)
}

@Test
func textPolishDecisionHonorsOffAlwaysAndProviderAvailability() {
    var disabledConfig = TextPolishConfig()
    disabledConfig.mode = .disabled
    let disabled = TextPolishDecisionEngine().decide(
        normalizedText: "请整理成三点。",
        audioDurationMs: 30_000,
        mode: .codePrompt,
        config: disabledConfig,
        providerAvailable: true
    )

    var alwaysConfig = TextPolishConfig()
    alwaysConfig.mode = .always
    let unavailable = TextPolishDecisionEngine().decide(
        normalizedText: "请整理成三点。",
        audioDurationMs: 30_000,
        mode: .codePrompt,
        config: alwaysConfig,
        providerAvailable: false
    )
    let forced = TextPolishDecisionEngine().decide(
        normalizedText: "短句。",
        audioDurationMs: 1_000,
        mode: .direct,
        config: alwaysConfig,
        providerAvailable: true
    )

    #expect(disabled == .init(shouldPolish: false, reason: .disabled))
    #expect(
        unavailable
            == .init(
                shouldPolish: false,
                reason: .providerUnavailable
            )
    )
    #expect(forced == .init(shouldPolish: true, reason: .forcedAlways))
}
