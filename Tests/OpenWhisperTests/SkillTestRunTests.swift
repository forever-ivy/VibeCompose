import Foundation
import Testing
@testable import OpenWhisper

private actor CapturingSkillTestPolisher: TextPolishing {
    private(set) var inputs: [String] = []
    let transform: @Sendable (String) -> String

    init(
        transform: @escaping @Sendable (String) -> String = {
            "Result: \($0)"
        }
    ) {
        self.transform = transform
    }

    func polish(
        text: String,
        terminologyEntries: [TerminologyEntry],
        hintTerms: [String]
    ) async throws -> TextPolishResult {
        _ = terminologyEntries
        _ = hintTerms
        inputs.append(text)
        return TextPolishResult(
            text: transform(text),
            provider: .chatGPTAuth,
            applied: true,
            estimatedInputTokens: 10,
            estimatedOutputTokens: 10
        )
    }
}

private func skillTestPlan(
    required: [ContextSourceKind] = [.voice]
) -> ResolvedSkillExecutionPlan {
    let definition = SkillDefinition(
        id: "local.test.skill-run",
        version: "1.0.0",
        name: "Test Skill",
        author: "Tests",
        promptInstruction: "Transform the input.",
        output: SkillOutputContract(
            format: .plainText,
            delivery: .previewThenPaste,
            risk: .low
        )
    )
    return ResolvedSkillExecutionPlan(
        skill: definition,
        source: .manual,
        matchedApplicationRuleID: nil,
        profile: OpenWhisperSkillProfile(
            contextRequest: ContextRequest(
                required: required,
                optional: []
            ),
            resourceBindings: .init(),
            output: definition.output,
            validators: definition.validators,
            risk: .low
        )
    )
}

@Test
func realSkillTestUsesProviderAndRestoresProtectedLiterals() async throws {
    let polisher = CapturingSkillTestPolisher()
    let execution = try await SkillTestEngine().execute(
        SkillTestRunRequest(
            plan: skillTestPlan(),
            inputText: "Run `swift test` for API v2."
        ),
        using: polisher
    )

    #expect(execution.provider == .chatGPTAuth)
    #expect(execution.generatedText.contains("`swift test`"))
    #expect(execution.generatedText.contains("API v2"))
    #expect(execution.validation.isValid)
    #expect(await polisher.inputs.count == 1)
    #expect(await polisher.inputs[0].contains("⟪OW_LITERAL_"))
}

@Test
func realSkillTestBlocksBeforeProviderWhenRequiredContextIsMissing() async {
    let polisher = CapturingSkillTestPolisher()

    await #expect(
        throws: SkillTestRunError.missingRequiredContext(
            [ContextSourceKind.selection.title]
        )
    ) {
        try await SkillTestEngine().execute(
            SkillTestRunRequest(
                plan: skillTestPlan(
                    required: [.voice, .selection]
                ),
                inputText: "Reply to this."
            ),
            using: polisher
        )
    }
    #expect(await polisher.inputs.isEmpty)
}

@Test
func realSkillTestRejectsProviderThatDropsProtectedLiteral() async {
    let polisher = CapturingSkillTestPolisher { _ in
        "Result without the protected value"
    }

    await #expect(
        throws: SkillTestRunError.protectedLiteralChanged
    ) {
        try await SkillTestEngine().execute(
            SkillTestRunRequest(
                plan: skillTestPlan(),
                inputText: "Keep `swift test` exactly."
            ),
            using: polisher
        )
    }
}

