//! Application configuration model. Field names and defaults are aligned
//! with the Swift `config.json` schema so an existing macOS configuration can
//! be read by this implementation.

use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::polish::TextPolishMode;
use crate::recovery::RecoveryRetentionPolicy;
use crate::skill::resolver::SkillsConfig;
use crate::style::StyleCapsuleConfig;
use crate::terminology::TerminologyEntry;

pub const DEFAULT_MAX_RECORDING_SECONDS: u32 = 120;
pub const DEFAULT_SAMPLE_RATE_HZ: u32 = 24_000;

/// Punctuation width preference for transcripts. Stored in config as the
/// Swift raw value string (`punctuationPreference`); unknown values fall back
/// to `Automatic` instead of failing the config load.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum TranscriptPunctuationPreference {
    #[default]
    Automatic,
    FullWidth,
    HalfWidth,
    Preserve,
}

impl TranscriptPunctuationPreference {
    pub fn parse(value: &str) -> Self {
        match value {
            "fullWidth" => Self::FullWidth,
            "halfWidth" => Self::HalfWidth,
            "preserve" => Self::Preserve,
            _ => Self::Automatic,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct HotkeyBindingConfig {
    /// Platform-neutral key name (e.g. "F5"); the shell maps it to the
    /// platform accelerator.
    pub key: String,
    /// Modifier names: "cmd" | "ctrl" | "alt" | "shift".
    pub modifiers: Vec<String>,
}

impl Default for HotkeyBindingConfig {
    fn default() -> Self {
        Self {
            key: "F5".into(),
            modifiers: vec![],
        }
    }
}

const SUPPORTED_HOTKEY_MODIFIERS: [&str; 4] = ["ctrl", "alt", "shift", "cmd"];
/// Reserved for VibeCompose Quick Add (terminology quick capture).
const QUICK_ADD_KEY: &str = "Space";
const QUICK_ADD_MODIFIERS: [&str; 2] = ["ctrl", "alt"];
/// Plain-`cmd` shortcuts for these keys collide with universal editing
/// shortcuts (select all / copy / quit / paste / close / cut / undo / switch).
const RESERVED_CMD_KEYS: [&str; 9] = ["A", "C", "Q", "V", "W", "X", "Z", "Tab", "Space"];

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum HotkeyValidationError {
    #[error("This key cannot be registered as a stable global shortcut.")]
    UnsupportedKey,
    #[error("Esc is reserved for cancelling the current dictation.")]
    EscapeReserved,
    #[error("Letters, numbers, punctuation, and navigation keys need Control, Option, or Command.")]
    ModifierRequired,
    #[error("This common system or editing shortcut is reserved.")]
    SystemShortcutReserved,
    #[error("This shortcut is already used by VibeCompose Quick Add.")]
    QuickAddConflict,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum ShortcutSetValidationError {
    #[error(transparent)]
    Binding(#[from] HotkeyValidationError),
    #[error("The Skill Switcher shortcut must be different from the dictation shortcut.")]
    DictationAndSkillSwitcherMatch,
    #[error("The Result Preview shortcut must be different from the dictation shortcut.")]
    DictationAndResultPreviewMatch,
    #[error("The Result Preview shortcut must be different from the Skill Switcher shortcut.")]
    SkillSwitcherAndResultPreviewMatch,
}

impl HotkeyBindingConfig {
    /// Trims the key and reduces modifiers to the supported set in canonical
    /// order, without duplicates.
    pub fn normalized(&self) -> Self {
        let lowered: Vec<String> = self
            .modifiers
            .iter()
            .map(|modifier| modifier.trim().to_lowercase())
            .collect();
        Self {
            key: self.key.trim().to_string(),
            modifiers: SUPPORTED_HOTKEY_MODIFIERS
                .iter()
                .filter(|supported| lowered.iter().any(|m| m == *supported))
                .map(|supported| supported.to_string())
                .collect(),
        }
    }

    /// Key-name and modifier-set equality, ignoring case and ordering.
    pub fn matches(&self, other: &HotkeyBindingConfig) -> bool {
        let a = self.normalized();
        let b = other.normalized();
        a.key.eq_ignore_ascii_case(&b.key) && a.modifiers == b.modifiers
    }

    /// F1..F20 may register without any modifier.
    pub fn is_function_key(&self) -> bool {
        let key = self.key.trim();
        let Some(number) = key.strip_prefix(['F', 'f']) else {
            return false;
        };
        matches!(number.parse::<u8>(), Ok(n) if (1..=20).contains(&n))
    }

    fn has_modifier(&self, name: &str) -> bool {
        self.modifiers.iter().any(|m| m == name)
    }

    /// Ported hotkey rules: Esc is reserved for cancel, the Quick Add chord is
    /// reserved, non-function keys need a substantive modifier (Control /
    /// Option / Command), and plain-`cmd` editing shortcuts stay with the OS.
    /// Returns the normalized binding.
    pub fn validated(&self) -> Result<HotkeyBindingConfig, HotkeyValidationError> {
        let normalized = self.normalized();
        if normalized.key.is_empty() {
            return Err(HotkeyValidationError::UnsupportedKey);
        }
        if normalized.key.eq_ignore_ascii_case("Escape") || normalized.key.eq_ignore_ascii_case("Esc")
        {
            return Err(HotkeyValidationError::EscapeReserved);
        }
        if normalized.matches(&Self::quick_add()) {
            return Err(HotkeyValidationError::QuickAddConflict);
        }

        if normalized.modifiers.is_empty() {
            if !normalized.is_function_key() {
                return Err(HotkeyValidationError::ModifierRequired);
            }
            return Ok(normalized);
        }

        let has_substantive_modifier = normalized.has_modifier("ctrl")
            || normalized.has_modifier("alt")
            || normalized.has_modifier("cmd");
        if !normalized.is_function_key() && !has_substantive_modifier {
            return Err(HotkeyValidationError::ModifierRequired);
        }

        let cmd_without_ctrl_or_alt = normalized.has_modifier("cmd")
            && !normalized.has_modifier("ctrl")
            && !normalized.has_modifier("alt");
        if cmd_without_ctrl_or_alt
            && RESERVED_CMD_KEYS
                .iter()
                .any(|reserved| normalized.key.eq_ignore_ascii_case(reserved))
        {
            return Err(HotkeyValidationError::SystemShortcutReserved);
        }
        Ok(normalized)
    }

    /// The reserved Quick Add chord (Ctrl+Alt+Space).
    pub fn quick_add() -> Self {
        Self {
            key: QUICK_ADD_KEY.into(),
            modifiers: QUICK_ADD_MODIFIERS.iter().map(|m| m.to_string()).collect(),
        }
    }
}

/// The full shortcut set must be individually valid and pairwise distinct.
pub fn validate_shortcut_set(
    dictation: &HotkeyBindingConfig,
    skill_switcher: Option<&HotkeyBindingConfig>,
    result_preview: Option<&HotkeyBindingConfig>,
) -> Result<(), ShortcutSetValidationError> {
    dictation.validated()?;
    if let Some(skill_switcher) = skill_switcher {
        skill_switcher.validated()?;
        if skill_switcher.matches(dictation) {
            return Err(ShortcutSetValidationError::DictationAndSkillSwitcherMatch);
        }
    }
    if let Some(result_preview) = result_preview {
        result_preview.validated()?;
        if result_preview.matches(dictation) {
            return Err(ShortcutSetValidationError::DictationAndResultPreviewMatch);
        }
        if let Some(skill_switcher) = skill_switcher {
            if result_preview.matches(skill_switcher) {
                return Err(ShortcutSetValidationError::SkillSwitcherAndResultPreviewMatch);
            }
        }
    }
    Ok(())
}

/// Platform-neutral feedback sound events. Shells map each event to a bundled
/// resource (`<resource_name>.wav`) and gate playback on
/// `transcription.feedback_sounds_enabled`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SoundFeedbackEvent {
    RecordingStarted,
    RecordingStopped,
}

impl SoundFeedbackEvent {
    pub const ALL: [SoundFeedbackEvent; 2] = [Self::RecordingStarted, Self::RecordingStopped];

    pub fn resource_name(&self) -> &'static str {
        match self {
            Self::RecordingStarted => "recording-start",
            Self::RecordingStopped => "recording-stop",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum TranscriptionProvider {
    #[default]
    ChatGptManagedAuth,
    OpenAiCompatible,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct TerminologyConfig {
    pub enabled: bool,
    pub entries: Vec<TerminologyEntry>,
}

impl Default for TerminologyConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            entries: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct TextPolishSettings {
    pub mode: TextPolishMode,
    pub chat_gpt_auth_enabled: bool,
    pub open_ai_compatible_enabled: bool,
    pub open_ai_fallback_enabled: bool,
    #[serde(rename = "chatGPTResponseModel")]
    pub chat_gpt_response_model: String,
    #[serde(rename = "openAICompatibleURL")]
    pub open_ai_compatible_url: String,
    #[serde(rename = "openAICompatibleModel")]
    pub open_ai_compatible_model: String,
    pub temperature: f64,
    pub max_output_tokens: u32,
    pub glossary_budget_characters: usize,
    pub show_cost_estimates: bool,
}

impl Default for TextPolishSettings {
    fn default() -> Self {
        Self {
            mode: TextPolishMode::AutomaticWhenKeyAvailable,
            chat_gpt_auth_enabled: true,
            open_ai_compatible_enabled: false,
            open_ai_fallback_enabled: false,
            chat_gpt_response_model: "gpt-5.5".into(),
            open_ai_compatible_url: "https://api.openai.com/v1/chat/completions".into(),
            open_ai_compatible_model: "gpt-4o".into(),
            temperature: 0.2,
            max_output_tokens: 1_200,
            glossary_budget_characters: 1_200,
            show_cost_estimates: true,
        }
    }
}

impl TextPolishSettings {
    /// Swift decode rule: if both provider flags are true, ChatGPT Auth wins;
    /// own-API primary never also uses own-API fallback.
    pub fn normalized(mut self) -> Self {
        if self.open_ai_compatible_enabled && self.chat_gpt_auth_enabled {
            self.open_ai_compatible_enabled = false;
        }
        if self.open_ai_compatible_enabled {
            self.open_ai_fallback_enabled = false;
        }
        self
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct TranscriptionConfig {
    pub provider: TranscriptionProvider,
    pub dictation_hotkey: HotkeyBindingConfig,
    pub max_duration_seconds: u32,
    pub sample_rate_hz: u32,
    pub punctuation_preference: String,
    pub speech_cleanup_enabled: bool,
    pub feedback_sounds_enabled: bool,
    pub hint_terms: Vec<String>,
    #[serde(rename = "openAIFallbackEnabled")]
    pub open_ai_fallback_enabled: bool,
    #[serde(rename = "openAIModel")]
    pub open_ai_model: String,
    #[serde(rename = "openAITranscriptionURL")]
    pub open_ai_transcription_url: String,
    pub skills: SkillsConfig,
    pub terminology: TerminologyConfig,
    pub text_polish: TextPolishSettings,
}

impl Default for TranscriptionConfig {
    fn default() -> Self {
        Self {
            provider: TranscriptionProvider::ChatGptManagedAuth,
            dictation_hotkey: HotkeyBindingConfig::default(),
            max_duration_seconds: DEFAULT_MAX_RECORDING_SECONDS,
            sample_rate_hz: DEFAULT_SAMPLE_RATE_HZ,
            punctuation_preference: "automatic".into(),
            speech_cleanup_enabled: true,
            feedback_sounds_enabled: true,
            hint_terms: Vec::new(),
            open_ai_fallback_enabled: false,
            open_ai_model: "gpt-4o-mini-transcribe".into(),
            open_ai_transcription_url: "https://api.openai.com/v1/audio/transcriptions".into(),
            skills: SkillsConfig::default(),
            terminology: TerminologyConfig::default(),
            text_polish: TextPolishSettings::default(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct InjectionConfig {
    pub preserve_clipboard: bool,
    pub restore_delay_milliseconds: u64,
    pub skip_result_preview_when_safe: bool,
}

impl Default for InjectionConfig {
    fn default() -> Self {
        Self {
            preserve_clipboard: false,
            restore_delay_milliseconds: 350,
            skip_result_preview_when_safe: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PrivacyConfig {
    pub history_enabled: bool,
    pub history_record_limit: usize,
    pub history_retention_days: u32,
    pub store_raw_transcripts: bool,
    /// Keep the WAV and any surviving text of a failed dictation for retry.
    pub failed_audio_recovery_enabled: bool,
    pub failed_audio_retention_hours: u32,
    pub failed_audio_record_limit: usize,
    pub exclude_sensitive_apps: bool,
    pub additional_sensitive_app_ids: Vec<String>,
    pub diagnostics_enabled: bool,
}

impl Default for PrivacyConfig {
    fn default() -> Self {
        Self {
            history_enabled: true,
            history_record_limit: 500,
            history_retention_days: 30,
            store_raw_transcripts: false,
            failed_audio_recovery_enabled: true,
            failed_audio_retention_hours: 24,
            failed_audio_record_limit: 10,
            exclude_sensitive_apps: true,
            additional_sensitive_app_ids: Vec::new(),
            diagnostics_enabled: true,
        }
    }
}

impl PrivacyConfig {
    /// Swift decode bounds for hand-edited configs: retention 1..=168 hours,
    /// record limit 1..=100.
    pub fn normalized(mut self) -> Self {
        self.failed_audio_retention_hours = self.failed_audio_retention_hours.clamp(1, 168);
        self.failed_audio_record_limit = self.failed_audio_record_limit.clamp(1, 100);
        self
    }

    /// Retention policy for the failure recovery store; a disabled toggle
    /// keeps zero records, which clears the store on the next prune.
    pub fn recovery_retention_policy(&self, now_epoch_seconds: i64) -> RecoveryRetentionPolicy {
        RecoveryRetentionPolicy::new(
            if self.failed_audio_recovery_enabled {
                self.failed_audio_record_limit
            } else {
                0
            },
            Some(self.failed_audio_retention_hours),
            now_epoch_seconds,
        )
    }
}

/// Built-in sensitive application identifiers excluded from transcript and
/// recovery persistence (password managers, keychain UIs).
pub const BUILT_IN_SENSITIVE_APP_IDS: &[&str] = &[
    "com.apple.keychainaccess",
    "com.apple.passwords",
    "com.1password.1password",
    "com.agilebits.onepassword7",
    "com.bitwarden.desktop",
    "com.lastpass.lastpassmacdesktop",
    "org.keepassxc.keepassxc",
    "com.dashlane.dashlanephonefinal",
    // Windows executable names, matched case-insensitively without path.
    "1password.exe",
    "bitwarden.exe",
    "keepassxc.exe",
    "keepass.exe",
];

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AppConfig {
    pub app_language: Option<String>,
    /// Optional global shortcut that opens the Skill switcher. `None` until
    /// the user enables it in Settings.
    pub skill_switcher_hotkey: Option<HotkeyBindingConfig>,
    /// Optional global shortcut that reopens the last dictation Preview and
    /// allows switching Skills to regenerate results for the same transcript.
    /// `None` until the user enables it in Settings.
    pub result_preview_hotkey: Option<HotkeyBindingConfig>,
    pub transcription: TranscriptionConfig,
    pub injection: InjectionConfig,
    pub privacy: PrivacyConfig,
    pub style_capsules: StyleCapsuleConfig,
}

impl AppConfig {
    pub fn load(path: &Path) -> std::io::Result<Self> {
        let data = std::fs::read(path)?;
        let config: AppConfig = serde_json::from_slice(&data)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
        Ok(config.normalized())
    }

    /// Swift decode rules for hand-edited configs: an invalid dictation
    /// hotkey falls back to the default, invalid optional hotkeys are
    /// dropped, provider flags stay mutually exclusive, style assignments
    /// are deduplicated, and privacy bounds are clamped.
    pub fn normalized(mut self) -> Self {
        self.transcription.text_polish = self.transcription.text_polish.normalized();
        self.transcription.dictation_hotkey = self
            .transcription
            .dictation_hotkey
            .validated()
            .unwrap_or_default();
        self.skill_switcher_hotkey = self
            .skill_switcher_hotkey
            .and_then(|binding| binding.validated().ok());
        self.result_preview_hotkey = self
            .result_preview_hotkey
            .and_then(|binding| binding.validated().ok());
        self.style_capsules = self.style_capsules.normalized();
        self.privacy = self.privacy.normalized();
        self
    }

    pub fn save(&self, path: &Path) -> std::io::Result<()> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let json = serde_json::to_vec_pretty(self)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
        write_private(path, &json)
    }

    pub fn is_sensitive_app(&self, application_id: &str) -> bool {
        if !self.privacy.exclude_sensitive_apps {
            return false;
        }
        let lowered = application_id.to_lowercase();
        BUILT_IN_SENSITIVE_APP_IDS
            .iter()
            .any(|id| *id == lowered)
            || self
                .privacy
                .additional_sensitive_app_ids
                .iter()
                .any(|id| id.to_lowercase() == lowered)
    }
}

/// Writes a file with owner-only permissions where the platform supports it.
pub fn write_private(path: &Path, data: &[u8]) -> std::io::Result<()> {
    std::fs::write(path, data)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    }
    Ok(())
}

/// Creates a directory (if needed) with owner-only permissions where the
/// platform supports it.
pub fn create_private_dir(path: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(path)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700))?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_match_product_contract() {
        let config = AppConfig::default();
        assert_eq!(config.transcription.dictation_hotkey.key, "F5");
        assert_eq!(config.transcription.max_duration_seconds, 120);
        assert_eq!(config.transcription.sample_rate_hz, 24_000);
        assert!(!config.privacy.store_raw_transcripts);
        assert_eq!(config.privacy.history_record_limit, 500);
        assert_eq!(config.skill_switcher_hotkey, None);
        assert_eq!(config.result_preview_hotkey, None);
        assert!(config.privacy.failed_audio_recovery_enabled);
        assert_eq!(config.privacy.failed_audio_retention_hours, 24);
        assert_eq!(config.privacy.failed_audio_record_limit, 10);
        assert!(config.style_capsules.enabled);
        assert_eq!(config.style_capsules.default_capsule_id, None);
    }

    #[test]
    fn legacy_config_without_new_keys_still_loads() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("config.json");
        std::fs::write(
            &path,
            r#"{"transcription":{"dictationHotkey":{"key":"F5","modifiers":[]}},"privacy":{"historyEnabled":true}}"#,
        )
        .unwrap();
        let config = AppConfig::load(&path).unwrap();
        assert_eq!(config.skill_switcher_hotkey, None);
        assert_eq!(config.result_preview_hotkey, None);
        assert!(config.privacy.failed_audio_recovery_enabled);
        assert!(config.style_capsules.enabled);
    }

    #[test]
    fn load_drops_invalid_optional_hotkeys_and_repairs_dictation_hotkey() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("config.json");
        std::fs::write(
            &path,
            r#"{
                "transcription": {"dictationHotkey": {"key": "Escape", "modifiers": []}},
                "skillSwitcherHotkey": {"key": "S", "modifiers": ["ctrl", "alt"]},
                "resultPreviewHotkey": {"key": "P", "modifiers": ["shift"]}
            }"#,
        )
        .unwrap();
        let config = AppConfig::load(&path).unwrap();
        assert_eq!(config.transcription.dictation_hotkey, HotkeyBindingConfig::default());
        assert_eq!(
            config.skill_switcher_hotkey,
            Some(HotkeyBindingConfig {
                key: "S".into(),
                modifiers: vec!["ctrl".into(), "alt".into()],
            })
        );
        assert_eq!(config.result_preview_hotkey, None);
    }

    #[test]
    fn load_clamps_failed_audio_bounds() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("config.json");
        std::fs::write(
            &path,
            r#"{"privacy":{"failedAudioRetentionHours":9000,"failedAudioRecordLimit":0}}"#,
        )
        .unwrap();
        let config = AppConfig::load(&path).unwrap();
        assert_eq!(config.privacy.failed_audio_retention_hours, 168);
        assert_eq!(config.privacy.failed_audio_record_limit, 1);
    }

    #[test]
    fn recovery_retention_policy_reflects_privacy_settings() {
        let mut privacy = PrivacyConfig::default();
        let policy = privacy.recovery_retention_policy(1_770_000_000);
        assert_eq!(policy.max_records, 10);
        assert_eq!(
            policy.cutoff_epoch_seconds(),
            Some(1_770_000_000 - 24 * 3_600)
        );

        privacy.failed_audio_recovery_enabled = false;
        assert_eq!(privacy.recovery_retention_policy(0).max_records, 0);
    }

    #[test]
    fn hotkey_validation_ports_swift_rules() {
        // Function keys register without modifiers.
        assert!(HotkeyBindingConfig::default().validated().is_ok());
        // Esc is reserved for cancel.
        assert_eq!(
            HotkeyBindingConfig {
                key: "Escape".into(),
                modifiers: vec![]
            }
            .validated(),
            Err(HotkeyValidationError::EscapeReserved)
        );
        // Letters need a substantive modifier; shift alone is not enough.
        assert_eq!(
            HotkeyBindingConfig {
                key: "K".into(),
                modifiers: vec![]
            }
            .validated(),
            Err(HotkeyValidationError::ModifierRequired)
        );
        assert_eq!(
            HotkeyBindingConfig {
                key: "K".into(),
                modifiers: vec!["shift".into()]
            }
            .validated(),
            Err(HotkeyValidationError::ModifierRequired)
        );
        // Plain-cmd editing shortcuts stay with the OS.
        assert_eq!(
            HotkeyBindingConfig {
                key: "C".into(),
                modifiers: vec!["cmd".into()]
            }
            .validated(),
            Err(HotkeyValidationError::SystemShortcutReserved)
        );
        assert!(HotkeyBindingConfig {
            key: "C".into(),
            modifiers: vec!["cmd".into(), "alt".into()]
        }
        .validated()
        .is_ok());
        // The Quick Add chord is reserved regardless of modifier order/case.
        assert_eq!(
            HotkeyBindingConfig {
                key: "space".into(),
                modifiers: vec!["ALT".into(), "ctrl".into()]
            }
            .validated(),
            Err(HotkeyValidationError::QuickAddConflict)
        );
        // Normalization dedups and orders modifiers canonically.
        let normalized = HotkeyBindingConfig {
            key: " P ".into(),
            modifiers: vec!["CMD".into(), "ctrl".into(), "cmd".into(), "meta".into()],
        }
        .validated()
        .unwrap();
        assert_eq!(normalized.key, "P");
        assert_eq!(normalized.modifiers, vec!["ctrl".to_string(), "cmd".to_string()]);
    }

    #[test]
    fn shortcut_set_requires_pairwise_distinct_bindings() {
        let dictation = HotkeyBindingConfig::default();
        let switcher = HotkeyBindingConfig {
            key: "S".into(),
            modifiers: vec!["ctrl".into(), "alt".into()],
        };
        let preview = HotkeyBindingConfig {
            key: "P".into(),
            modifiers: vec!["ctrl".into(), "alt".into()],
        };
        assert!(validate_shortcut_set(&dictation, Some(&switcher), Some(&preview)).is_ok());
        assert_eq!(
            validate_shortcut_set(&dictation, Some(&dictation), None),
            Err(ShortcutSetValidationError::DictationAndSkillSwitcherMatch)
        );
        assert_eq!(
            validate_shortcut_set(&dictation, Some(&switcher), Some(&dictation)),
            Err(ShortcutSetValidationError::DictationAndResultPreviewMatch)
        );
        assert_eq!(
            validate_shortcut_set(&dictation, Some(&switcher), Some(&switcher)),
            Err(ShortcutSetValidationError::SkillSwitcherAndResultPreviewMatch)
        );
        assert_eq!(
            validate_shortcut_set(
                &HotkeyBindingConfig {
                    key: "Escape".into(),
                    modifiers: vec![]
                },
                None,
                None
            ),
            Err(ShortcutSetValidationError::Binding(
                HotkeyValidationError::EscapeReserved
            ))
        );
    }

    #[test]
    fn sound_feedback_events_expose_resource_names() {
        assert_eq!(
            SoundFeedbackEvent::RecordingStarted.resource_name(),
            "recording-start"
        );
        assert_eq!(
            SoundFeedbackEvent::RecordingStopped.resource_name(),
            "recording-stop"
        );
        assert_eq!(SoundFeedbackEvent::ALL.len(), 2);
    }

    #[test]
    fn polish_provider_flags_are_mutually_exclusive() {
        let settings = TextPolishSettings {
            chat_gpt_auth_enabled: true,
            open_ai_compatible_enabled: true,
            open_ai_fallback_enabled: true,
            ..Default::default()
        }
        .normalized();
        assert!(settings.chat_gpt_auth_enabled);
        assert!(!settings.open_ai_compatible_enabled);
    }

    #[test]
    fn sensitive_app_matching_is_case_insensitive() {
        let config = AppConfig::default();
        assert!(config.is_sensitive_app("com.1password.1password"));
        assert!(config.is_sensitive_app("BitWarden.exe"));
        assert!(!config.is_sensitive_app("com.apple.textedit"));
        let mut relaxed = config.clone();
        relaxed.privacy.exclude_sensitive_apps = false;
        assert!(!relaxed.is_sensitive_app("com.1password.1password"));
    }

    #[test]
    fn round_trips_json() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("config.json");
        let mut config = AppConfig::default();
        config.transcription.skills.default_skill_id = "app.vibecompose.skill.direct".into();
        config.skill_switcher_hotkey = Some(HotkeyBindingConfig {
            key: "S".into(),
            modifiers: vec!["ctrl".into(), "alt".into()],
        });
        config.style_capsules.default_capsule_id = Some("builtin.work-formal".into());
        config
            .style_capsules
            .set_capsule_id(Some("builtin.team-chat"), "app.vibecompose.skill.email");
        config.save(&path).unwrap();
        let loaded = AppConfig::load(&path).unwrap();
        assert_eq!(loaded, config);
    }
}
