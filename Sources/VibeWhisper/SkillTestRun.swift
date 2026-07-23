import Foundation

enum SkillVoiceSampleAction: Sendable, Equatable {
    case start
    case stopAndTranscribe
    case cancel
}

enum SkillVoiceSampleResult: Sendable, Equatable {
    case recording
    case transcribed(String)
    case cancelled
}

struct SkillTestRunRequest: Sendable {
    let plan: ResolvedSkillExecutionPlan
    let inputText: String
    let context: SkillPromptContext
    let terminologyEntries: [TerminologyEntry]
    let expectedOutput: String?

    init(
        plan: ResolvedSkillExecutionPlan,
        inputText: String,
        context: SkillPromptContext = .init(),
        terminologyEntries: [TerminologyEntry] = [],
        expectedOutput: String? = nil
    ) {
        self.plan = plan
        self.inputText = inputText
        self.context = context
        self.terminologyEntries = terminologyEntries
        self.expectedOutput = expectedOutput
    }
}

struct SkillTestRunResult: Sendable, Equatable {
    let generatedText: String
    let finalText: String
    let validation: SkillValidationReport
    let provider: TextPolishProviderID?
    let wasEdited: Bool
    let wasCancelled: Bool
}

struct SkillTestExecution: Sendable, Equatable {
    let inputText: String
    let generatedText: String
    let validation: SkillValidationReport
    let provider: TextPolishProviderID?
}

struct SkillTestEngine: Sendable {
    var literalTokenizer = TechnicalLiteralTokenizer()
    var validator = SkillValidatorEngine()

    func execute(
        _ request: SkillTestRunRequest,
        using polisher: any TextPolishing
    ) async throws -> SkillTestExecution {
        let input = request.inputText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !input.isEmpty else {
            throw SkillTestRunError.emptyInput
        }
        let missingContext = request.plan.profile
            .contextRequest.required.filter { source in
                switch source {
                case .voice:
                    return false
                case .selection:
                    return request.context.selection?
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty != false
                case .styleCapsule:
                    return request.context.styleCapsule?
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty != false
                case .terminology:
                    return request.terminologyEntries.isEmpty
                case .activeApp,
                     .focusedParagraph,
                     .openFile,
                     .workspace,
                     .editorDiagnostics,
                     .terminalSession,
                     .browserPage,
                     .conversationWindow,
                     .clipboard:
                    return true
                }
            }
        guard missingContext.isEmpty else {
            throw SkillTestRunError.missingRequiredContext(
                missingContext.map(\.title)
            )
        }

        let tokenization =
            request.plan.skill
                .protectsVoiceTechnicalLiterals
            ? literalTokenizer.tokenize(
                input,
                style: .modelSafe
            )
            : TechnicalLiteralTokenization
                .passthrough(input)
        let result = try await polisher.polish(
            text: tokenization.maskedText,
            terminologyEntries: request.terminologyEntries,
            hintTerms: []
        )
        guard let generatedText = tokenization
            .restoringLiterals(in: result.text)
        else {
            throw SkillTestRunError.protectedLiteralChanged
        }
        let originalText = request.plan.skill
            .validationSourceText(
                transcript: input,
                selection:
                    request.context.selection
            )
        return SkillTestExecution(
            inputText: input,
            generatedText: generatedText,
            validation: validator.validate(
                output: generatedText,
                originalText: originalText,
                plan: request.plan
            ),
            provider: result.provider
        )
    }
}

enum SkillTestRunError: LocalizedError, Equatable {
    case emptyInput
    case appBusy
    case chatGPTConnectionRequired
    case missingRequiredContext([String])
    case protectedLiteralChanged

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return L10n.text(
                "Enter a test input before running this Skill."
            )
        case .appBusy:
            return L10n.text(
                "Finish or cancel the current dictation before running a Skill test."
            )
        case .chatGPTConnectionRequired:
            return L10n.text(
                "Connect ChatGPT before running a real Skill test. The test uses the same private, non-stable browser connection as dictation."
            )
        case .missingRequiredContext(let labels):
            return L10n.format(
                "Provide the required test Context before running: %@.",
                labels.joined(separator: ", ")
            )
        case .protectedLiteralChanged:
            return L10n.text(
                "The test Provider changed a protected technical literal, so VibeWhisper rejected the result."
            )
        }
    }
}
