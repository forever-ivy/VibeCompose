import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SkillCreatorSettingsView: View {
    private enum EditorMode:
        String,
        CaseIterable,
        Identifiable
    {
        case simple = "Simple"
        case advanced = "Advanced"

        var id: String { rawValue }
    }

    private enum SelectionRequirement:
        String,
        CaseIterable,
        Identifiable
    {
        case unused = "No selection"
        case optional = "Optional selection"
        case required = "Required selection"

        var id: String { rawValue }
    }

    private struct TestBenchReport {
        let prompt: String
        let validation:
            SkillValidationReport
        let sentCategories: [String]
        let characterCount: Int
        let resultText: String?
        let providerLabel: String?
        let expectedOutputMatches: Bool?
    }

    @Binding var config: AppConfig
    @Binding var inventory: CommunitySkillInventory
    let store: SkillPackageStore
    let localAssetAccessEnabled: Bool
    let onRunTest:
        (SkillTestRunRequest) async
            -> Result<SkillTestRunResult, any Error>
    let onVoiceSampleAction:
        (SkillVoiceSampleAction) async
            -> Result<SkillVoiceSampleResult, any Error>

    @State private var selectedTemplate: SkillCreatorTemplateID = .codingPrompt
    @State private var draft = SkillCreatorDraft.template(.codingPrompt)
    @State private var validationReport: SkillCreatorValidationReport?
    @State private var message: String?
    @State private var messageIsError = false
    @State private var showsAdvanced = false
    @State private var editorMode:
        EditorMode = .simple
    @State private var exampleInput = ""
    @State private var expectedOutput = ""
    @State private var simulatedSelection = ""
    @State private var simulatedStyle = ""
    @State private var simulatedTerminology = ""
    @State private var testBenchReport:
        TestBenchReport?
    @State private var showsCompiledPrompt = false
    @State private var isRunningTest = false
    @State private var isRecordingVoiceSample = false
    @State private var isTranscribingVoiceSample = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("Skill Creator"))
                        .font(.system(size: 12, weight: .semibold))
                }
                Spacer(minLength: 12)
                Menu {
                    ForEach(SkillCreatorTemplateID.allCases) { template in
                        Button(L10n.text(template.title)) {
                            selectedTemplate = template
                        }
                    }
                } label: {
                    Label(
                        L10n.text(selectedTemplate.title),
                        systemImage: "chevron.down"
                    )
                }
                .buttonStyle(OpenWhisperSecondaryButtonStyle())
                .frame(minWidth: 160, idealWidth: 210, maxWidth: 260)
            }

            creatorModeControl

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    editorFields
                }
                VStack(alignment: .leading, spacing: 10) {
                    editorFields
                }
            }

            if editorMode == .simple {
                simpleExamples
            } else {
                VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text("SKILL.md Instructions"))
                    .font(.system(size: 11, weight: .medium))
                TextEditor(text: $draft.instructions)
                    .accessibilityLabel(
                        L10n.text("SKILL.md Instructions")
                    )
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 110, idealHeight: 140, maxHeight: 220)
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .background(
                        Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.5)
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { profileControls }
                VStack(alignment: .leading, spacing: 10) { profileControls }
            }

            testBench

            if editorMode == .advanced {
                DisclosureGroup(
                L10n.text("References, Assets & Golden Tests"),
                isExpanded: $showsAdvanced
            ) {
                advancedResources
                    .padding(.top, 8)
            }
                .font(.system(size: 11, weight: .medium))
            }

            if let validationReport {
                if validationReport.isValid {
                    InlineStatus(
                        text: L10n.text("The draft passes standard format and OpenWhisper runtime validation."),
                        kind: validationReport.warnings.isEmpty ? .success : .warning
                    )
                }
                ForEach(validationReport.errors, id: \.self) {
                    InlineStatus(text: $0, kind: .error)
                }
                ForEach(validationReport.warnings, id: \.self) {
                    InlineStatus(text: $0, kind: .warning)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { actionControls }
                VStack(alignment: .leading, spacing: 8) { actionControls }
            }

            if let message {
                InlineStatus(
                    text: message,
                    kind: messageIsError ? .error : .success
                )
            }
        }
        .onChange(of: selectedTemplate) { template in
            draft = .template(template)
            validationReport = nil
            message = nil
            testBenchReport = nil
        }
        .onDisappear {
            guard isRecordingVoiceSample else { return }
            Task { @MainActor in
                _ = await onVoiceSampleAction(.cancel)
                isRecordingVoiceSample = false
            }
        }
    }

    private var creatorModeControl: some View {
        HStack(spacing: 4) {
            ForEach(EditorMode.allCases) { mode in
                Button {
                    editorMode = mode
                } label: {
                    Text(L10n.text(mode.rawValue))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(
                            editorMode == mode
                                ? Color.white
                                : Color.primary
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            editorMode == mode
                                ? Color(
                                    nsColor:
                                        OpenWhisperPalette.brandBlue
                                )
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(maxWidth: 300)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("Creator mode"))
    }

    private var simpleExamples: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text("Example input and expected output"))
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Button {
                    toggleVoiceSampleRecording()
                } label: {
                    Label(
                        voiceSampleButtonTitle,
                        systemImage: isRecordingVoiceSample
                            ? "stop.circle.fill"
                            : "mic.circle"
                    )
                }
                .buttonStyle(OpenWhisperSecondaryButtonStyle())
                .disabled(
                    isTranscribingVoiceSample
                        || isRunningTest
                )
            }
            if isRecordingVoiceSample {
                Label(
                    L10n.text(
                        "Recording a temporary voice sample. Stop when finished; the audio is deleted after transcription."
                    ),
                    systemImage: "record.circle"
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.red)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    exampleEditor(
                        title: "What you say",
                        text: $exampleInput
                    )
                    exampleEditor(
                        title: "What the Skill should produce",
                        text: $expectedOutput
                    )
                }
                VStack(alignment: .leading, spacing: 10) {
                    exampleEditor(
                        title: "What you say",
                        text: $exampleInput
                    )
                    exampleEditor(
                        title: "What the Skill should produce",
                        text: $expectedOutput
                    )
                }
            }
        }
    }

    private func exampleEditor(
        title: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text(title))
                .font(.system(size: 10, weight: .semibold))
            TextEditor(text: text)
                .accessibilityLabel(L10n.text(title))
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: 90, idealHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(7)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var editorFields: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text("Portable name"))
                .font(.system(size: 10, weight: .semibold))
            TextField(
                L10n.text("Portable name"),
                text: $draft.name
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(L10n.text("Portable name"))
        }
        .frame(minWidth: 150, idealWidth: 210, maxWidth: 280)

        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text("Description"))
                .font(.system(size: 10, weight: .semibold))
            TextField(
                L10n.text("Description"),
                text: $draft.description
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(L10n.text("Description"))
        }
        .frame(minWidth: 220, idealWidth: 330, maxWidth: .infinity)
    }

    @ViewBuilder
    private var profileControls: some View {
        Menu {
            ForEach(
                [
                    SkillOutputFormat.plainText,
                    .markdown,
                    .json,
                    .template,
                ],
                id: \.rawValue
            ) { format in
                Button(format.localizedLabel) {
                    draft.profile.output.format = format
                }
            }
        } label: {
            profileMenuLabel(
                title: "Output",
                value: draft.profile.output.format.localizedLabel
            )
        }
        .buttonStyle(OpenWhisperSecondaryButtonStyle())

        Menu {
            Button(SkillDeliveryPolicy.previewThenPaste.localizedLabel) {
                draft.profile.output.delivery = .previewThenPaste
            }
            Button(SkillDeliveryPolicy.copyOnly.localizedLabel) {
                draft.profile.output.delivery = .copyOnly
            }
            if draft.profile.risk == .low {
                Button(
                    SkillDeliveryPolicy
                        .automaticPasteWhenVerified.localizedLabel
                ) {
                    draft.profile.output.delivery =
                        .automaticPasteWhenVerified
                }
            }
        } label: {
            profileMenuLabel(
                title: "Delivery",
                value: draft.profile.output.delivery.localizedLabel
            )
        }
        .buttonStyle(OpenWhisperSecondaryButtonStyle())

        Menu {
            ForEach(
                [SkillRiskLevel.low, .medium, .high],
                id: \.rawValue
            ) { risk in
                Button(risk.localizedLabel) {
                    riskBinding.wrappedValue = risk
                }
            }
        } label: {
            profileMenuLabel(
                title: "Risk",
                value: draft.profile.risk.localizedLabel
            )
        }
        .buttonStyle(OpenWhisperSecondaryButtonStyle())

        Menu {
            ForEach(SelectionRequirement.allCases) {
                requirement in
                Button(L10n.text(requirement.rawValue)) {
                    selectionRequirementBinding.wrappedValue =
                        requirement
                }
            }
        } label: {
            profileMenuLabel(
                title: "Selected text",
                value: L10n.text(
                    selectionRequirementBinding.wrappedValue.rawValue
                )
            )
        }
        .buttonStyle(OpenWhisperSecondaryButtonStyle())

        Toggle(L10n.text("Style"), isOn: contextBinding(.styleCapsule))
    }

    private func profileMenuLabel(
        title: String,
        value: String
    ) -> some View {
        HStack(spacing: 5) {
            Text(L10n.text(title))
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.primary)
            Image(systemName: "chevron.down")
                .foregroundStyle(.secondary)
        }
    }

    private var testBench: some View {
        DisclosureGroup(
            L10n.text("Test Bench"),
            isExpanded: .constant(true)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if editorMode == .advanced {
                    HStack(alignment: .top, spacing: 8) {
                        testContextEditor(
                            title: "Simulated selection",
                            text: $simulatedSelection
                        )
                        testContextEditor(
                            title: "Simulated style",
                            text: $simulatedStyle
                        )
                        testContextEditor(
                            title: "Simulated terminology",
                            text: $simulatedTerminology
                        )
                    }
                }

                HStack(spacing: 10) {
                    Button(
                        isRunningTest
                            ? L10n.text("Running Test…")
                            : L10n.text("Run Real Test")
                    ) {
                        runTestBench()
                    }
                    .buttonStyle(OpenWhisperPrimaryButtonStyle())
                    .disabled(
                        isRunningTest
                            || exampleInput
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                                .isEmpty
                    )
                }

                if let testBenchReport {
                    Label(
                        testBenchReport.validation.isValid
                            ? L10n.text("Validator passed")
                            : L10n.format(
                                "Validator failed: %@",
                                testBenchReport.validation
                                    .issues
                                    .map { $0.code.rawValue }
                                    .joined(separator: ", ")
                            ),
                        systemImage:
                            testBenchReport.validation.isValid
                            ? "checkmark.shield.fill"
                            : "exclamationmark.shield.fill"
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        testBenchReport.validation.isValid
                        ? .green
                        : .orange
                    )
                    Text(
                        L10n.format(
                            "Data categories: %@ · %ld characters before Provider",
                            testBenchReport.sentCategories
                                .joined(separator: ", "),
                            testBenchReport.characterCount
                        )
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                    if let providerLabel = testBenchReport.providerLabel {
                        Text(
                            L10n.format(
                                "Provider: %@",
                                providerLabel
                            )
                        )
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    }

                    if let expectedOutputMatches =
                        testBenchReport.expectedOutputMatches
                    {
                        Label(
                            expectedOutputMatches
                                ? L10n.text(
                                    "Matches expected output"
                                )
                                : L10n.text(
                                    "Differs from expected output; review the result or refine the Skill."
                                ),
                            systemImage: expectedOutputMatches
                                ? "equal.circle.fill"
                                : "arrow.left.and.right.circle"
                        )
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(
                            expectedOutputMatches
                                ? .green
                                : .orange
                        )
                    }

                    if let resultText = testBenchReport.resultText {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L10n.text("Test result"))
                                .font(.system(size: 10, weight: .semibold))
                            Text(resultText)
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                                .padding(8)
                                .background(
                                    Color(nsColor: .textBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                        }
                    }

                    DisclosureGroup(
                        L10n.text("Compiled request layers"),
                        isExpanded: $showsCompiledPrompt
                    ) {
                        Text(testBenchReport.prompt)
                            .font(.system(size: 9, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.top, 6)
                    }
                    .font(.system(size: 10, weight: .medium))
                }
            }
            .padding(.top, 8)
        }
        .font(.system(size: 11, weight: .medium))
    }

    private func testContextEditor(
        title: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text(title))
                .font(.system(size: 9, weight: .semibold))
            TextEditor(text: text)
                .accessibilityLabel(L10n.text(title))
                .font(.system(size: 9, design: .monospaced))
                .frame(minHeight: 62)
                .scrollContentBackground(.hidden)
                .padding(5)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .frame(maxWidth: .infinity)
    }

    private var advancedResources: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { resourceButtons }
                VStack(alignment: .leading, spacing: 8) { resourceButtons }
            }
            ForEach(draft.references.keys.sorted(), id: \.self) { path in
                resourceRow(path: path, isAsset: false)
            }
            ForEach(draft.assets.keys.sorted(), id: \.self) { path in
                resourceRow(path: path, isAsset: true)
            }
            TextEditor(text: goldenCasesBinding)
                .accessibilityLabel(
                    L10n.text("Optional Golden cases as JSONL")
                )
                .font(.system(size: 10, design: .monospaced))
                .frame(minHeight: 72, idealHeight: 90, maxHeight: 150)
                .overlay(alignment: .topLeading) {
                    if (draft.goldenCasesJSONL ?? "").isEmpty {
                        Text(L10n.text("Optional Golden cases as JSONL"))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    @ViewBuilder
    private var resourceButtons: some View {
        Button(L10n.text("Add Reference…"), action: addReference)
            .buttonStyle(OpenWhisperSecondaryButtonStyle())
        Button(L10n.text("Add Static Asset…"), action: addAsset)
            .buttonStyle(OpenWhisperSecondaryButtonStyle())
        Text(L10n.format(
            "%ld references · %ld assets",
            draft.references.count,
            draft.assets.count
        ))
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private func resourceRow(path: String, isAsset: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isAsset ? "photo" : "doc.text")
                .foregroundStyle(.secondary)
            Text(path)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
            Spacer()
            Button(L10n.text("Remove"), role: .destructive) {
                if isAsset { draft.assets.removeValue(forKey: path) }
                else { draft.references.removeValue(forKey: path) }
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var actionControls: some View {
        Button(L10n.text("Validate Draft")) {
            validationReport = SkillCreator()
                .validate(preparedDraft)
        }
        .buttonStyle(OpenWhisperSecondaryButtonStyle())
        Button(L10n.text("Export & Install…"), action: exportAndInstall)
            .buttonStyle(OpenWhisperPrimaryButtonStyle())
            .disabled(!localAssetAccessEnabled)
        Spacer(minLength: 0)
    }

    private var preparedDraft: SkillCreatorDraft {
        var value = draft
        let input = exampleInput.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let output = expectedOutput.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !input.isEmpty || !output.isEmpty {
            let inputExample = input.isEmpty
                ? "Not provided"
                : input
            let outputExample = output.isEmpty
                ? "Not provided"
                : output
            value.instructions +=
                "\n\n## Example\n\nInput:\n\(inputExample)\n\nExpected output:\n\(outputExample)"
        }
        return value
    }

    private var voiceSampleButtonTitle: String {
        if isTranscribingVoiceSample {
            return L10n.text("Transcribing…")
        }
        if isRecordingVoiceSample {
            return L10n.text("Stop & Transcribe")
        }
        return L10n.text("Record Voice Sample")
    }

    private func toggleVoiceSampleRecording() {
        let action: SkillVoiceSampleAction =
            isRecordingVoiceSample
            ? .stopAndTranscribe
            : .start
        if action == .stopAndTranscribe {
            isTranscribingVoiceSample = true
        }
        Task { @MainActor in
            let result = await onVoiceSampleAction(action)
            isTranscribingVoiceSample = false
            switch result {
            case .success(.recording):
                isRecordingVoiceSample = true
                message = nil
            case .success(.transcribed(let text)):
                isRecordingVoiceSample = false
                exampleInput = text
                message = L10n.text(
                    "Voice sample transcribed into the temporary test input."
                )
                messageIsError = false
            case .success(.cancelled):
                isRecordingVoiceSample = false
            case .failure(let error):
                isRecordingVoiceSample = false
                message = error.localizedDescription
                messageIsError = true
                NSSound.beep()
            }
        }
    }

    private func runTestBench() {
        let candidateDraft = preparedDraft
        let normalizedInput = exampleInput
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        let candidateOutput = expectedOutput
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        let definition = SkillDefinition(
            id: "local.creator.test-bench",
            version:
                SkillDefinition.isValidVersion(
                    candidateDraft.version
                )
                ? candidateDraft.version
                : "1.0.0",
            name: candidateDraft.name.isEmpty
                ? "Local Test Skill"
                : candidateDraft.name,
            author: candidateDraft.author,
            requiredCapabilities:
                capabilities(
                    candidateDraft.profile
                        .contextRequest.required,
                    includesVoice: true
                ),
            optionalCapabilities:
                capabilities(
                    candidateDraft.profile
                        .contextRequest.optional,
                    includesVoice: false
                ),
            promptInstruction:
                candidateDraft.instructions,
            output:
                candidateDraft.profile.output,
            validators:
                candidateDraft.profile.validators
        )
        let plan = ResolvedSkillExecutionPlan(
            skill: definition,
            source: .manual,
            matchedApplicationRuleID: nil,
            profile: candidateDraft.profile
        )
        let terminology = simulatedTerminology
            .split(whereSeparator: \.isNewline)
            .map {
                TerminologyEntry(
                    canonical:
                        String($0).trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ),
                    aliases: [],
                    source: "creator-test-bench"
                )
            }
            .filter { !$0.canonical.isEmpty }
        let selection = simulatedSelection
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        let style = simulatedStyle
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        let context = SkillPromptContext(
            styleCapsule:
                style.isEmpty ? nil : style,
            selection:
                selection.isEmpty
                ? nil
                : selection
        )
        let messages = SkillPromptCompiler().compile(
            transcript: normalizedInput,
            terminologyEntries: terminology,
            config: config.transcription.textPolish,
            plan: plan,
            context: context
        )
        let validation = SkillValidatorEngine()
            .validate(
                output: candidateOutput,
                originalText: [
                    normalizedInput,
                    selection,
                ]
                .filter { !$0.isEmpty }
                .joined(separator: "\n"),
                plan: plan
            )
        var categories = [L10n.text("Voice")]
        if !selection.isEmpty {
            categories.append(
                L10n.text("Selected text")
            )
        }
        if !style.isEmpty {
            categories.append(
                L10n.text("Style Capsule")
            )
        }
        if !terminology.isEmpty {
            categories.append(
                L10n.text("Terminology")
            )
        }
        let compiledPrompt = messages.map {
            "[\($0.role.uppercased())]\n\($0.content)"
        }.joined(separator: "\n\n")
        let characterCount =
            normalizedInput.count
            + selection.count
            + style.count
            + terminology.reduce(0) {
                $0 + $1.canonical.count
            }
        testBenchReport = TestBenchReport(
            prompt: compiledPrompt,
            validation: validation,
            sentCategories: categories,
            characterCount: characterCount,
            resultText: nil,
            providerLabel: nil,
            expectedOutputMatches: nil
        )

        guard !normalizedInput.isEmpty else {
            message = SkillTestRunError.emptyInput.localizedDescription
            messageIsError = true
            return
        }

        isRunningTest = true
        message = nil
        let expected = candidateOutput.isEmpty
            ? nil
            : candidateOutput
        Task { @MainActor in
            let result = await onRunTest(
                SkillTestRunRequest(
                    plan: plan,
                    inputText: normalizedInput,
                    context: context,
                    terminologyEntries: terminology,
                    expectedOutput: expected
                )
            )
            isRunningTest = false
            switch result {
            case .success(let result):
                guard !result.wasCancelled else {
                    message = L10n.text("Skill test cancelled.")
                    messageIsError = false
                    return
                }
                testBenchReport = TestBenchReport(
                    prompt: compiledPrompt,
                    validation: result.validation,
                    sentCategories: categories,
                    characterCount: characterCount,
                    resultText: result.finalText,
                    providerLabel: result.provider?.title,
                    expectedOutputMatches: expected.map {
                        $0.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ) == result.finalText.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                    }
                )
                message = result.wasEdited
                    ? L10n.text(
                        "Real test completed with your Preview edits."
                    )
                    : L10n.text("Real test completed.")
                messageIsError = !result.validation.isValid
            case .failure(let error):
                message = error.localizedDescription
                messageIsError = true
                NSSound.beep()
            }
        }
    }

    private func capabilities(
        _ sources: [ContextSourceKind],
        includesVoice: Bool
    ) -> [SkillCapability] {
        var output: [SkillCapability] =
            includesVoice ? [.voice] : []
        for source in sources {
            let capability: SkillCapability? =
                switch source {
                case .voice:
                    .voice
                case .selection:
                    .selection
                case .focusedParagraph:
                    .focusedParagraph
                case .conversationWindow:
                    .conversationWindow
                case .clipboard:
                    .clipboard
                case .styleCapsule:
                    .styleCapsule
                case .activeApp,
                     .terminology,
                     .openFile,
                     .workspace,
                     .editorDiagnostics,
                     .terminalSession,
                     .browserPage:
                    nil
                }
            if let capability,
               !output.contains(capability)
            {
                output.append(capability)
            }
        }
        return output
    }

    private var outputFormatBinding: Binding<SkillOutputFormat> {
        Binding(
            get: { draft.profile.output.format },
            set: { draft.profile.output.format = $0 }
        )
    }

    private var deliveryBinding: Binding<SkillDeliveryPolicy> {
        Binding(
            get: { draft.profile.output.delivery },
            set: { draft.profile.output.delivery = $0 }
        )
    }

    private var riskBinding: Binding<SkillRiskLevel> {
        Binding(
            get: { draft.profile.risk },
            set: { risk in
                draft.profile.risk = risk
                draft.profile.output.risk = risk
                if risk != .low,
                   draft.profile.output.delivery == .automaticPasteWhenVerified
                {
                    draft.profile.output.delivery = .previewThenPaste
                }
            }
        )
    }

    private var selectionRequirementBinding:
        Binding<SelectionRequirement>
    {
        Binding(
            get: {
                if draft.profile.contextRequest
                    .required.contains(.selection)
                {
                    return .required
                }
                if draft.profile.contextRequest
                    .optional.contains(.selection)
                {
                    return .optional
                }
                return .unused
            },
            set: { requirement in
                var required = draft.profile
                    .contextRequest.required
                    .filter { $0 != .selection }
                var optional = draft.profile
                    .contextRequest.optional
                    .filter { $0 != .selection }
                switch requirement {
                case .unused:
                    break
                case .optional:
                    optional.append(.selection)
                case .required:
                    required.append(.selection)
                    draft.profile.output.delivery =
                        .previewThenPaste
                }
                draft.profile.contextRequest =
                    ContextRequest(
                        required: required,
                        optional: optional
                    )
            }
        )
    }

    private func contextBinding(_ source: ContextSourceKind) -> Binding<Bool> {
        Binding(
            get: { draft.profile.contextRequest.optional.contains(source) },
            set: { enabled in
                var values = draft.profile.contextRequest.optional.filter { $0 != source }
                if enabled { values.append(source) }
                draft.profile.contextRequest = ContextRequest(
                    required: draft.profile.contextRequest.required,
                    optional: values
                )
            }
        )
    }

    private var goldenCasesBinding: Binding<String> {
        Binding(
            get: { draft.goldenCasesJSONL ?? "" },
            set: { draft.goldenCasesJSONL = $0.isEmpty ? nil : $0 }
        )
    }

    private func addReference() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText, .json, .commaSeparatedText]
        guard panel.runModal() == .OK else { return }
        for url in panel.urls.prefix(20) {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                draft.references["references/\(url.lastPathComponent)"] = String(text.prefix(100_000))
            }
        }
    }

    private func addAsset() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls.prefix(20) {
            if let data = try? Data(contentsOf: url), data.count <= 512 * 1_024 {
                draft.assets["assets/\(url.lastPathComponent)"] = data
            }
        }
    }

    private func exportAndInstall() {
        let candidateDraft = preparedDraft
        let validation = SkillCreator()
            .validate(candidateDraft)
        validationReport = validation
        guard validation.isValid else {
            message = L10n.text("Fix validation errors before exporting the Skill.")
            messageIsError = true
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = L10n.text("Export Standard Agent Skill")
        panel.prompt = L10n.text("Export & Install")
        panel.nameFieldStringValue = draft.name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let package = try SkillCreator()
                .export(candidateDraft, to: url)
            let reimported = try AgentSkillPackageLoader().load(from: url)
            guard reimported.contentSHA256 == package.contentSHA256 else {
                throw TrustedSkillRegistryError.hashMismatch
            }
            let installed = try store.install(from: url)
            config.communitySkills.setActiveVersion(
                installed.definition.version,
                for: installed.definition.id
            )
            config.transcription.skills.setEnabled(
                installed.compatibility.runtimeStatus == .compatible,
                skillID: installed.definition.id
            )
            inventory = store.loadInventory(config: config.communitySkills)
            message = L10n.format(
                "Exported and installed %@ %@.",
                installed.definition.name,
                installed.definition.version
            )
            messageIsError = false
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }
}
