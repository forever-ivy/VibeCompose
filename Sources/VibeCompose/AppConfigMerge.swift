import Foundation

/// 3-way merge for Settings draft rebasing against concurrent coordinator writes.
///
/// For each field: if `local` differs from `base` (user dirty in Settings), keep
/// `local`; otherwise take `remote` (live coordinator / disk). Nested
/// `TranscriptionConfig` is merged field-by-field so skill-menu / Quick Add
/// changes do not clobber an unrelated dirty hotkey (or vice versa).
///
/// Concurrent edits to the *same* leaf still last-write within that leaf — that
/// matches the known product races (skills/menu vs appearance; recents vs
/// Settings toggles).
enum AppConfigMerge {
    static func merging(
        base: AppConfig,
        local: AppConfig,
        remote: AppConfig
    ) -> AppConfig {
        AppConfig.merging(base: base, local: local, remote: remote)
    }
}

extension AppConfig {
    /// Prefer local where it diverged from base; otherwise adopt remote.
    static func merging(
        base: AppConfig,
        local: AppConfig,
        remote: AppConfig
    ) -> AppConfig {
        if local == base {
            return remote
        }
        if local == remote {
            return local
        }

        var result = remote
        result.appLanguage = pick(
            base: base.appLanguage,
            local: local.appLanguage,
            remote: remote.appLanguage
        )
        result.skillSwitcherHotkey = pick(
            base: base.skillSwitcherHotkey,
            local: local.skillSwitcherHotkey,
            remote: remote.skillSwitcherHotkey
        )
        result.resultPreviewHotkey = pick(
            base: base.resultPreviewHotkey,
            local: local.resultPreviewHotkey,
            remote: remote.resultPreviewHotkey
        )
        result.transcription = TranscriptionConfig.merging(
            base: base.transcription,
            local: local.transcription,
            remote: remote.transcription
        )
        result.injection = pick(
            base: base.injection,
            local: local.injection,
            remote: remote.injection
        )
        result.auth = pick(
            base: base.auth,
            local: local.auth,
            remote: remote.auth
        )
        result.privacy = pick(
            base: base.privacy,
            local: local.privacy,
            remote: remote.privacy
        )
        result.visualFeedback = pick(
            base: base.visualFeedback,
            local: local.visualFeedback,
            remote: remote.visualFeedback
        )
        result.context = pick(
            base: base.context,
            local: local.context,
            remote: remote.context
        )
        result.styleCapsules = pick(
            base: base.styleCapsules,
            local: local.styleCapsules,
            remote: remote.styleCapsules
        )
        result.terminologyPacks = pick(
            base: base.terminologyPacks,
            local: local.terminologyPacks,
            remote: remote.terminologyPacks
        )
        result.communitySkills = pick(
            base: base.communitySkills,
            local: local.communitySkills,
            remote: remote.communitySkills
        )
        result.skillEcosystem = pick(
            base: base.skillEcosystem,
            local: local.skillEcosystem,
            remote: remote.skillEcosystem
        )
        return result
    }

    private static func pick<T: Equatable>(
        base: T,
        local: T,
        remote: T
    ) -> T {
        local != base ? local : remote
    }
}

extension TranscriptionConfig {
    static func merging(
        base: TranscriptionConfig,
        local: TranscriptionConfig,
        remote: TranscriptionConfig
    ) -> TranscriptionConfig {
        if local == base {
            return remote
        }
        if local == remote {
            return local
        }

        var result = remote
        result.provider = pick(
            base: base.provider,
            local: local.provider,
            remote: remote.provider
        )
        result.openAIFallbackEnabled = pick(
            base: base.openAIFallbackEnabled,
            local: local.openAIFallbackEnabled,
            remote: remote.openAIFallbackEnabled
        )
        result.dictationHotkey = pick(
            base: base.dictationHotkey,
            local: local.dictationHotkey,
            remote: remote.dictationHotkey
        )
        result.openAITranscriptionURL = pick(
            base: base.openAITranscriptionURL,
            local: local.openAITranscriptionURL,
            remote: remote.openAITranscriptionURL
        )
        result.openAIModel = pick(
            base: base.openAIModel,
            local: local.openAIModel,
            remote: remote.openAIModel
        )
        result.sampleRateHz = pick(
            base: base.sampleRateHz,
            local: local.sampleRateHz,
            remote: remote.sampleRateHz
        )
        result.maxDurationSeconds = pick(
            base: base.maxDurationSeconds,
            local: local.maxDurationSeconds,
            remote: remote.maxDurationSeconds
        )
        result.hintTerms = pick(
            base: base.hintTerms,
            local: local.hintTerms,
            remote: remote.hintTerms
        )
        result.speechCleanupEnabled = pick(
            base: base.speechCleanupEnabled,
            local: local.speechCleanupEnabled,
            remote: remote.speechCleanupEnabled
        )
        result.feedbackSoundsEnabled = pick(
            base: base.feedbackSoundsEnabled,
            local: local.feedbackSoundsEnabled,
            remote: remote.feedbackSoundsEnabled
        )
        result.punctuationPreference = pick(
            base: base.punctuationPreference,
            local: local.punctuationPreference,
            remote: remote.punctuationPreference
        )
        result.skills = pick(
            base: base.skills,
            local: local.skills,
            remote: remote.skills
        )
        result.terminology = pick(
            base: base.terminology,
            local: local.terminology,
            remote: remote.terminology
        )
        result.textPolish = pick(
            base: base.textPolish,
            local: local.textPolish,
            remote: remote.textPolish
        )
        // Runtime-only resolution fields stay with remote (coordinator session).
        result.resolvedSkillPlan = remote.resolvedSkillPlan
        result.skillPromptContext = remote.skillPromptContext
        result.resolvedTerminologyEntries =
            remote.resolvedTerminologyEntries
        result.resolvedTerminologyPackIDs =
            remote.resolvedTerminologyPackIDs
        result.resolvedTerminologyRisk =
            remote.resolvedTerminologyRisk
        result.resolvedStyleCapsuleID =
            remote.resolvedStyleCapsuleID
        return result
    }

    private static func pick<T: Equatable>(
        base: T,
        local: T,
        remote: T
    ) -> T {
        local != base ? local : remote
    }
}
