//! Technical literal protection, ported from Swift `TechnicalLiteralTokenizer`.
//!
//! Before AI Polish rewrites a transcript, technical literals (URLs, paths,
//! commands, versions, identifiers, code spans) are replaced by placeholder
//! tokens. After the model responds, every token must appear exactly once so
//! literals can be restored unchanged; otherwise the pipeline falls back to
//! the normalized transcript.

use std::collections::HashMap;
use std::sync::LazyLock;

use fancy_regex::Regex;

/// Regex patterns matching protected technical literals. Order matters only
/// for overlap merging; all matches are merged into disjoint ranges.
static PATTERNS: LazyLock<Vec<Regex>> = LazyLock::new(|| {
    [
        // Fenced code blocks and inline code spans.
        r"(?s:```.*?```)",
        r"`[^`\r\n]+`",
        // URLs and e-mail addresses.
        r#"(?i)\b(?:https?|ftp)://[^\s<>{}\[\]"'，。！？；：]+"#,
        r"\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b",
        // POSIX and Windows paths.
        r#"(?<![\w])(?:~|/|\./|\.\./)[^\s<>{}\[\]"'，。！？；：]+"#,
        r#"\b[A-Za-z]:\\(?:[^\\\s<>:"|?*，。！？；：]+\\)*[^\\\s<>:"|?*，。！？；：]*"#,
        // Command flags and environment variables.
        r"(?<!\S)--?[A-Za-z0-9][A-Za-z0-9-]*(?:=[^\s，。！？；：]+)?",
        r"\$\{[A-Za-z_][A-Za-z0-9_]*\}|\$[A-Za-z_][A-Za-z0-9_]*",
        // Versions, IPs, UUIDs, hashes.
        r"\bv?\d+(?:\.\d+){1,}(?:[-+][A-Za-z0-9.-]+)?\b",
        r"\b(?:\d{1,3}\.){3}\d{1,3}(?::\d{1,5})?\b",
        r"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b",
        r"\b(?:sha(?:1|224|256|384|512):)?[0-9A-Fa-f]{32,128}\b",
        // Filenames with extensions, optionally scoped (pkg/name.ext).
        r"(?<![\w])[@A-Za-z0-9_+.-]+(?:/[@A-Za-z0-9_+.-]+)?\.[A-Za-z0-9]{1,16}(?![\w])",
        // Code symbols: Namespace::symbol, dotted.call(), function(args).
        r"\b[A-Za-z_][A-Za-z0-9_.]*(?:::?[A-Za-z_][A-Za-z0-9_]*|\([^()\r\n]*\))",
    ]
    .iter()
    .map(|p| Regex::new(p).expect("literal pattern must compile"))
    .collect()
});

const TRAILING_PUNCTUATION: &[char] = &[
    '.', ',', '!', '?', ';', ':', '，', '。', '！', '？', '；', '：',
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TokenStyle {
    /// Unicode private-use scalars, for local-only normalization.
    PrivateUse,
    /// Visible bracketed tokens the model is instructed to preserve.
    ModelSafe,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Tokenization {
    pub masked_text: String,
    pub literals: Vec<String>,
    replacements: HashMap<String, String>,
}

impl Tokenization {
    pub fn passthrough(text: &str) -> Self {
        Self {
            masked_text: text.to_string(),
            literals: Vec::new(),
            replacements: HashMap::new(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.replacements.is_empty()
    }

    /// Restores literals in the model output. When `require_exactly_once` is
    /// set, every placeholder must occur exactly once or restoration fails.
    pub fn restore_literals(&self, candidate: &str, require_exactly_once: bool) -> Option<String> {
        if require_exactly_once {
            for token in self.replacements.keys() {
                if candidate.split(token.as_str()).count() != 2 {
                    return None;
                }
            }
        }
        let mut text = candidate.to_string();
        for (token, literal) in &self.replacements {
            text = text.replace(token.as_str(), literal);
        }
        Some(text)
    }
}

#[derive(Debug, Default, Clone, Copy)]
pub struct LiteralTokenizer;

impl LiteralTokenizer {
    pub fn tokenize(&self, text: &str, style: TokenStyle) -> Tokenization {
        let ranges = self.protected_ranges(text);
        if ranges.is_empty() {
            return Tokenization::passthrough(text);
        }

        let mut masked = text.to_string();
        let mut literals = vec![String::new(); ranges.len()];
        let mut replacements: HashMap<String, String> = HashMap::new();

        for (index, range) in ranges.iter().enumerate().rev() {
            let literal = masked[range.clone()].to_string();
            let token = unique_token(index, style, text, &replacements);
            literals[index] = literal.clone();
            replacements.insert(token.clone(), literal);
            masked.replace_range(range.clone(), &token);
        }

        Tokenization {
            masked_text: masked,
            literals: literals.into_iter().filter(|l| !l.is_empty()).collect(),
            replacements,
        }
    }

    /// Byte ranges of protected literals, merged and trimmed of trailing
    /// sentence punctuation.
    pub fn protected_ranges(&self, text: &str) -> Vec<std::ops::Range<usize>> {
        let mut matches: Vec<std::ops::Range<usize>> = Vec::new();
        for regex in PATTERNS.iter() {
            for found in regex.find_iter(text).flatten() {
                let trimmed = trim_trailing_punctuation(text, found.start()..found.end());
                if !trimmed.is_empty() {
                    matches.push(trimmed);
                }
            }
        }
        matches.sort_by(|a, b| a.start.cmp(&b.start).then(b.end.cmp(&a.end)));

        let mut merged: Vec<std::ops::Range<usize>> = Vec::new();
        for range in matches {
            match merged.last_mut() {
                Some(last) if range.start < last.end => {
                    if range.end > last.end {
                        last.end = range.end;
                    }
                }
                _ => merged.push(range),
            }
        }
        merged
    }
}

fn trim_trailing_punctuation(text: &str, mut range: std::ops::Range<usize>) -> std::ops::Range<usize> {
    while range.start < range.end {
        let slice = &text[range.clone()];
        match slice.chars().next_back() {
            Some(c) if TRAILING_PUNCTUATION.contains(&c) => {
                range.end -= c.len_utf8();
            }
            _ => break,
        }
    }
    range
}

fn unique_token(
    index: usize,
    style: TokenStyle,
    original_text: &str,
    existing: &HashMap<String, String>,
) -> String {
    let mut candidate_index = index;
    loop {
        let candidate = match style {
            TokenStyle::PrivateUse => {
                let scalar = 0xF0000 + candidate_index as u32;
                char::from_u32(scalar)
                    .map(|c| c.to_string())
                    .unwrap_or_else(|| "\u{F0000}".to_string())
            }
            TokenStyle::ModelSafe => format!("⟪OW_LITERAL_{candidate_index:04}⟫"),
        };
        if !original_text.contains(&candidate) && !existing.contains_key(&candidate) {
            return candidate;
        }
        candidate_index += 1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn roundtrip(text: &str) {
        let tokenization = LiteralTokenizer.tokenize(text, TokenStyle::ModelSafe);
        let restored = tokenization
            .restore_literals(&tokenization.masked_text, true)
            .expect("masked text must restore");
        assert_eq!(restored, text);
    }

    #[test]
    fn protects_urls_paths_and_versions() {
        let text = "部署 https://api.example.com/v2 时先跑 ./scripts/check.sh，版本是 1.2.3。";
        let tokenization = LiteralTokenizer.tokenize(text, TokenStyle::ModelSafe);
        assert!(tokenization.literals.iter().any(|l| l.contains("https://api.example.com/v2")));
        assert!(tokenization.literals.iter().any(|l| l.contains("./scripts/check.sh")));
        assert!(tokenization.literals.iter().any(|l| l == "1.2.3"));
        roundtrip(text);
    }

    #[test]
    fn protects_flags_env_vars_and_emails() {
        let text = "运行 cargo build --release，设置 $HOME 并邮件 dev@example.com";
        let tokenization = LiteralTokenizer.tokenize(text, TokenStyle::ModelSafe);
        assert!(tokenization.literals.iter().any(|l| l == "--release"));
        assert!(tokenization.literals.iter().any(|l| l == "$HOME"));
        assert!(tokenization.literals.iter().any(|l| l == "dev@example.com"));
        roundtrip(text);
    }

    #[test]
    fn protects_code_spans_and_symbols() {
        let text = "调用 `foo.bar()` 和 std::mem::swap 再看 config.json 文件";
        let tokenization = LiteralTokenizer.tokenize(text, TokenStyle::ModelSafe);
        assert!(tokenization.literals.iter().any(|l| l == "`foo.bar()`"));
        assert!(tokenization.literals.iter().any(|l| l.contains("std::mem")));
        assert!(tokenization.literals.iter().any(|l| l == "config.json"));
        roundtrip(text);
    }

    #[test]
    fn restore_fails_when_token_deleted_or_duplicated() {
        let text = "看 https://example.com 的文档";
        let tokenization = LiteralTokenizer.tokenize(text, TokenStyle::ModelSafe);
        assert!(tokenization.restore_literals("重写后没有令牌", true).is_none());
        let duplicated = format!(
            "{} {}",
            tokenization.masked_text, tokenization.masked_text
        );
        assert!(tokenization.restore_literals(&duplicated, true).is_none());
    }

    #[test]
    fn passthrough_when_no_literals() {
        let tokenization = LiteralTokenizer.tokenize("今天天气不错", TokenStyle::ModelSafe);
        assert!(tokenization.is_empty());
        assert_eq!(tokenization.masked_text, "今天天气不错");
    }
}
