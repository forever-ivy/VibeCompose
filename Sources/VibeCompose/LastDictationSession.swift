import Foundation

/// In-memory cache of the most recent successful dictation so the user can
/// reopen Preview (even with HUD hidden) and re-run a different Skill on the
/// same source transcript without re-recording.
///
/// Privacy notes:
/// - Memory only — never written to disk / History.
/// - Selection text is retained only for the current process lifetime and is
///   cleared on privacy-sensitive operations (delete-all, snapshot mode).
/// - Default TTL is 30 minutes; expired sessions are treated as missing.
struct LastDictationSession: Sendable, Equatable {
    let id: UUID
    /// Normalized ASR text used as Skill input / Preview "source".
    let originalTranscript: String
    /// Last Skill output (or user-edited Preview text after confirm).
    let lastResultText: String
    let skillPlan: ResolvedSkillExecutionPlan
    let skillPromptContext: SkillPromptContext
    let contextCapabilities: [SkillCapability]
    let terminologyEntries: [TerminologyEntry]
    let allowsPasteToTarget: Bool
    let allowsSelectionReplacement: Bool
    /// AX selection identity captured at dictation time; used to re-verify before
    /// Replace Selection on Preview reopen / reprocess.
    let selectionSnapshot: SelectionContextSnapshot?
    let preparedAt: Date
    /// Soft expiry so a stale session cannot be re-sent days later.
    let expiresAt: Date

    static let defaultTTL: TimeInterval = 30 * 60

    var isExpired: Bool {
        Date() >= expiresAt
    }

    init(
        id: UUID = UUID(),
        originalTranscript: String,
        lastResultText: String,
        skillPlan: ResolvedSkillExecutionPlan,
        skillPromptContext: SkillPromptContext = .init(),
        contextCapabilities: [SkillCapability] = [.voice],
        terminologyEntries: [TerminologyEntry] = [],
        allowsPasteToTarget: Bool,
        allowsSelectionReplacement: Bool,
        selectionSnapshot: SelectionContextSnapshot? = nil,
        preparedAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.originalTranscript = originalTranscript
        self.lastResultText = lastResultText
        self.skillPlan = skillPlan
        self.skillPromptContext = skillPromptContext
        self.contextCapabilities = contextCapabilities
        self.terminologyEntries = terminologyEntries
        self.allowsPasteToTarget = allowsPasteToTarget
        self.allowsSelectionReplacement = allowsSelectionReplacement
        self.selectionSnapshot = selectionSnapshot
        self.preparedAt = preparedAt
        self.expiresAt = expiresAt
            ?? preparedAt.addingTimeInterval(Self.defaultTTL)
    }

    func withResultText(_ text: String) -> LastDictationSession {
        LastDictationSession(
            id: id,
            originalTranscript: originalTranscript,
            lastResultText: text,
            skillPlan: skillPlan,
            skillPromptContext: skillPromptContext,
            contextCapabilities: contextCapabilities,
            terminologyEntries: terminologyEntries,
            allowsPasteToTarget: allowsPasteToTarget,
            allowsSelectionReplacement: allowsSelectionReplacement,
            selectionSnapshot: selectionSnapshot,
            preparedAt: preparedAt,
            expiresAt: expiresAt
        )
    }

    func withSkillPlan(
        _ plan: ResolvedSkillExecutionPlan,
        resultText: String
    ) -> LastDictationSession {
        LastDictationSession(
            id: id,
            originalTranscript: originalTranscript,
            lastResultText: resultText,
            skillPlan: plan,
            skillPromptContext: skillPromptContext,
            contextCapabilities: contextCapabilities,
            terminologyEntries: terminologyEntries,
            allowsPasteToTarget: allowsPasteToTarget,
            allowsSelectionReplacement: allowsSelectionReplacement,
            selectionSnapshot: selectionSnapshot,
            preparedAt: preparedAt,
            expiresAt: expiresAt
        )
    }

    /// Payload for reopening Preview without a model call.
    func makePreviewRequest(
        resultText: String? = nil,
        plan: ResolvedSkillExecutionPlan? = nil,
        validationIssueCodes: [String] = [],
        fallbackMessage: String? = nil,
        skillChoices: [SkillMenuEntry] = [],
        currentSkillInstallationID: UUID? = nil
    ) -> PreviewRequest {
        let plan = plan ?? skillPlan
        return PreviewRequest(
            skillID: plan.skill.id,
            skillVersion: plan.skill.version,
            skillName: plan.skill.localizedName,
            originalTranscript: originalTranscript,
            resultText: resultText ?? lastResultText,
            selectedText: skillPromptContext.selection,
            contextCapabilities: contextCapabilities,
            initialValidationIssueCodes: validationIssueCodes,
            fallbackMessage: fallbackMessage,
            allowsSelectionReplacement: allowsSelectionReplacement,
            allowsPasteToTarget: allowsPasteToTarget,
            executionPlan: plan,
            skillChoices: skillChoices,
            currentSkillInstallationID:
                currentSkillInstallationID ?? plan.installation.id
        )
    }
}
