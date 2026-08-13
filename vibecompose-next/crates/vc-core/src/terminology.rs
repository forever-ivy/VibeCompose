//! Terminology entries and deterministic transcript normalization.
//! Ported from Swift `TerminologyLibrary` / `TerminologyNormalizer` (core
//! alias-alignment path; language and punctuation conversion preferences are
//! carried in config and applied here where implemented).

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::config::TranscriptPunctuationPreference;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum TerminologyEntryType {
    #[default]
    Term,
    Correction,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TerminologyEntry {
    #[serde(default = "Uuid::new_v4")]
    pub id: Uuid,
    #[serde(rename = "type", default)]
    pub entry_type: TerminologyEntryType,
    pub original: String,
    #[serde(default)]
    pub replacement: Option<String>,
    #[serde(default)]
    pub aliases: Vec<String>,
    #[serde(default = "default_true")]
    pub is_enabled: bool,
    #[serde(default)]
    pub source: String,
    #[serde(default)]
    pub usage_count: u64,
    #[serde(default)]
    pub created_at: String,
}

fn default_true() -> bool {
    true
}

impl TerminologyEntry {
    pub fn term(canonical: &str, aliases: &[&str], source: &str) -> Self {
        Self {
            id: Uuid::new_v4(),
            entry_type: TerminologyEntryType::Term,
            original: canonical.to_string(),
            replacement: None,
            aliases: aliases.iter().map(|a| a.to_string()).collect(),
            is_enabled: true,
            source: source.to_string(),
            usage_count: 0,
            created_at: String::new(),
        }
    }

    /// The spelling the transcript should converge to.
    pub fn canonical(&self) -> &str {
        match self.entry_type {
            TerminologyEntryType::Term => &self.original,
            TerminologyEntryType::Correction => match &self.replacement {
                Some(replacement) if !replacement.trim().is_empty() => replacement,
                _ => &self.original,
            },
        }
    }

    /// All spellings that should be rewritten to the canonical form.
    pub fn variants(&self) -> Vec<&str> {
        let mut variants: Vec<&str> = Vec::new();
        if self.entry_type == TerminologyEntryType::Correction {
            variants.push(self.original.as_str());
        }
        variants.extend(self.aliases.iter().map(String::as_str));
        variants
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NormalizationResult {
    pub text: String,
    pub applied: bool,
    pub exact_replacement_count: usize,
    pub fuzzy_replacement_count: usize,
}

impl NormalizationResult {
    pub fn unchanged(text: String) -> Self {
        Self {
            text,
            applied: false,
            exact_replacement_count: 0,
            fuzzy_replacement_count: 0,
        }
    }
}

pub trait TranscriptNormalizing: Send + Sync {
    fn normalize(
        &self,
        text: &str,
        imported_entries: &[TerminologyEntry],
        hint_terms: &[String],
    ) -> NormalizationResult;
}

/// Deterministic terminology alignment.
///
/// Two passes, mirroring the Swift engine's observable behavior:
/// 1. exact alias replacement (longest alias first, whole-word for ASCII);
/// 2. spaced-alias fuzzy pass ("Git Hub" → "GitHub", "K 8 s" → "Kubernetes")
///    tolerating spaces between alias tokens.
///
/// After alias alignment the transcript's punctuation width is adjusted per
/// the configured preference, with technical literals (URLs, emails, paths,
/// CLI flags, versions, filenames) protected from conversion.
#[derive(Debug, Default, Clone, Copy)]
pub struct TerminologyNormalizer {
    pub punctuation_preference: TranscriptPunctuationPreference,
}

impl TerminologyNormalizer {
    pub fn new(punctuation_preference: TranscriptPunctuationPreference) -> Self {
        Self {
            punctuation_preference,
        }
    }

    fn replace_exact(text: &str, variant: &str, canonical: &str, count: &mut usize) -> String {
        if variant.is_empty() || variant == canonical {
            return text.to_string();
        }
        let ascii_word = variant.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '.');
        let mut result = String::with_capacity(text.len());
        let mut rest = text;
        loop {
            let Some(found) = rest.to_lowercase().find(&variant.to_lowercase()) else {
                result.push_str(rest);
                break;
            };
            // Map the lowercase byte offset back to the original string. The
            // lowercase mapping is length-preserving for the alphabets we
            // accept in aliases (ASCII + CJK), so the offset is valid.
            let (before, aligned) = rest.split_at(found);
            let matched_len = variant.len();
            if aligned.len() < matched_len || !aligned.is_char_boundary(matched_len) {
                result.push_str(rest);
                break;
            }
            let matched = &aligned[..matched_len];
            let after = &aligned[matched_len..];
            let boundary_ok = if ascii_word {
                // The previous character may live in an earlier chunk already
                // pushed to `result`, so check `result` when `before` is empty.
                let prev_char = before
                    .chars()
                    .next_back()
                    .or_else(|| result.chars().next_back());
                let prev_ok = prev_char.map(|c| !c.is_ascii_alphanumeric()).unwrap_or(true);
                let next_ok = after
                    .chars()
                    .next()
                    .map(|c| !c.is_ascii_alphanumeric())
                    .unwrap_or(true);
                prev_ok && next_ok
            } else {
                true
            };
            result.push_str(before);
            if boundary_ok {
                result.push_str(canonical);
                *count += 1;
            } else {
                result.push_str(matched);
            }
            rest = after;
            if rest.is_empty() {
                break;
            }
        }
        result
    }

    /// Collapses optional spaces between alias tokens: alias "Git Hub" also
    /// matches "git hub" and "Git  Hub"; alias tokens keep word boundaries.
    fn replace_spaced(text: &str, variant: &str, canonical: &str, count: &mut usize) -> String {
        let tokens: Vec<&str> = variant.split_whitespace().collect();
        if tokens.len() < 2 {
            return text.to_string();
        }
        let pattern = tokens
            .iter()
            .map(|t| fancy_regex::escape(t).to_string())
            .collect::<Vec<_>>()
            .join(r"\s*");
        let Ok(regex) = fancy_regex::Regex::new(&format!(r"(?i)\b{pattern}\b")) else {
            return text.to_string();
        };
        let mut replaced = 0usize;
        let result = regex
            .replace_all(text, |_caps: &fancy_regex::Captures| {
                replaced += 1;
                canonical.to_string()
            })
            .to_string();
        *count += replaced;
        result
    }
}

impl TranscriptNormalizing for TerminologyNormalizer {
    fn normalize(
        &self,
        text: &str,
        imported_entries: &[TerminologyEntry],
        hint_terms: &[String],
    ) -> NormalizationResult {
        let mut current = text.to_string();
        let mut exact = 0usize;
        let mut fuzzy = 0usize;

        // Longest variants first so overlapping aliases resolve deterministically.
        let mut jobs: Vec<(String, String)> = Vec::new();
        for entry in imported_entries.iter().filter(|e| e.is_enabled) {
            let canonical = entry.canonical().to_string();
            for variant in entry.variants() {
                let variant = variant.trim();
                if !variant.is_empty() {
                    jobs.push((variant.to_string(), canonical.clone()));
                }
            }
        }
        // Hint terms assert canonical spelling; treat spaced form as alias.
        for hint in hint_terms {
            let hint = hint.trim();
            if hint.is_empty() {
                continue;
            }
            jobs.push((hint.to_string(), hint.to_string()));
        }
        jobs.sort_by(|a, b| b.0.len().cmp(&a.0.len()));

        for (variant, canonical) in &jobs {
            if variant != canonical {
                current = Self::replace_exact(&current, variant, canonical, &mut exact);
            }
            current = Self::replace_spaced(&current, variant, canonical, &mut fuzzy);
        }

        current = punctuation_adjusted_text(&current, self.punctuation_preference);

        let applied = exact > 0 || fuzzy > 0;
        NormalizationResult {
            applied,
            exact_replacement_count: exact,
            fuzzy_replacement_count: fuzzy,
            text: current,
        }
    }
}

// ---------------------------------------------------------------------------
// Punctuation width adjustment (ported from Swift `punctuationAdjustedText`)
// ---------------------------------------------------------------------------

/// Byte ranges of technical literals that punctuation conversion must not
/// touch: URLs, emails, absolute/home paths, CLI flags, versions, filenames.
fn protected_literal_ranges(text: &str) -> Vec<std::ops::Range<usize>> {
    const PATTERNS: [&str; 6] = [
        r"https?://[^\s,，。.!！?？;；:：\)\）\]\】]+",
        r"\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b",
        r"(?<![:/])(?:~|/)[^\s,，。.!！?？;；:：\)\）\]\】]+",
        r"(?<!\S)--?[A-Za-z0-9][A-Za-z0-9-]*",
        r"\bv?\d+(?:\.\d+){1,}\b",
        r"\b[A-Za-z0-9][A-Za-z0-9._-]*\.[A-Za-z0-9][A-Za-z0-9._-]*\b",
    ];
    static COMPILED: std::sync::LazyLock<Vec<fancy_regex::Regex>> =
        std::sync::LazyLock::new(|| {
            PATTERNS
                .iter()
                .map(|p| fancy_regex::Regex::new(p).expect("literal pattern compiles"))
                .collect()
        });
    let mut ranges = Vec::new();
    for regex in COMPILED.iter() {
        for found in regex.find_iter(text).flatten() {
            ranges.push(found.range());
        }
    }
    ranges
}

fn is_protected(offset: usize, ranges: &[std::ops::Range<usize>]) -> bool {
    ranges.iter().any(|range| range.contains(&offset))
}

fn contains_han_characters(text: &str) -> bool {
    text.chars().any(|c| {
        let v = c as u32;
        (0x4E00..=0x9FFF).contains(&v) || (0x3400..=0x4DBF).contains(&v)
    })
}

pub fn punctuation_adjusted_text(
    text: &str,
    preference: TranscriptPunctuationPreference,
) -> String {
    if preference == TranscriptPunctuationPreference::Preserve {
        return text.to_string();
    }
    // Mirror the Swift ordering: technical literals are masked before width
    // conversion (so a path like ./scripts/check.sh can never be half
    // converted), then restored. The regex ranges below remain as a second
    // layer for patterns the tokenizer does not claim.
    let tokenization =
        crate::literal::LiteralTokenizer.tokenize(text, crate::literal::TokenStyle::PrivateUse);
    let converted = match preference {
        TranscriptPunctuationPreference::Automatic => {
            full_width_punctuation_text(&tokenization.masked_text, true)
        }
        TranscriptPunctuationPreference::FullWidth => {
            full_width_punctuation_text(&tokenization.masked_text, false)
        }
        TranscriptPunctuationPreference::HalfWidth => {
            half_width_punctuation_text(&tokenization.masked_text)
        }
        TranscriptPunctuationPreference::Preserve => unreachable!(),
    };
    tokenization
        .restore_literals(&converted, false)
        .unwrap_or_else(|| text.to_string())
}

fn full_width_punctuation_text(text: &str, requires_han: bool) -> String {
    if requires_han && !contains_han_characters(text) {
        return text.to_string();
    }

    let protected = protected_literal_ranges(text);
    let characters: Vec<(usize, char)> = text.char_indices().collect();
    let mut output = String::with_capacity(text.len());

    for (position, &(offset, character)) in characters.iter().enumerate() {
        if is_protected(offset, &protected) {
            output.push(character);
            continue;
        }
        let previous = position.checked_sub(1).map(|i| characters[i].1);
        let next = characters.get(position + 1).map(|&(_, c)| c);
        match full_width_punctuation(character, previous, next) {
            Some(converted) => output.push(converted),
            None => output.push(character),
        }
    }
    output
}

/// Context-aware half→full conversion: separators between digits (3,14 /
/// 3.14 / 12:30) and dots inside identifiers stay half-width.
fn full_width_punctuation(character: char, previous: Option<char>, next: Option<char>) -> Option<char> {
    let both_numeric =
        previous.map(|c| c.is_numeric()).unwrap_or(false) && next.map(|c| c.is_numeric()).unwrap_or(false);
    let both_alphanumeric = previous.map(|c| c.is_ascii_alphanumeric()).unwrap_or(false)
        && next.map(|c| c.is_ascii_alphanumeric()).unwrap_or(false);
    match character {
        ',' if both_numeric => None,
        ',' => Some('，'),
        '.' if both_alphanumeric => None,
        '.' => Some('。'),
        '?' => Some('？'),
        '!' => Some('！'),
        ':' if both_numeric => None,
        ':' => Some('：'),
        ';' => Some('；'),
        '(' => Some('（'),
        ')' => Some('）'),
        '[' => Some('【'),
        ']' => Some('】'),
        _ => None,
    }
}

fn half_width_punctuation_text(text: &str) -> String {
    text.chars()
        .map(|c| match c {
            '，' => ',',
            '。' => '.',
            '？' => '?',
            '！' => '!',
            '：' => ':',
            '；' => ';',
            '（' => '(',
            '）' => ')',
            '【' => '[',
            '】' => ']',
            other => other,
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entries() -> Vec<TerminologyEntry> {
        vec![
            TerminologyEntry::term("GitHub", &["Git Hub"], "starter"),
            TerminologyEntry::term("Kubernetes", &["K8s"], "starter"),
            TerminologyEntry::term("VibeCompose", &["Vibe Compose"], "starter"),
        ]
    }

    #[test]
    fn aligns_exact_aliases() {
        let result =
            TerminologyNormalizer::default().normalize("我在 K8s 上部署", &entries(), &[]);
        assert_eq!(result.text, "我在 Kubernetes 上部署");
        assert!(result.applied);
    }

    #[test]
    fn aligns_spaced_aliases_case_insensitively() {
        let result =
            TerminologyNormalizer::default().normalize("push 到 git hub 上", &entries(), &[]);
        assert_eq!(result.text, "push 到 GitHub 上");
        let result =
            TerminologyNormalizer::default().normalize("用 vibe compose 听写", &entries(), &[]);
        assert_eq!(result.text, "用 VibeCompose 听写");
    }

    #[test]
    fn respects_ascii_word_boundaries() {
        let result =
            TerminologyNormalizer::default().normalize("K8sK8s 不该整体替换", &entries(), &[]);
        assert_eq!(result.text, "K8sK8s 不该整体替换");
    }

    #[test]
    fn correction_entries_rewrite_original_to_replacement() {
        let mut entry = TerminologyEntry::term("原话", &[], "user");
        entry.entry_type = TerminologyEntryType::Correction;
        entry.replacement = Some("正解".to_string());
        let result = TerminologyNormalizer::default().normalize("这里是原话表述", &[entry], &[]);
        assert_eq!(result.text, "这里是正解表述");
    }

    #[test]
    fn untouched_text_reports_unapplied() {
        let result = TerminologyNormalizer::default().normalize("没有任何术语", &entries(), &[]);
        assert!(!result.applied);
        assert_eq!(result.exact_replacement_count, 0);
    }

    // -- punctuation width --------------------------------------------------

    #[test]
    fn automatic_converts_to_full_width_only_when_han_present() {
        let normalizer = TerminologyNormalizer::default();
        let mixed = normalizer.normalize("今天下雨,记得带伞.", &[], &[]);
        assert_eq!(mixed.text, "今天下雨，记得带伞。");
        let english = normalizer.normalize("It rains today, bring an umbrella.", &[], &[]);
        assert_eq!(english.text, "It rains today, bring an umbrella.");
    }

    #[test]
    fn full_width_preference_converts_pure_english_too() {
        let normalizer =
            TerminologyNormalizer::new(TranscriptPunctuationPreference::FullWidth);
        let result = normalizer.normalize("Hello, world!", &[], &[]);
        assert_eq!(result.text, "Hello， world！");
    }

    #[test]
    fn half_width_preference_converts_full_width_marks() {
        let normalizer =
            TerminologyNormalizer::new(TranscriptPunctuationPreference::HalfWidth);
        let result = normalizer.normalize("你好，世界！（测试）", &[], &[]);
        assert_eq!(result.text, "你好,世界!(测试)");
    }

    #[test]
    fn preserve_preference_keeps_widths() {
        let normalizer =
            TerminologyNormalizer::new(TranscriptPunctuationPreference::Preserve);
        let result = normalizer.normalize("你好,世界，混合!", &[], &[]);
        assert_eq!(result.text, "你好,世界，混合!");
    }

    #[test]
    fn numeric_and_identifier_separators_stay_half_width() {
        let normalizer = TerminologyNormalizer::default();
        let result = normalizer.normalize("圆周率是3.14,时间12:30,共1,000个.", &[], &[]);
        assert_eq!(result.text, "圆周率是3.14，时间12:30，共1,000个。");
    }

    #[test]
    fn technical_literals_are_protected_from_conversion() {
        let normalizer = TerminologyNormalizer::default();
        let result = normalizer.normalize(
            "看这个链接 https://example.com/a?b=1 还有邮箱 a.b@test.io,以及 ./scripts/check.sh,版本 v1.2.3,文件 main.rs,好吗?",
            &[],
            &[],
        );
        assert!(result.text.contains("https://example.com/a?b=1"));
        assert!(result.text.contains("a.b@test.io"));
        assert!(result.text.contains("./scripts/check.sh"));
        assert!(result.text.contains("v1.2.3"));
        assert!(result.text.contains("main.rs"));
        assert!(result.text.ends_with("好吗？"));
    }
}
