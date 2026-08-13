//! Style Capsules (Writing Styles): small user-approved tone/presentation
//! descriptions injected into the polish prompt under `[STYLE_CAPSULE]` when
//! the active Skill holds the `styleCapsule` capability. Capsule text is
//! untrusted data; the prompt compiler truncates it to
//! `MAX_STYLE_CAPSULE_CHARS`. Ported from Swift `PersonalizationRuntime`.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::config::{create_private_dir, write_private};
use crate::skill::{SkillCapability, SkillDefinition};

pub const MAX_STYLE_NAME_CHARS: usize = 80;
/// Matches `prompt::MAX_STYLE_CAPSULE_CHARS`: summaries are stored at the same
/// bound the prompt compiler enforces.
pub const MAX_STYLE_SUMMARY_CHARS: usize = 4_000;
pub const MAX_STYLE_EXAMPLE_CHARS: usize = 1_000;
pub const MAX_STYLE_EXAMPLES: usize = 10;
pub const MAX_CUSTOM_STYLE_CAPSULES: usize = 100;
pub const MAX_STYLE_FILE_BYTES: u64 = 64 * 1_024;
pub const MAX_STYLE_ASSIGNMENTS: usize = 100;

#[derive(Debug, thiserror::Error)]
pub enum StyleCapsuleError {
    #[error("The Writing Style identifier is invalid.")]
    InvalidIdentifier,
    #[error("Enter a name and a readable style summary.")]
    InvalidContent,
    #[error("Built-in Writing Styles cannot be changed or deleted.")]
    BuiltInReadOnly,
    #[error("VibeCompose blocked a symbolic link in Writing Style storage.")]
    SymbolicLink,
    #[error("The Writing Style is too large.")]
    Oversized,
    #[error("The Writing Style no longer exists.")]
    Missing,
    #[error("The Writing Style file could not be parsed: {0}")]
    Parse(String),
    #[error(transparent)]
    Io(#[from] std::io::Error),
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct StyleCapsule {
    pub id: String,
    pub name: String,
    pub summary: String,
    pub examples: Vec<String>,
    /// RFC 3339 UTC timestamps.
    pub created_at: String,
    pub updated_at: String,
    pub is_built_in: bool,
}

impl StyleCapsule {
    /// Normalizing constructor: trims and bounds name/summary/examples the
    /// way the Swift initializer does. Deserialized capsules keep raw values;
    /// the prompt compiler enforces the final budget.
    pub fn new(
        id: impl Into<String>,
        name: &str,
        summary: &str,
        examples: &[String],
        created_at: impl Into<String>,
        updated_at: impl Into<String>,
        is_built_in: bool,
    ) -> Self {
        Self {
            id: id.into(),
            name: clipped(name.trim(), MAX_STYLE_NAME_CHARS),
            summary: clipped(summary.trim(), MAX_STYLE_SUMMARY_CHARS),
            examples: examples
                .iter()
                .map(|example| clipped(example.trim(), MAX_STYLE_EXAMPLE_CHARS))
                .filter(|example| !example.is_empty())
                .take(MAX_STYLE_EXAMPLES)
                .collect(),
            created_at: created_at.into(),
            updated_at: updated_at.into(),
            is_built_in,
        }
    }

    /// The text handed to `SkillPromptContext.style_capsule`.
    pub fn prompt_text(&self) -> String {
        let mut sections = vec![self.summary.clone()];
        if !self.examples.is_empty() {
            sections.push(format!(
                "User-approved examples:\n{}",
                self.examples
                    .iter()
                    .map(|example| format!("- {example}"))
                    .collect::<Vec<_>>()
                    .join("\n")
            ));
        }
        sections.join("\n")
    }

    /// `builtin.` / `user.` namespace plus a lowercase slug; also the only
    /// shape the file store will turn into a path.
    pub fn is_valid_identifier(value: &str) -> bool {
        static PATTERN: std::sync::LazyLock<fancy_regex::Regex> =
            std::sync::LazyLock::new(|| {
                fancy_regex::Regex::new(r"^(?:builtin|user)\.[a-z0-9][a-z0-9.-]{2,100}$").unwrap()
            });
        PATTERN.is_match(value).unwrap_or(false)
    }
}

fn clipped(value: &str, maximum_characters: usize) -> String {
    value.chars().take(maximum_characters).collect()
}

// ---------------------------------------------------------------------------
// Built-in registry
// ---------------------------------------------------------------------------

pub const WORK_FORMAL_STYLE_ID: &str = "builtin.work-formal";
pub const TEAM_CHAT_STYLE_ID: &str = "builtin.team-chat";
pub const TECHNICAL_WRITING_STYLE_ID: &str = "builtin.technical-writing";
pub const ENGLISH_BUSINESS_STYLE_ID: &str = "builtin.english-business";
pub const PERSONAL_CASUAL_STYLE_ID: &str = "builtin.personal-casual";
pub const ACADEMIC_WRITING_STYLE_ID: &str = "builtin.academic-writing";
pub const EXECUTIVE_SUMMARY_STYLE_ID: &str = "builtin.executive-summary";
pub const CODE_DOCUMENTATION_STYLE_ID: &str = "builtin.code-documentation";

const BUILT_IN_STYLE_TIMESTAMP: &str = "2026-07-14T00:00:00Z";

fn built_in(id: &str, name: &str, summary: &str, example: &str) -> StyleCapsule {
    StyleCapsule::new(
        id,
        name,
        summary,
        &[example.to_string()],
        BUILT_IN_STYLE_TIMESTAMP,
        BUILT_IN_STYLE_TIMESTAMP,
        true,
    )
}

pub fn builtin_style_capsules() -> Vec<StyleCapsule> {
    vec![
        built_in(
            WORK_FORMAL_STYLE_ID,
            "Work Formal",
            "Use a professional, calm tone. Prefer complete sentences, explicit requests, restrained politeness, and concise paragraphs. Avoid hype, slang, emojis, and unnecessary preambles.",
            "Could you please review the attached proposal by Friday and share any concerns before we circulate it more widely?",
        ),
        built_in(
            TEAM_CHAT_STYLE_ID,
            "Team Chat",
            "Use a concise, direct, collaborative team-chat tone. Lead with the decision or request, keep paragraphs short, and use bullets only when they improve scanability. Avoid formal greetings and signatures.",
            "Ship plan for Thursday: I will land the API fix today. Need design review by 3pm if possible.",
        ),
        built_in(
            TECHNICAL_WRITING_STYLE_ID,
            "Technical Writing",
            "Use precise technical language, explicit constraints, compact headings, and implementation-oriented bullets. Preserve identifiers and avoid marketing language, vague adjectives, and unsupported claims.",
            "Retry only on HTTP 429/503 with exponential backoff (base 250ms, cap 4s, max 5 attempts). Do not retry non-idempotent POST.",
        ),
        built_in(
            ENGLISH_BUSINESS_STYLE_ID,
            "English Business",
            "Write clear international business English with short paragraphs, neutral confidence, explicit next steps, and moderate politeness. Avoid idioms, exaggerated claims, and culture-specific slang.",
            "Thank you for the update. Next step: please confirm the delivery date so we can schedule the customer review.",
        ),
        built_in(
            PERSONAL_CASUAL_STYLE_ID,
            "Personal Casual",
            "Use a warm, natural, conversational tone with varied sentence length. Keep the message compact, avoid corporate phrasing, and do not add emojis or sign-offs unless requested.",
            "Hey — running a bit late, should be there in ten. Grab a table if you get there first?",
        ),
        built_in(
            ACADEMIC_WRITING_STYLE_ID,
            "Academic Writing",
            "Use formal academic prose: third person where appropriate, precise hedged claims (\"suggests\", \"indicates\", \"demonstrates\"), passive voice when the actor is less important than the action, and explicit logical connectors. Avoid contractions, colloquialisms, and unsupported assertions.",
            "The results indicate that response latency increases significantly under high concurrency, suggesting that the synchronisation strategy warrants further investigation.",
        ),
        built_in(
            EXECUTIVE_SUMMARY_STYLE_ID,
            "Executive Summary",
            "Lead with the bottom line (BLUF). Use short declarative sentences, plain language, and explicit numbers. Keep each paragraph to a single idea. End with a clear recommended action or decision needed. Avoid jargon, qualifications, and background that executives do not need to act.",
            "Deployment is blocked by a single authentication bug. Fix ships Friday; no user impact expected. Decision needed: approve the Friday release window.",
        ),
        built_in(
            CODE_DOCUMENTATION_STYLE_ID,
            "Code Documentation",
            "Write in third person, present tense, imperative voice for function descriptions (\"Returns\", \"Throws\", \"Inserts\"). Be precise about types, nullability, side effects, and error conditions. Follow JSDoc / docstring conventions: one summary sentence, then @param / @returns / @throws as needed. Avoid vague adjectives and marketing language.",
            "Returns the normalised transcript with terminology corrections applied. Throws `TerminologyError.conflictingEntries` if two packs define the same canonical form with different casings.",
        ),
    ]
}

/// Built-ins first, then custom capsules (anything claiming `isBuiltIn` in a
/// custom file is excluded).
pub fn all_style_capsules(custom: &[StyleCapsule]) -> Vec<StyleCapsule> {
    let mut all = builtin_style_capsules();
    all.extend(custom.iter().filter(|c| !c.is_built_in).cloned());
    all
}

// ---------------------------------------------------------------------------
// Configuration (persisted inside config.json)
// ---------------------------------------------------------------------------

/// One Skill-specific override; Swift encodes the keys as `skillID` /
/// `capsuleID`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct StyleCapsuleAssignment {
    #[serde(rename = "skillID")]
    pub skill_id: String,
    #[serde(rename = "capsuleID")]
    pub capsule_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct StyleCapsuleConfig {
    pub enabled: bool,
    #[serde(rename = "defaultCapsuleID")]
    pub default_capsule_id: Option<String>,
    pub skill_assignments: Vec<StyleCapsuleAssignment>,
}

impl Default for StyleCapsuleConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            default_capsule_id: None,
            skill_assignments: Vec::new(),
        }
    }
}

impl StyleCapsuleConfig {
    /// Swift decode rule: drop invalid capsule/skill identifiers, dedup
    /// assignments per Skill (first wins), cap the assignment count.
    pub fn normalized(mut self) -> Self {
        self.default_capsule_id =
            normalized_capsule_id(self.default_capsule_id.as_deref());
        self.skill_assignments = normalized_assignments(std::mem::take(&mut self.skill_assignments));
        self
    }

    /// The capsule to use for a Skill: explicit assignment, else the default.
    pub fn capsule_id_for(&self, skill_id: &str) -> Option<&str> {
        self.assigned_capsule_id(skill_id)
            .or(self.default_capsule_id.as_deref())
    }

    /// Only the explicit per-Skill override, if any.
    pub fn assigned_capsule_id(&self, skill_id: &str) -> Option<&str> {
        self.skill_assignments
            .iter()
            .find(|assignment| assignment.skill_id == skill_id)
            .map(|assignment| assignment.capsule_id.as_str())
    }

    /// Sets or clears (`None`) the override for a Skill.
    pub fn set_capsule_id(&mut self, capsule_id: Option<&str>, skill_id: &str) {
        self.skill_assignments
            .retain(|assignment| assignment.skill_id != skill_id);
        if let Some(capsule_id) = normalized_capsule_id(capsule_id) {
            if SkillDefinition::is_valid_identifier(skill_id) {
                self.skill_assignments.push(StyleCapsuleAssignment {
                    skill_id: skill_id.to_string(),
                    capsule_id,
                });
            }
        }
        self.skill_assignments = normalized_assignments(std::mem::take(&mut self.skill_assignments));
    }
}

fn normalized_capsule_id(value: Option<&str>) -> Option<String> {
    let normalized = value?.trim().to_lowercase();
    StyleCapsule::is_valid_identifier(&normalized).then_some(normalized)
}

fn normalized_assignments(values: Vec<StyleCapsuleAssignment>) -> Vec<StyleCapsuleAssignment> {
    let mut seen = std::collections::HashSet::new();
    values
        .into_iter()
        .filter_map(|assignment| {
            if !SkillDefinition::is_valid_identifier(&assignment.skill_id) {
                return None;
            }
            let capsule_id = normalized_capsule_id(Some(&assignment.capsule_id))?;
            if !seen.insert(assignment.skill_id.clone()) {
                return None;
            }
            Some(StyleCapsuleAssignment {
                skill_id: assignment.skill_id,
                capsule_id,
            })
        })
        .take(MAX_STYLE_ASSIGNMENTS)
        .collect()
}

// ---------------------------------------------------------------------------
// File store (one JSON file per custom capsule)
// ---------------------------------------------------------------------------

/// Custom capsules live as `<id>.json` under `StyleCapsules/` in the
/// application data directory. Only `user.`-namespaced, size-bounded, regular
/// files are accepted; identifiers are the only source of file names.
#[derive(Debug, Clone)]
pub struct StyleCapsuleStore {
    root: PathBuf,
}

impl StyleCapsuleStore {
    pub fn new(application_data_dir: &Path) -> Self {
        Self {
            root: application_data_dir.join("StyleCapsules"),
        }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn load_custom(&self) -> Result<Vec<StyleCapsule>, StyleCapsuleError> {
        self.prepare_root()?;
        let mut file_names: Vec<String> = std::fs::read_dir(&self.root)?
            .filter_map(|entry| entry.ok())
            .map(|entry| entry.file_name().to_string_lossy().into_owned())
            .filter(|name| !name.starts_with('.'))
            .filter(|name| {
                Path::new(name)
                    .extension()
                    .map(|ext| ext.eq_ignore_ascii_case("json"))
                    .unwrap_or(false)
            })
            .collect();
        file_names.sort();

        let mut capsules = Vec::new();
        for name in file_names.into_iter().take(MAX_CUSTOM_STYLE_CAPSULES) {
            let path = self.root.join(&name);
            let metadata = std::fs::symlink_metadata(&path)?;
            if metadata.file_type().is_symlink() {
                return Err(StyleCapsuleError::SymbolicLink);
            }
            if !metadata.is_file() {
                continue;
            }
            if metadata.len() > MAX_STYLE_FILE_BYTES {
                return Err(StyleCapsuleError::Oversized);
            }
            let data = std::fs::read(&path)?;
            let capsule: StyleCapsule = serde_json::from_slice(&data)
                .map_err(|e| StyleCapsuleError::Parse(e.to_string()))?;
            if StyleCapsule::is_valid_identifier(&capsule.id)
                && capsule.id.starts_with("user.")
                && !capsule.name.is_empty()
                && !capsule.summary.is_empty()
                && !capsule.is_built_in
            {
                capsules.push(capsule);
            }
        }
        Ok(capsules)
    }

    pub fn load_all(&self) -> Result<Vec<StyleCapsule>, StyleCapsuleError> {
        Ok(all_style_capsules(&self.load_custom()?))
    }

    pub fn save(&self, capsule: &StyleCapsule) -> Result<(), StyleCapsuleError> {
        if !StyleCapsule::is_valid_identifier(&capsule.id) || !capsule.id.starts_with("user.") {
            return Err(StyleCapsuleError::InvalidIdentifier);
        }
        if capsule.name.trim().is_empty()
            || capsule.summary.trim().is_empty()
            || capsule.is_built_in
        {
            return Err(StyleCapsuleError::InvalidContent);
        }
        self.prepare_root()?;
        let existing = self.load_custom()?;
        let replaces_existing = existing.iter().any(|c| c.id == capsule.id);
        if !replaces_existing && existing.len() >= MAX_CUSTOM_STYLE_CAPSULES {
            return Err(StyleCapsuleError::Oversized);
        }

        let data =
            serde_json::to_vec_pretty(capsule).map_err(|e| StyleCapsuleError::Parse(e.to_string()))?;
        if data.len() as u64 > MAX_STYLE_FILE_BYTES {
            return Err(StyleCapsuleError::Oversized);
        }
        write_private(&self.file_path(&capsule.id), &data)?;
        Ok(())
    }

    pub fn delete(&self, id: &str) -> Result<(), StyleCapsuleError> {
        if !id.starts_with("user.") {
            return Err(StyleCapsuleError::BuiltInReadOnly);
        }
        // Stricter than the Swift original: the identifier is re-validated so
        // a crafted id can never become a path outside the store.
        if !StyleCapsule::is_valid_identifier(id) {
            return Err(StyleCapsuleError::InvalidIdentifier);
        }
        self.prepare_root()?;
        let path = self.file_path(id);
        let Ok(metadata) = std::fs::symlink_metadata(&path) else {
            return Err(StyleCapsuleError::Missing);
        };
        if metadata.file_type().is_symlink() {
            return Err(StyleCapsuleError::SymbolicLink);
        }
        std::fs::remove_file(&path)?;
        Ok(())
    }

    /// Writes a capsule to a caller-chosen location (settings export).
    pub fn export(&self, capsule: &StyleCapsule, path: &Path) -> Result<(), StyleCapsuleError> {
        let data =
            serde_json::to_vec_pretty(capsule).map_err(|e| StyleCapsuleError::Parse(e.to_string()))?;
        std::fs::write(path, data)?;
        Ok(())
    }

    fn prepare_root(&self) -> Result<(), StyleCapsuleError> {
        if let Ok(metadata) = std::fs::symlink_metadata(&self.root) {
            if metadata.file_type().is_symlink() {
                return Err(StyleCapsuleError::SymbolicLink);
            }
        }
        create_private_dir(&self.root)?;
        Ok(())
    }

    fn file_path(&self, id: &str) -> PathBuf {
        self.root.join(format!("{id}.json"))
    }
}

// ---------------------------------------------------------------------------
// Analyzer (local heuristic, no network)
// ---------------------------------------------------------------------------

/// Builds an editable style summary from user-pasted writing samples. Purely
/// local heuristics; the user reviews the text before it is saved.
pub fn summarize_style_samples(samples: &str) -> String {
    let normalized = samples.trim();
    if normalized.is_empty() {
        return String::new();
    }

    let sentences: Vec<&str> = normalized
        .split(['.', '!', '?', '。', '！', '？', '\n'])
        .filter(|sentence| !sentence.is_empty())
        .collect();
    let average_words = if sentences.is_empty() {
        0
    } else {
        let total: usize = sentences
            .iter()
            .map(|sentence| sentence.split_whitespace().count())
            .sum();
        (total / sentences.len()).max(1)
    };

    let uses_bullets = normalized.contains("\n- ") || normalized.contains("\n• ");
    let contains_chinese = {
        static HAN: std::sync::LazyLock<fancy_regex::Regex> =
            std::sync::LazyLock::new(|| fancy_regex::Regex::new(r"\p{Han}").unwrap());
        HAN.is_match(normalized).unwrap_or(false)
    };
    let contains_english = normalized.chars().any(|c| c.is_ascii_alphabetic());

    let language = match (contains_chinese, contains_english) {
        (true, true) => "mixed Chinese and English",
        (true, false) => "predominantly Chinese",
        _ => "predominantly English",
    };
    let sentence_style = if average_words <= 12 {
        "short, compact sentences"
    } else {
        "moderate-length sentences"
    };
    let structure = if uses_bullets {
        "Use bullets when organizing multiple points."
    } else {
        "Prefer short paragraphs over unnecessary bullets."
    };

    format!(
        "Write in {language} with {sentence_style}. {structure}\nPreserve the speaker's directness and technical density. Avoid adding greetings, sign-offs, emojis, hype, unsupported claims, or facts that are not present."
    )
}

// ---------------------------------------------------------------------------
// Resolver
// ---------------------------------------------------------------------------

/// The capsule for a dictation session: Styles must be enabled, the Skill must
/// hold the `styleCapsule` capability, and the assigned (or default) capsule
/// must exist. Anything else yields no style section in the prompt.
pub fn resolve_style_capsule<'a>(
    config: &StyleCapsuleConfig,
    available: &'a [StyleCapsule],
    skill: &SkillDefinition,
) -> Option<&'a StyleCapsule> {
    if !config.enabled {
        return None;
    }
    if !skill
        .all_capabilities()
        .contains(&SkillCapability::StyleCapsule)
    {
        return None;
    }
    let id = config.capsule_id_for(&skill.id)?;
    available.iter().find(|capsule| capsule.id == id)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::skill::{
        SkillDeliveryPolicy, SkillOutputContract, SkillOutputFormat, SkillRiskLevel,
        SkillValidatorPolicy,
    };

    fn skill(id: &str, capabilities: Vec<SkillCapability>) -> SkillDefinition {
        SkillDefinition {
            schema_version: 1,
            id: id.into(),
            version: "1.0.0".into(),
            name: "Test".into(),
            author: "VibeCompose".into(),
            minimum_app_version: "0.1.0".into(),
            required_capabilities: vec![SkillCapability::Voice],
            optional_capabilities: capabilities,
            terminology_entries: vec![],
            prompt_instruction: "Voice Mode: Test.".into(),
            output: SkillOutputContract {
                format: SkillOutputFormat::PlainText,
                delivery: SkillDeliveryPolicy::AutomaticPasteWhenVerified,
                risk: SkillRiskLevel::Low,
            },
            validators: SkillValidatorPolicy::default(),
            legacy_mode: None,
            summary: None,
            use_case: None,
        }
    }

    fn user_capsule(id: &str, name: &str, summary: &str) -> StyleCapsule {
        StyleCapsule::new(
            id,
            name,
            summary,
            &[],
            "2026-08-12T00:00:00Z",
            "2026-08-12T00:00:00Z",
            false,
        )
    }

    #[test]
    fn constructor_normalizes_name_summary_and_examples() {
        let long_name = "n".repeat(100);
        let examples = vec![
            format!("  {}  ", "e".repeat(1_200)),
            "   ".to_string(),
            "第二个例子".to_string(),
        ];
        let capsule = StyleCapsule::new(
            "user.test-style",
            &format!("  {long_name}  "),
            "  一段风格描述  ",
            &examples,
            "2026-08-12T00:00:00Z",
            "2026-08-12T00:00:00Z",
            false,
        );
        assert_eq!(capsule.name.chars().count(), MAX_STYLE_NAME_CHARS);
        assert_eq!(capsule.summary, "一段风格描述");
        assert_eq!(capsule.examples.len(), 2);
        assert_eq!(capsule.examples[0].chars().count(), MAX_STYLE_EXAMPLE_CHARS);
        assert_eq!(capsule.examples[1], "第二个例子");
    }

    #[test]
    fn prompt_text_appends_examples_section() {
        let plain = user_capsule("user.plain", "Plain", "简洁直接。");
        assert_eq!(plain.prompt_text(), "简洁直接。");

        let with_examples = StyleCapsule::new(
            "user.with-examples",
            "With",
            "简洁直接。",
            &["例一".to_string(), "例二".to_string()],
            "2026-08-12T00:00:00Z",
            "2026-08-12T00:00:00Z",
            false,
        );
        assert_eq!(
            with_examples.prompt_text(),
            "简洁直接。\nUser-approved examples:\n- 例一\n- 例二"
        );
    }

    #[test]
    fn identifier_validation_enforces_namespace_and_charset() {
        assert!(StyleCapsule::is_valid_identifier("builtin.work-formal"));
        assert!(StyleCapsule::is_valid_identifier("user.my-style.v2"));
        assert!(!StyleCapsule::is_valid_identifier("community.style"));
        assert!(!StyleCapsule::is_valid_identifier("user.AB"));
        assert!(!StyleCapsule::is_valid_identifier("user.x"));
        assert!(!StyleCapsule::is_valid_identifier("user./escape"));
        assert!(!StyleCapsule::is_valid_identifier(&format!(
            "user.{}",
            "a".repeat(120)
        )));
    }

    #[test]
    fn builtin_registry_is_stable() {
        let builtins = builtin_style_capsules();
        assert_eq!(builtins.len(), 8);
        assert!(builtins.iter().all(|c| c.is_built_in));
        assert!(builtins
            .iter()
            .all(|c| StyleCapsule::is_valid_identifier(&c.id)));
        assert_eq!(builtins[0].id, WORK_FORMAL_STYLE_ID);

        let custom = vec![
            user_capsule("user.mine", "Mine", "描述"),
            StyleCapsule::new(
                "user.fake-builtin",
                "Fake",
                "描述",
                &[],
                "2026-08-12T00:00:00Z",
                "2026-08-12T00:00:00Z",
                true,
            ),
        ];
        let all = all_style_capsules(&custom);
        assert_eq!(all.len(), 9);
        assert!(all.iter().any(|c| c.id == "user.mine"));
        assert!(!all.iter().any(|c| c.id == "user.fake-builtin"));
    }

    #[test]
    fn config_normalization_drops_invalid_and_duplicate_assignments() {
        let config = StyleCapsuleConfig {
            enabled: true,
            default_capsule_id: Some("  Builtin.Work-Formal ".into()),
            skill_assignments: vec![
                StyleCapsuleAssignment {
                    skill_id: "app.vibecompose.skill.email".into(),
                    capsule_id: "builtin.team-chat".into(),
                },
                StyleCapsuleAssignment {
                    skill_id: "app.vibecompose.skill.email".into(),
                    capsule_id: "builtin.work-formal".into(),
                },
                StyleCapsuleAssignment {
                    skill_id: "Bad_Skill".into(),
                    capsule_id: "builtin.work-formal".into(),
                },
                StyleCapsuleAssignment {
                    skill_id: "app.vibecompose.skill.reply".into(),
                    capsule_id: "not-a-capsule".into(),
                },
            ],
        }
        .normalized();

        assert_eq!(
            config.default_capsule_id.as_deref(),
            Some("builtin.work-formal")
        );
        assert_eq!(config.skill_assignments.len(), 1);
        assert_eq!(
            config.assigned_capsule_id("app.vibecompose.skill.email"),
            Some("builtin.team-chat")
        );
    }

    #[test]
    fn capsule_id_for_prefers_assignment_then_default() {
        let mut config = StyleCapsuleConfig {
            default_capsule_id: Some("builtin.work-formal".into()),
            ..Default::default()
        };
        config.set_capsule_id(Some("builtin.team-chat"), "app.vibecompose.skill.email");

        assert_eq!(
            config.capsule_id_for("app.vibecompose.skill.email"),
            Some("builtin.team-chat")
        );
        assert_eq!(
            config.capsule_id_for("app.vibecompose.skill.direct"),
            Some("builtin.work-formal")
        );

        config.set_capsule_id(None, "app.vibecompose.skill.email");
        assert_eq!(
            config.capsule_id_for("app.vibecompose.skill.email"),
            Some("builtin.work-formal")
        );
    }

    #[test]
    fn serde_keys_match_swift_config_schema() {
        let config = StyleCapsuleConfig {
            default_capsule_id: Some("builtin.work-formal".into()),
            skill_assignments: vec![StyleCapsuleAssignment {
                skill_id: "app.vibecompose.skill.email".into(),
                capsule_id: "builtin.team-chat".into(),
            }],
            ..Default::default()
        };
        let json = serde_json::to_value(&config).unwrap();
        assert!(json.get("defaultCapsuleID").is_some());
        let assignment = &json["skillAssignments"][0];
        assert!(assignment.get("skillID").is_some());
        assert!(assignment.get("capsuleID").is_some());
    }

    #[test]
    fn store_save_load_delete_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let store = StyleCapsuleStore::new(dir.path());
        let capsule = user_capsule("user.my-style", "我的风格", "短句，直接。");
        store.save(&capsule).unwrap();

        let custom = store.load_custom().unwrap();
        assert_eq!(custom, vec![capsule.clone()]);
        assert_eq!(store.load_all().unwrap().len(), 9);

        store.delete("user.my-style").unwrap();
        assert!(store.load_custom().unwrap().is_empty());
        assert!(matches!(
            store.delete("user.my-style"),
            Err(StyleCapsuleError::Missing)
        ));
    }

    #[test]
    fn store_rejects_invalid_saves_and_builtin_deletes() {
        let dir = tempfile::tempdir().unwrap();
        let store = StyleCapsuleStore::new(dir.path());

        assert!(matches!(
            store.save(&user_capsule("builtin.work-formal", "X", "Y")),
            Err(StyleCapsuleError::InvalidIdentifier)
        ));
        assert!(matches!(
            store.save(&user_capsule("user.empty-name", "  ", "Y")),
            Err(StyleCapsuleError::InvalidContent)
        ));
        let mut fake_builtin = user_capsule("user.claims-builtin", "X", "Y");
        fake_builtin.is_built_in = true;
        assert!(matches!(
            store.save(&fake_builtin),
            Err(StyleCapsuleError::InvalidContent)
        ));
        assert!(matches!(
            store.delete("builtin.work-formal"),
            Err(StyleCapsuleError::BuiltInReadOnly)
        ));
        assert!(matches!(
            store.delete("user./../escape"),
            Err(StyleCapsuleError::InvalidIdentifier)
        ));
    }

    #[test]
    fn store_skips_foreign_files_and_rejects_oversized() {
        let dir = tempfile::tempdir().unwrap();
        let store = StyleCapsuleStore::new(dir.path());
        store
            .save(&user_capsule("user.keep-me", "Keep", "描述"))
            .unwrap();

        // Wrong namespace inside a well-formed file: skipped, not an error.
        std::fs::write(
            store.root().join("user.wrong-namespace.json"),
            serde_json::to_vec(&StyleCapsule::new(
                "builtin.sneaky",
                "X",
                "Y",
                &[],
                "",
                "",
                false,
            ))
            .unwrap(),
        )
        .unwrap();
        assert_eq!(store.load_custom().unwrap().len(), 1);

        // Oversized file: load fails loudly.
        std::fs::write(
            store.root().join("user.huge.json"),
            vec![b' '; (MAX_STYLE_FILE_BYTES + 1) as usize],
        )
        .unwrap();
        assert!(matches!(
            store.load_custom(),
            Err(StyleCapsuleError::Oversized)
        ));
    }

    #[test]
    fn analyzer_describes_language_sentences_and_bullets() {
        assert_eq!(summarize_style_samples("   "), "");

        let chinese = summarize_style_samples("我们今天发布。明天复盘。");
        assert!(chinese.starts_with("Write in predominantly Chinese with short, compact sentences."));
        assert!(chinese.contains("Prefer short paragraphs"));

        let mixed_bullets = summarize_style_samples(
            "Plan for 今天:\n- ship the API fix and write the full follow-up notes for everyone involved in the deploy today\n- 复盘 the incident and document every mitigation step we agreed on during the review meeting yesterday afternoon",
        );
        assert!(mixed_bullets.starts_with("Write in mixed Chinese and English"));
        assert!(mixed_bullets.contains("moderate-length sentences"));
        assert!(mixed_bullets.contains("Use bullets when organizing multiple points."));
        assert!(mixed_bullets.ends_with(
            "Preserve the speaker's directness and technical density. Avoid adding greetings, sign-offs, emojis, hype, unsupported claims, or facts that are not present."
        ));
    }

    #[test]
    fn resolver_requires_enabled_capability_and_known_capsule() {
        let available = builtin_style_capsules();
        let mut config = StyleCapsuleConfig {
            default_capsule_id: Some(WORK_FORMAL_STYLE_ID.into()),
            ..Default::default()
        };

        let capable = skill(
            "app.vibecompose.skill.email",
            vec![SkillCapability::StyleCapsule],
        );
        let incapable = skill("app.vibecompose.skill.direct", vec![]);

        let resolved = resolve_style_capsule(&config, &available, &capable).unwrap();
        assert_eq!(resolved.id, WORK_FORMAL_STYLE_ID);
        assert!(resolve_style_capsule(&config, &available, &incapable).is_none());

        config.set_capsule_id(Some(TEAM_CHAT_STYLE_ID), "app.vibecompose.skill.email");
        assert_eq!(
            resolve_style_capsule(&config, &available, &capable)
                .unwrap()
                .id,
            TEAM_CHAT_STYLE_ID
        );

        config.enabled = false;
        assert!(resolve_style_capsule(&config, &available, &capable).is_none());

        config.enabled = true;
        config.set_capsule_id(Some("user.deleted"), "app.vibecompose.skill.email");
        assert!(resolve_style_capsule(&config, &available, &capable).is_none());
    }
}
