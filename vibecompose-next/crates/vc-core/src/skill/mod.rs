//! Skill runtime: declarative packages, registry, resolution, prompt
//! compilation, and output validation. Ported from Swift `SkillRuntime.swift`
//! and `AgentSkillRuntime.swift`.

pub mod package;
pub mod prompt;
pub mod registry;
pub mod resolver;
pub mod validator;

use serde::{Deserialize, Serialize};

use crate::terminology::TerminologyEntry;

pub const DIRECT_SKILL_ID: &str = "app.vibecompose.skill.direct";

/// Context capabilities a Skill may request. Community Skills remain
/// declarative data: no capability can execute code or reach the network.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SkillCapability {
    Voice,
    Selection,
    FocusedParagraph,
    ConversationWindow,
    Clipboard,
    StyleCapsule,
    ExternalAction,
}

impl SkillCapability {
    pub fn code(&self) -> &'static str {
        match self {
            Self::Voice => "voice",
            Self::Selection => "selection",
            Self::FocusedParagraph => "focusedParagraph",
            Self::ConversationWindow => "conversationWindow",
            Self::Clipboard => "clipboard",
            Self::StyleCapsule => "styleCapsule",
            Self::ExternalAction => "externalAction",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "voice" => Some(Self::Voice),
            "selection" => Some(Self::Selection),
            "focusedParagraph" | "focused-paragraph" => Some(Self::FocusedParagraph),
            "conversationWindow" | "conversation-window" => Some(Self::ConversationWindow),
            "clipboard" => Some(Self::Clipboard),
            "styleCapsule" | "style-capsule" => Some(Self::StyleCapsule),
            "externalAction" | "external-action" => Some(Self::ExternalAction),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum SkillOutputFormat {
    #[default]
    PlainText,
    Markdown,
    Code,
    Json,
    Template,
    ActionPreview,
}

impl SkillOutputFormat {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "plainText" | "plain-text" => Some(Self::PlainText),
            "markdown" => Some(Self::Markdown),
            "code" => Some(Self::Code),
            "json" => Some(Self::Json),
            "template" => Some(Self::Template),
            "actionPreview" | "action-preview" => Some(Self::ActionPreview),
            _ => None,
        }
    }

    pub fn code(&self) -> &'static str {
        match self {
            Self::PlainText => "plainText",
            Self::Markdown => "markdown",
            Self::Code => "code",
            Self::Json => "json",
            Self::Template => "template",
            Self::ActionPreview => "actionPreview",
        }
    }
}

/// How the final text may leave the app. Enforced locally; generated text can
/// never change it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum SkillDeliveryPolicy {
    #[default]
    AutomaticPasteWhenVerified,
    PreviewThenPaste,
    CopyOnly,
}

impl SkillDeliveryPolicy {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "automaticPasteWhenVerified" | "automatic-paste-when-verified" => {
                Some(Self::AutomaticPasteWhenVerified)
            }
            "previewThenPaste" | "preview-then-paste" => Some(Self::PreviewThenPaste),
            "copyOnly" | "copy-only" => Some(Self::CopyOnly),
            _ => None,
        }
    }

    pub fn code(&self) -> &'static str {
        match self {
            Self::AutomaticPasteWhenVerified => "automaticPasteWhenVerified",
            Self::PreviewThenPaste => "previewThenPaste",
            Self::CopyOnly => "copyOnly",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum SkillRiskLevel {
    Low,
    #[default]
    Medium,
    High,
}

impl SkillRiskLevel {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "low" => Some(Self::Low),
            "medium" => Some(Self::Medium),
            "high" => Some(Self::High),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct SkillOutputContract {
    pub format: SkillOutputFormat,
    pub delivery: SkillDeliveryPolicy,
    pub risk: SkillRiskLevel,
}

impl Default for SkillOutputContract {
    fn default() -> Self {
        Self {
            format: SkillOutputFormat::PlainText,
            delivery: SkillDeliveryPolicy::PreviewThenPaste,
            risk: SkillRiskLevel::Medium,
        }
    }
}

pub const MAX_VALIDATOR_CHARACTERS: usize = 100_000;
pub const DEFAULT_VALIDATOR_CHARACTERS: usize = 12_000;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SkillValidatorPolicy {
    pub require_non_empty: bool,
    pub maximum_characters: usize,
    pub preserve_technical_literals: bool,
    pub require_closed_markdown_fences: bool,
    pub required_section_alternatives: Vec<Vec<String>>,
    pub forbidden_phrases: Vec<String>,
}

impl Default for SkillValidatorPolicy {
    fn default() -> Self {
        Self {
            require_non_empty: true,
            maximum_characters: DEFAULT_VALIDATOR_CHARACTERS,
            preserve_technical_literals: true,
            require_closed_markdown_fences: false,
            required_section_alternatives: Vec::new(),
            forbidden_phrases: Vec::new(),
        }
    }
}

impl SkillValidatorPolicy {
    /// Applies the same bounds Swift enforces in its initializer.
    pub fn normalized(mut self) -> Self {
        self.maximum_characters = self.maximum_characters.clamp(1, MAX_VALIDATOR_CHARACTERS);
        self.required_section_alternatives.truncate(20);
        for alternatives in &mut self.required_section_alternatives {
            alternatives.truncate(20);
        }
        self.forbidden_phrases.truncate(100);
        self
    }
}

/// Legacy dictation mode retained for decision heuristics and telemetry.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum DictationMode {
    #[default]
    Direct,
    Reply,
    Email,
    CodePrompt,
    Translate,
}

impl DictationMode {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "direct" => Some(Self::Direct),
            "reply" => Some(Self::Reply),
            "email" => Some(Self::Email),
            "codePrompt" | "code-prompt" => Some(Self::CodePrompt),
            "translate" => Some(Self::Translate),
            _ => None,
        }
    }
}

/// A stable, versioned Skill declaration.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SkillDefinition {
    #[serde(default = "default_schema_version")]
    pub schema_version: u32,
    pub id: String,
    pub version: String,
    pub name: String,
    #[serde(default = "default_author")]
    pub author: String,
    #[serde(default = "default_minimum_app_version")]
    pub minimum_app_version: String,
    #[serde(default = "default_required_capabilities")]
    pub required_capabilities: Vec<SkillCapability>,
    #[serde(default)]
    pub optional_capabilities: Vec<SkillCapability>,
    #[serde(default)]
    pub terminology_entries: Vec<TerminologyEntry>,
    pub prompt_instruction: String,
    pub output: SkillOutputContract,
    #[serde(default)]
    pub validators: SkillValidatorPolicy,
    #[serde(default)]
    pub legacy_mode: Option<DictationMode>,
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default)]
    pub use_case: Option<String>,
}

fn default_schema_version() -> u32 {
    1
}
fn default_author() -> String {
    "VibeCompose".to_string()
}
fn default_minimum_app_version() -> String {
    "0.1.0".to_string()
}
fn default_required_capabilities() -> Vec<SkillCapability> {
    vec![SkillCapability::Voice]
}

impl SkillDefinition {
    /// Normalizes capabilities/instruction the way the Swift initializer does.
    pub fn normalized(mut self) -> Self {
        self.optional_capabilities
            .retain(|c| !self.required_capabilities.contains(c));
        dedup_preserving_order(&mut self.required_capabilities);
        dedup_preserving_order(&mut self.optional_capabilities);
        self.prompt_instruction = self.prompt_instruction.trim().to_string();
        self.validators = self.validators.clone().normalized();
        self
    }

    pub fn all_capabilities(&self) -> Vec<SkillCapability> {
        let mut all = self.required_capabilities.clone();
        all.extend(self.optional_capabilities.iter().copied());
        all
    }

    /// A required selection is the document being transformed; the spoken
    /// transcript is the user's instruction.
    pub fn uses_selection_as_primary_input(&self) -> bool {
        self.required_capabilities.contains(&SkillCapability::Selection)
    }

    /// Selection-first Skills validate the selected source instead of the
    /// spoken instruction, so instruction literals are not treated as output
    /// content.
    pub fn protects_voice_technical_literals(&self) -> bool {
        !self.uses_selection_as_primary_input()
    }

    pub fn validation_source_text<'a>(
        &self,
        transcript: &'a str,
        selection: Option<&'a str>,
    ) -> &'a str {
        if self.uses_selection_as_primary_input() {
            if let Some(selection) = selection {
                if !selection.trim().is_empty() {
                    return selection;
                }
            }
        }
        transcript
    }

    pub fn is_valid_identifier(value: &str) -> bool {
        if value.is_empty() || value.len() > 160 {
            return false;
        }
        static PATTERN: std::sync::LazyLock<fancy_regex::Regex> = std::sync::LazyLock::new(|| {
            fancy_regex::Regex::new(r"^[a-z0-9]+(?:[.-][a-z0-9-]+)*$").unwrap()
        });
        PATTERN.is_match(value).unwrap_or(false)
    }

    pub fn is_valid_version(value: &str) -> bool {
        if value.is_empty() || value.len() > 64 {
            return false;
        }
        static PATTERN: std::sync::LazyLock<fancy_regex::Regex> = std::sync::LazyLock::new(|| {
            fancy_regex::Regex::new(r"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$").unwrap()
        });
        if !PATTERN.is_match(value).unwrap_or(false) {
            return false;
        }
        let core = value.split('-').next().unwrap_or_default();
        let components: Vec<&str> = core.split('.').collect();
        components.len() == 3 && components.iter().all(|c| c.len() <= 20)
    }
}

fn dedup_preserving_order(values: &mut Vec<SkillCapability>) {
    let mut seen = Vec::new();
    values.retain(|v| {
        if seen.contains(v) {
            false
        } else {
            seen.push(*v);
            true
        }
    });
}

/// Where the resolved Skill came from; frozen at recording start.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SkillResolutionSource {
    Manual,
    NextRun,
    ApplicationRule,
    GlobalDefault,
    DirectFallback,
}

/// The frozen execution plan for one dictation session.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResolvedSkillExecutionPlan {
    pub skill: SkillDefinition,
    pub source: SkillResolutionSource,
    #[serde(default)]
    pub matched_application_rule_id: Option<uuid::Uuid>,
}

impl ResolvedSkillExecutionPlan {
    pub fn legacy_mode(&self) -> DictationMode {
        self.skill.legacy_mode.unwrap_or(DictationMode::Direct)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identifier_and_version_validation() {
        assert!(SkillDefinition::is_valid_identifier("app.vibecompose.skill.direct"));
        assert!(SkillDefinition::is_valid_identifier("builtin.code-prompt"));
        assert!(!SkillDefinition::is_valid_identifier("Bad_Upper"));
        assert!(!SkillDefinition::is_valid_identifier(""));
        assert!(SkillDefinition::is_valid_version("1.2.0"));
        assert!(SkillDefinition::is_valid_version("1.2.0-alpha.1"));
        assert!(!SkillDefinition::is_valid_version("1.2"));
        assert!(!SkillDefinition::is_valid_version("v1.2.3"));
    }

    #[test]
    fn selection_primary_semantics() {
        let mut skill = SkillDefinition {
            schema_version: 1,
            id: "test.rewrite".into(),
            version: "1.0.0".into(),
            name: "Rewrite".into(),
            author: "t".into(),
            minimum_app_version: "0.1.0".into(),
            required_capabilities: vec![SkillCapability::Voice, SkillCapability::Selection],
            optional_capabilities: vec![SkillCapability::Selection],
            terminology_entries: vec![],
            prompt_instruction: " do it ".into(),
            output: SkillOutputContract::default(),
            validators: SkillValidatorPolicy::default(),
            legacy_mode: None,
            summary: None,
            use_case: None,
        };
        skill = skill.normalized();
        assert!(skill.uses_selection_as_primary_input());
        assert!(!skill.protects_voice_technical_literals());
        assert_eq!(skill.optional_capabilities.len(), 0);
        assert_eq!(skill.prompt_instruction, "do it");
        assert_eq!(skill.validation_source_text("说的话", Some("选中文本")), "选中文本");
        assert_eq!(skill.validation_source_text("说的话", Some("  ")), "说的话");
    }
}
