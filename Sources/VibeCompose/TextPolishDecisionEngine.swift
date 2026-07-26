import Foundation

enum TextPolishDecisionReason: String, Codable, Sendable, Equatable, CaseIterable {
    case disabled
    case providerUnavailable = "provider_unavailable"
    case forcedAlways = "forced_always"
    case skipShortDirect = "skip_short_direct"
    case skipLowComplexity = "skip_low_complexity"
    case runReply = "run_reply"
    case runEmail = "run_email"
    /// Structured-intent heuristic. The raw value predates the Backend
    /// Prompt → Code Prompt merge and is kept stable for telemetry.
    case runAgentPlan = "run_agent_plan"
    case runCodePrompt = "run_code_prompt"
    case runTranslation = "run_translation"
    case runSelfCorrection = "run_self_correction"
    case runLongDictation = "run_long_dictation"
    case runComplexDictation = "run_complex_dictation"
}

struct TextPolishDecision: Sendable, Equatable {
    let shouldPolish: Bool
    let reason: TextPolishDecisionReason
}

protocol TextPolishDeciding: Sendable {
    func decide(
        normalizedText: String,
        audioDurationMs: Int,
        mode: DictationMode,
        config: TextPolishConfig,
        providerAvailable: Bool
    ) -> TextPolishDecision
}

struct TextPolishDecisionEngine: TextPolishDeciding {
    func decide(
        normalizedText: String,
        audioDurationMs: Int,
        mode: DictationMode = .direct,
        config: TextPolishConfig,
        providerAvailable: Bool
    ) -> TextPolishDecision {
        guard config.mode != .disabled else {
            return .init(shouldPolish: false, reason: .disabled)
        }
        guard providerAvailable else {
            return .init(
                shouldPolish: false,
                reason: .providerUnavailable
            )
        }
        if config.mode == .always {
            return .init(shouldPolish: true, reason: .forcedAlways)
        }

        switch mode {
        case .reply:
            return .init(shouldPolish: true, reason: .runReply)
        case .email:
            return .init(shouldPolish: true, reason: .runEmail)
        case .codePrompt:
            return .init(shouldPolish: true, reason: .runCodePrompt)
        case .translate:
            return .init(shouldPolish: true, reason: .runTranslation)
        case .direct:
            break
        }

        let normalized = normalizedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = normalized
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .lowercased()

        if containsAny(
            folded,
            phrases: [
                "翻译成",
                "译成",
                "翻成",
                "translate into",
                "translate to",
                "translation",
            ]
        ) {
            return .init(shouldPolish: true, reason: .runTranslation)
        }
        if containsAny(
            folded,
            phrases: [
                "写封邮件",
                "写一封邮件",
                "发个邮件",
                "发一封邮件",
                "邮件主题",
                "收件人",
                "email",
                "subject line",
            ]
        ) {
            return .init(shouldPolish: true, reason: .runEmail)
        }
        if containsAny(
            folded,
            phrases: [
                "不对",
                "改成",
                "更正",
                "应该说",
                "我的意思是",
                "后面为准",
                "后面的为准",
                "刚才说错",
                "actually",
                "correction",
                "i mean",
            ]
        ) {
            return .init(
                shouldPolish: true,
                reason: .runSelfCorrection
            )
        }
        if hasStructuredIntent(folded) {
            return .init(shouldPolish: true, reason: .runAgentPlan)
        }

        let duration = max(0, audioDurationMs)
        if duration > 20_000 {
            return .init(
                shouldPolish: true,
                reason: .runLongDictation
            )
        }

        let characterCount = meaningfulCharacterCount(normalized)
        let complexityScore = complexityScore(
            text: normalized,
            durationMs: duration,
            characterCount: characterCount
        )
        if complexityScore >= 3 {
            return .init(
                shouldPolish: true,
                reason: .runComplexDictation
            )
        }
        if duration <= 10_000, characterCount <= 80 {
            return .init(
                shouldPolish: false,
                reason: .skipShortDirect
            )
        }
        return .init(
            shouldPolish: false,
            reason: .skipLowComplexity
        )
    }

    private func hasStructuredIntent(_ text: String) -> Bool {
        containsAny(
            text,
            phrases: [
                "整理成",
                "分点",
                "列成",
                "步骤",
                "第一",
                "第二",
                "第三",
                "目标",
                "约束",
                "验收",
                "待办",
                "实施计划",
                "agent plan",
                "bullet",
                "steps",
                "requirements",
                "acceptance criteria",
            ]
        )
    }

    private func complexityScore(
        text: String,
        durationMs: Int,
        characterCount: Int
    ) -> Int {
        var score = 0
        if durationMs >= 10_000 {
            score += 1
        }
        if durationMs >= 15_000 {
            score += 1
        }
        if characterCount >= 80 {
            score += 1
        }
        if characterCount >= 140 {
            score += 1
        }
        if sentenceTerminatorCount(text) >= 3 {
            score += 1
        }
        if text.contains("\n- ")
            || text.contains("\n• ")
            || text.contains("\n1.")
            || text.contains("\n1、")
        {
            score += 2
        }
        return score
    }

    private func containsAny(
        _ text: String,
        phrases: [String]
    ) -> Bool {
        phrases.contains { text.contains($0) }
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
