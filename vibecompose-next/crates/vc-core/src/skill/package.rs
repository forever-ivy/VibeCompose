//! Skill package loading: SKILL.md frontmatter, `vibecompose.yaml` profile,
//! resource enumeration with containment checks, and SkillDefinition
//! assembly. Ported from Swift `AgentSkillRuntime.swift`.
//!
//! Skill packages are untrusted declarative data. They cannot execute code,
//! add providers or network origins, or bypass the fixed prompt and delivery
//! boundaries.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};
use thiserror::Error;

use super::{
    DictationMode, SkillCapability, SkillDefinition, SkillDeliveryPolicy, SkillOutputContract,
    SkillOutputFormat, SkillRiskLevel, SkillValidatorPolicy,
};
use crate::terminology::{TerminologyEntry, TerminologyEntryType};
use crate::yamlite::RestrictedYamlDocument;

pub const MAX_FILE_COUNT: usize = 128;
pub const MAX_FILE_BYTES: u64 = 512 * 1024;
pub const MAX_PACKAGE_BYTES: u64 = 4 * 1024 * 1024;
pub const MAX_SKILL_MD_BYTES: usize = 96 * 1024;
pub const MAX_PROFILE_BYTES: u64 = 64 * 1024;
pub const MAX_INSTRUCTION_CHARS: usize = 40_000;

#[derive(Debug, Error)]
pub enum SkillPackageError {
    #[error("the standard Skill directory is missing SKILL.md")]
    MissingSkillMarkdown,
    #[error("SKILL.md frontmatter is invalid: {0}")]
    InvalidFrontmatter(String),
    #[error("vibecompose.yaml is invalid: {0}")]
    InvalidProfile(String),
    #[error("the Skill contains an unsafe path: {0}")]
    UnsafePath(String),
    #[error("the Skill contains a symbolic link: {0}")]
    SymbolicLink(String),
    #[error("the Skill resource is not readable UTF-8 text: {0}")]
    UnreadableText(String),
    #[error("the Skill contains too many files")]
    TooManyFiles,
    #[error("a Skill resource is too large: {0}")]
    FileTooLarge(String),
    #[error("the Skill directory is too large")]
    PackageTooLarge,
    #[error("the Skill is not compatible with VibeCompose: {0}")]
    Incompatible(String),
    #[error("io error at {path}: {source}")]
    Io {
        path: String,
        source: std::io::Error,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillFrontmatter {
    pub name: String,
    pub description: String,
    pub license: Option<String>,
    pub compatibility: Option<String>,
    pub metadata: BTreeMap<String, String>,
    pub allowed_tools: Option<String>,
}

/// Parses SKILL.md: YAML frontmatter delimited by `---`, then instructions.
pub fn parse_frontmatter(
    text: &str,
) -> Result<(SkillFrontmatter, String, BTreeMap<String, String>), SkillPackageError> {
    if !text.starts_with("---") {
        return Err(SkillPackageError::InvalidFrontmatter(
            "SKILL.md must begin with YAML frontmatter".into(),
        ));
    }
    let lines: Vec<&str> = text.split('\n').collect();
    let Some(end_offset) = lines[1..]
        .iter()
        .position(|line| line.trim() == "---")
    else {
        return Err(SkillPackageError::InvalidFrontmatter(
            "frontmatter closing delimiter is missing".into(),
        ));
    };
    let end = end_offset + 1;
    let yaml = lines[1..end].join("\n");
    let body = lines[end + 1..].join("\n").trim().to_string();
    if body.is_empty() || body.chars().count() > MAX_INSTRUCTION_CHARS {
        return Err(SkillPackageError::InvalidFrontmatter(
            "instructions must contain 1–40,000 characters".into(),
        ));
    }

    let document = RestrictedYamlDocument::parse(
        &yaml,
        &[
            "name",
            "description",
            "license",
            "compatibility",
            "metadata",
            "allowed-tools",
        ],
        true,
    )
    .map_err(|e| SkillPackageError::InvalidFrontmatter(e.to_string()))?;

    let name = document.scalar("name").unwrap_or_default().trim().to_string();
    let description = document
        .scalar("description")
        .unwrap_or_default()
        .trim()
        .to_string();
    if !is_portable_name(&name) {
        return Err(SkillPackageError::InvalidFrontmatter(
            "name must be a portable 1–64 character identifier".into(),
        ));
    }
    if description.is_empty() || description.chars().count() > 1024 {
        return Err(SkillPackageError::InvalidFrontmatter(
            "description must contain 1–1,024 characters".into(),
        ));
    }

    let mut metadata = BTreeMap::new();
    for (key, value) in &document.scalars {
        if let Some(stripped) = key.strip_prefix("metadata.") {
            metadata.insert(
                stripped.to_string(),
                value.chars().take(2048).collect::<String>(),
            );
        }
    }
    let known = ["name", "description", "license", "compatibility", "allowed-tools"];
    let mut vendor = BTreeMap::new();
    for (key, value) in &document.scalars {
        if !known.contains(&key.as_str()) && !key.starts_with("metadata.") {
            vendor.insert(key.clone(), value.clone());
        }
    }
    for (key, values) in &document.lists {
        if !known.contains(&key.as_str()) && !key.starts_with("metadata.") {
            vendor.insert(key.clone(), values.join(", "));
        }
    }
    let allowed_tools = document.scalar("allowed-tools").map(str::to_string).or_else(|| {
        let list = document.list("allowed-tools");
        if list.is_empty() {
            None
        } else {
            Some(list.join(", "))
        }
    });

    Ok((
        SkillFrontmatter {
            name,
            description,
            license: document.scalar("license").map(str::to_string),
            compatibility: document.scalar("compatibility").map(str::to_string),
            metadata,
            allowed_tools,
        },
        body,
        vendor,
    ))
}

fn is_portable_name(name: &str) -> bool {
    let mut chars = name.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    if !first.is_ascii_alphanumeric() {
        return false;
    }
    name.chars().count() <= 64
        && chars.all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SkillResourceBindings {
    pub terminology: Vec<String>,
    pub templates: Vec<String>,
    pub references: Vec<String>,
    pub examples: Vec<String>,
    pub golden_tests: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SkillProfile {
    pub context_required: Vec<SkillCapability>,
    pub context_optional: Vec<SkillCapability>,
    pub resource_bindings: SkillResourceBindings,
    pub output: SkillOutputContract,
    pub validators: SkillValidatorPolicy,
    pub risk: SkillRiskLevel,
}

impl Default for SkillProfile {
    /// The safe default profile: preview-gated medium risk.
    fn default() -> Self {
        Self {
            context_required: vec![SkillCapability::Voice],
            context_optional: Vec::new(),
            resource_bindings: SkillResourceBindings::default(),
            output: SkillOutputContract {
                format: SkillOutputFormat::PlainText,
                delivery: SkillDeliveryPolicy::PreviewThenPaste,
                risk: SkillRiskLevel::Medium,
            },
            validators: SkillValidatorPolicy::default(),
            risk: SkillRiskLevel::Medium,
        }
    }
}

/// Parses `vibecompose.yaml`. Only the fixed key set is allowed; unknown keys
/// fail closed. Medium/high-risk Skills cannot request auto-paste.
pub fn parse_profile(text: &str) -> Result<SkillProfile, SkillPackageError> {
    let document = RestrictedYamlDocument::parse(
        text,
        &["context", "resources", "output", "risk", "validators"],
        false,
    )
    .map_err(|e| SkillPackageError::InvalidProfile(e.to_string()))?;

    const ALLOWED_PATHS: &[&str] = &[
        "context.required",
        "context.optional",
        "resources.terminology",
        "resources.templates",
        "resources.references",
        "resources.examples",
        "resources.goldenTests",
        "output.format",
        "output.delivery",
        "output.risk",
        "risk",
        "validators.requireNonEmpty",
        "validators.maximumCharacters",
        "validators.preserveTechnicalLiterals",
        "validators.requireClosedMarkdownFences",
        "validators.requiredSections",
        "validators.forbiddenPhrases",
    ];
    if let Some(unknown) = document
        .paths()
        .find(|path| !ALLOWED_PATHS.contains(path))
    {
        return Err(SkillPackageError::InvalidProfile(format!(
            "unknown profile key {unknown}"
        )));
    }

    let sources = |path: &str| -> Result<Vec<SkillCapability>, SkillPackageError> {
        document
            .list(path)
            .iter()
            .map(|value| {
                SkillCapability::parse(value).ok_or_else(|| {
                    SkillPackageError::InvalidProfile(format!("unknown Context source {value}"))
                })
            })
            .collect()
    };

    let format_value = document.scalar("output.format").unwrap_or("plainText");
    let delivery_value = document
        .scalar("output.delivery")
        .unwrap_or("previewThenPaste");
    let risk_value = document
        .scalar("risk")
        .or_else(|| document.scalar("output.risk"))
        .unwrap_or("medium");

    let format = SkillOutputFormat::parse(format_value)
        .filter(|f| *f != SkillOutputFormat::ActionPreview);
    let delivery = SkillDeliveryPolicy::parse(delivery_value);
    let risk = SkillRiskLevel::parse(risk_value);
    let (Some(format), Some(delivery), Some(risk)) = (format, delivery, risk) else {
        return Err(SkillPackageError::InvalidProfile(
            "output format, delivery, or risk is unsupported".into(),
        ));
    };
    if delivery == SkillDeliveryPolicy::AutomaticPasteWhenVerified && risk != SkillRiskLevel::Low {
        return Err(SkillPackageError::InvalidProfile(
            "medium- and high-risk Skills cannot auto-paste".into(),
        ));
    }

    let required = sources("context.required")?;
    let optional = sources("context.optional")?;
    let maximum_characters = document
        .scalar("validators.maximumCharacters")
        .and_then(|v| v.parse::<usize>().ok())
        .unwrap_or(12_000)
        .clamp(1, 100_000);
    let bool_at = |path: &str, fallback: bool| -> bool {
        match document.scalar(path).map(str::to_lowercase).as_deref() {
            Some("true") | Some("yes") | Some("1") => true,
            Some("false") | Some("no") | Some("0") => false,
            _ => fallback,
        }
    };

    let required_sections: Vec<Vec<String>> = document
        .list("validators.requiredSections")
        .iter()
        .map(|line| {
            line.split('|')
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_string)
                .collect::<Vec<_>>()
        })
        .filter(|alternatives: &Vec<String>| !alternatives.is_empty())
        .collect();

    Ok(SkillProfile {
        context_required: if required.is_empty() {
            vec![SkillCapability::Voice]
        } else {
            required
        },
        context_optional: optional,
        resource_bindings: SkillResourceBindings {
            terminology: document.list("resources.terminology").to_vec(),
            templates: document.list("resources.templates").to_vec(),
            references: document.list("resources.references").to_vec(),
            examples: document.list("resources.examples").to_vec(),
            golden_tests: document.list("resources.goldenTests").to_vec(),
        },
        output: SkillOutputContract {
            format,
            delivery,
            risk,
        },
        validators: SkillValidatorPolicy {
            require_non_empty: bool_at("validators.requireNonEmpty", true),
            maximum_characters,
            preserve_technical_literals: bool_at("validators.preserveTechnicalLiterals", true),
            require_closed_markdown_fences: bool_at("validators.requireClosedMarkdownFences", false),
            required_section_alternatives: required_sections,
            forbidden_phrases: document.list("validators.forbiddenPhrases").to_vec(),
        }
        .normalized(),
        risk,
    })
}

/// Parses a Skill-local terminology.csv: header `type,original,replacement,enabled,aliases`
/// with `|`-separated aliases. Invalid rows are skipped, matching Swift.
pub fn parse_terminology_csv(text: &str, source: &str) -> Vec<TerminologyEntry> {
    let mut lines = text.lines();
    let Some(header_line) = lines.next() else {
        return Vec::new();
    };
    let header: Vec<String> = parse_csv_fields(header_line)
        .into_iter()
        .map(|f| f.trim().to_lowercase())
        .collect();
    let index_of = |names: &[&str]| -> Option<usize> {
        names.iter().find_map(|n| header.iter().position(|h| h == n))
    };
    let Some(original_index) = index_of(&["original", "term", "canonical", "word", "phrase"]) else {
        return Vec::new();
    };
    let type_index = index_of(&["type"]);
    let replacement_index = index_of(&["replacement", "correction"]);
    let enabled_index = index_of(&["enabled"]);
    let aliases_index = index_of(&["aliases"]);

    let field = |fields: &[String], index: Option<usize>| -> String {
        index
            .and_then(|i| fields.get(i))
            .map(|s| s.to_string())
            .unwrap_or_default()
    };

    let mut seen = std::collections::HashSet::new();
    let mut entries = Vec::new();
    for line in lines {
        let fields = parse_csv_fields(line);
        let Some(original) = fields.get(original_index) else {
            continue;
        };
        let original = original.trim().to_string();
        if !is_valid_term(&original) {
            continue;
        }
        let raw_type = field(&fields, type_index).trim().to_lowercase();
        let replacement = field(&fields, replacement_index).trim().to_string();
        let entry_type = if raw_type == "correction" || !replacement.is_empty() {
            TerminologyEntryType::Correction
        } else {
            TerminologyEntryType::Term
        };
        if entry_type == TerminologyEntryType::Correction && replacement.is_empty() {
            continue;
        }
        let aliases: Vec<String> = field(&fields, aliases_index)
            .split('|')
            .map(str::trim)
            .filter(|a| is_valid_term(a))
            .map(str::to_string)
            .collect();
        let enabled_raw = field(&fields, enabled_index).trim().to_lowercase();
        let is_enabled = enabled_raw.is_empty()
            || !["0", "false", "no", "off", "disabled"].contains(&enabled_raw.as_str());

        let key = format!(
            "{}|{}",
            original.to_lowercase(),
            replacement.to_lowercase()
        );
        if !seen.insert(key) {
            continue;
        }
        entries.push(TerminologyEntry {
            id: uuid::Uuid::new_v4(),
            entry_type,
            original,
            replacement: (entry_type == TerminologyEntryType::Correction).then_some(replacement),
            aliases,
            is_enabled,
            source: source.to_string(),
            usage_count: 0,
            created_at: String::new(),
        });
    }
    entries
}

fn parse_csv_fields(line: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut field = String::new();
    let mut quoted = false;
    let mut chars = line.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '"' {
            if quoted && chars.peek() == Some(&'"') {
                field.push('"');
                chars.next();
                continue;
            }
            quoted = !quoted;
        } else if c == ',' && !quoted {
            fields.push(std::mem::take(&mut field));
        } else {
            field.push(c);
        }
    }
    fields.push(field);
    fields
}

fn is_valid_term(term: &str) -> bool {
    const MAX_FIELD_CHARS: usize = 120;
    if term.is_empty() || term.chars().count() > MAX_FIELD_CHARS {
        return false;
    }
    let lowered = term.to_lowercase();
    !["term", "terms", "original", "canonical", "word", "phrase"].contains(&lowered.as_str())
}

/// A loaded, hash-pinned Skill package directory.
#[derive(Debug, Clone)]
pub struct LoadedSkillPackage {
    pub root: PathBuf,
    pub frontmatter: SkillFrontmatter,
    pub instructions: String,
    pub vendor_extensions: BTreeMap<String, String>,
    pub profile: SkillProfile,
    pub terminology: Vec<TerminologyEntry>,
    pub resource_paths: Vec<String>,
    pub content_sha256: String,
}

impl LoadedSkillPackage {
    /// Builds the runtime SkillDefinition from package metadata. Identity
    /// fields come from `metadata.*` in the frontmatter.
    pub fn definition(&self) -> Result<SkillDefinition, SkillPackageError> {
        let metadata = &self.frontmatter.metadata;
        let id = metadata
            .get("vibecompose-id")
            .cloned()
            .unwrap_or_else(|| format!("community.{}", self.frontmatter.name.to_lowercase()));
        let version = metadata.get("version").cloned().unwrap_or_else(|| "1.0.0".into());
        if !SkillDefinition::is_valid_identifier(&id) {
            return Err(SkillPackageError::Incompatible(format!(
                "invalid skill identifier {id}"
            )));
        }
        if !SkillDefinition::is_valid_version(&version) {
            return Err(SkillPackageError::Incompatible(format!(
                "invalid skill version {version}"
            )));
        }
        let definition = SkillDefinition {
            schema_version: 1,
            id,
            version,
            name: metadata
                .get("display-name")
                .cloned()
                .unwrap_or_else(|| self.frontmatter.name.clone()),
            author: metadata
                .get("author")
                .cloned()
                .unwrap_or_else(|| "Community".into()),
            minimum_app_version: metadata
                .get("minimum-app-version")
                .cloned()
                .unwrap_or_else(|| "0.1.0".into()),
            required_capabilities: self.profile.context_required.clone(),
            optional_capabilities: self.profile.context_optional.clone(),
            terminology_entries: self.terminology.clone(),
            prompt_instruction: self.instructions.clone(),
            output: self.profile.output,
            validators: self.profile.validators.clone(),
            legacy_mode: metadata
                .get("legacy-mode")
                .and_then(|m| DictationMode::parse(m)),
            summary: metadata.get("summary").cloned(),
            use_case: metadata.get("use-case").cloned(),
        };
        Ok(definition.normalized())
    }
}

/// Loads a Skill package directory with the same containment rules as Swift:
/// bounded file count/size, no symlinks, no dot-files, no traversal, UTF-8
/// SKILL.md, deterministic content hash.
pub fn load_package(root: &Path) -> Result<LoadedSkillPackage, SkillPackageError> {
    let skill_md_path = root.join("SKILL.md");
    if !skill_md_path.is_file() {
        return Err(SkillPackageError::MissingSkillMarkdown);
    }

    let mut files = enumerate_files(root)?;
    files.sort();

    let skill_text = read_text(&skill_md_path, "SKILL.md")?;
    if skill_text.len() > MAX_SKILL_MD_BYTES || skill_text.contains('\u{0}') {
        return Err(SkillPackageError::UnreadableText("SKILL.md".into()));
    }
    let (frontmatter, instructions, vendor) = parse_frontmatter(&skill_text)?;

    let profile_path = root.join("vibecompose.yaml");
    let profile = if profile_path.is_file() {
        let metadata = std::fs::metadata(&profile_path).map_err(|source| SkillPackageError::Io {
            path: "vibecompose.yaml".into(),
            source,
        })?;
        if metadata.len() > MAX_PROFILE_BYTES {
            return Err(SkillPackageError::InvalidProfile(
                "profile is too large or not UTF-8".into(),
            ));
        }
        parse_profile(&read_text(&profile_path, "vibecompose.yaml")?)?
    } else {
        SkillProfile::default()
    };

    let mut terminology = Vec::new();
    for resource in &profile.resource_bindings.terminology {
        let resolved = safe_join(root, resource)?;
        if resolved.is_file() {
            let csv = read_text(&resolved, resource)?;
            terminology.extend(parse_terminology_csv(&csv, "skill"));
        }
    }

    let mut hasher = Sha256::new();
    for relative in &files {
        let data = std::fs::read(root.join(relative)).map_err(|source| SkillPackageError::Io {
            path: relative.clone(),
            source,
        })?;
        hasher.update(relative.as_bytes());
        hasher.update([0u8]);
        hasher.update(&data);
        hasher.update([0u8]);
    }
    let content_sha256 = format!("{:x}", hasher.finalize());

    Ok(LoadedSkillPackage {
        root: root.to_path_buf(),
        frontmatter,
        instructions,
        vendor_extensions: vendor,
        profile,
        terminology,
        resource_paths: files,
        content_sha256,
    })
}

fn read_text(path: &Path, label: &str) -> Result<String, SkillPackageError> {
    let data = std::fs::read(path).map_err(|source| SkillPackageError::Io {
        path: label.to_string(),
        source,
    })?;
    String::from_utf8(data).map_err(|_| SkillPackageError::UnreadableText(label.to_string()))
}

fn safe_join(root: &Path, relative: &str) -> Result<PathBuf, SkillPackageError> {
    validate_relative_path(relative)?;
    Ok(root.join(relative))
}

fn validate_relative_path(path: &str) -> Result<(), SkillPackageError> {
    let parts: Vec<&str> = path.split('/').collect();
    if path.is_empty()
        || path.starts_with('/')
        || path.chars().count() > 500
        || parts.iter().any(|p| p.is_empty() || *p == "." || *p == "..")
    {
        return Err(SkillPackageError::UnsafePath(path.to_string()));
    }
    Ok(())
}

fn enumerate_files(root: &Path) -> Result<Vec<String>, SkillPackageError> {
    let mut files = Vec::new();
    let mut total: u64 = 0;
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let entries = std::fs::read_dir(&dir).map_err(|source| SkillPackageError::Io {
            path: dir.display().to_string(),
            source,
        })?;
        for entry in entries {
            let entry = entry.map_err(|source| SkillPackageError::Io {
                path: dir.display().to_string(),
                source,
            })?;
            let path = entry.path();
            let relative = path
                .strip_prefix(root)
                .map_err(|_| SkillPackageError::UnsafePath(path.display().to_string()))?
                .to_string_lossy()
                .replace('\\', "/");
            // Skip dot-prefixed junk and archive metadata directories.
            if relative
                .split('/')
                .any(|part| part.starts_with('.') || part == "__MACOSX")
            {
                continue;
            }
            validate_relative_path(&relative)?;
            let metadata = entry
                .metadata()
                .map_err(|source| SkillPackageError::Io {
                    path: relative.clone(),
                    source,
                })?;
            let symlink_metadata =
                std::fs::symlink_metadata(&path).map_err(|source| SkillPackageError::Io {
                    path: relative.clone(),
                    source,
                })?;
            if symlink_metadata.file_type().is_symlink() {
                return Err(SkillPackageError::SymbolicLink(relative));
            }
            if metadata.is_dir() {
                stack.push(path);
                continue;
            }
            if !metadata.is_file() {
                return Err(SkillPackageError::UnsafePath(relative));
            }
            if metadata.len() > MAX_FILE_BYTES {
                return Err(SkillPackageError::FileTooLarge(relative));
            }
            total += metadata.len();
            files.push(relative);
            if files.len() > MAX_FILE_COUNT {
                return Err(SkillPackageError::TooManyFiles);
            }
            if total > MAX_PACKAGE_BYTES {
                return Err(SkillPackageError::PackageTooLarge);
            }
        }
    }
    Ok(files)
}

#[cfg(test)]
mod tests {
    use super::*;

    const DIRECT_SKILL_MD: &str = "---\nname: direct\ndescription: Faithful dictation with light cleanup and no structural rewrite. Use for fast, faithful dictation when you do not need a structured transformation.\nlicense: MIT\ncompatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.\nmetadata:\n  author: VibeCompose\n  version: \"1.2.0\"\n  vibecompose-id: app.vibecompose.skill.direct\n  display-name: Direct\n  package-id: builtin.direct\n  summary: Faithful dictation with light cleanup and no structural rewrite.\n  use-case: Use for fast, faithful dictation when you do not need a structured transformation.\n  legacy-mode: direct\n---\n\nVoice Mode: Direct. Return faithful cleaned dictation in the speaker's language.\n";

    #[test]
    fn parses_builtin_frontmatter() {
        let (front, instructions, _vendor) = parse_frontmatter(DIRECT_SKILL_MD).unwrap();
        assert_eq!(front.name, "direct");
        assert_eq!(front.metadata.get("vibecompose-id").unwrap(), "app.vibecompose.skill.direct");
        assert_eq!(front.metadata.get("version").unwrap(), "1.2.0");
        assert!(instructions.starts_with("Voice Mode: Direct."));
    }

    #[test]
    fn profile_rejects_medium_risk_auto_paste() {
        let text = "output:\n  format: plainText\n  delivery: automaticPasteWhenVerified\n  risk: medium\n";
        assert!(parse_profile(text).is_err());
        let low = "output:\n  format: plainText\n  delivery: automaticPasteWhenVerified\n  risk: low\n";
        assert!(parse_profile(low).is_ok());
    }

    #[test]
    fn profile_rejects_unknown_keys() {
        let text = "output:\n  format: plainText\nnetwork:\n  origin: https://example.com\n";
        assert!(parse_profile(text).is_err());
    }

    #[test]
    fn profile_parses_required_sections_alternatives() {
        let text = "validators:\n  requiredSections:\n  - Observed Behavior|Observed|实际行为\n  - Impact|影响\n";
        let profile = parse_profile(text).unwrap();
        assert_eq!(profile.validators.required_section_alternatives.len(), 2);
        assert_eq!(
            profile.validators.required_section_alternatives[0],
            vec!["Observed Behavior", "Observed", "实际行为"]
        );
    }

    #[test]
    fn csv_parses_terms_corrections_and_quotes() {
        let csv = "type,original,replacement,enabled,aliases\nterm,OpenAPI,,true,open api|Open API\ncorrection,原话,正解,true,\nterm,\"a,b\",,false,\nbad-row-without-fields\n";
        let entries = parse_terminology_csv(csv, "skill");
        assert_eq!(entries.len(), 3);
        assert_eq!(entries[0].aliases, vec!["open api", "Open API"]);
        assert_eq!(entries[1].entry_type, TerminologyEntryType::Correction);
        assert_eq!(entries[1].replacement.as_deref(), Some("正解"));
        assert_eq!(entries[2].original, "a,b");
        assert!(!entries[2].is_enabled);
    }

    #[test]
    fn rejects_traversal_paths() {
        assert!(validate_relative_path("../evil").is_err());
        assert!(validate_relative_path("/abs").is_err());
        assert!(validate_relative_path("a/../b").is_err());
        assert!(validate_relative_path("ok/nested.md").is_ok());
    }
}
