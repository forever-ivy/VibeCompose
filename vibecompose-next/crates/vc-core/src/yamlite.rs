//! Restricted YAML subset parser, ported from the Swift `RestrictedYAMLDocument`.
//!
//! Community Skill files are untrusted input. Instead of pulling a full YAML
//! implementation (anchors, tags, merge keys and other attack surface), the
//! runtime accepts only the constrained subset that Skill packages are allowed
//! to use: two indentation levels, scalars, string lists, and literal/folded
//! block scalars.

use std::collections::BTreeMap;

use thiserror::Error;

const MAX_BYTES: usize = 96 * 1024;
const MAX_LINES: usize = 1500;
const MAX_BLOCK_SCALAR_CHARS: usize = 16_000;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum YamlError {
    #[error("tabs, YAML tags, and oversized documents are not supported")]
    UnsupportedDocument,
    #[error("too many YAML lines")]
    TooManyLines,
    #[error("invalid indentation on line {0}")]
    InvalidIndentation(usize),
    #[error("unexpected list on line {0}")]
    UnexpectedList(usize),
    #[error("missing ':' on line {0}")]
    MissingColon(usize),
    #[error("invalid key on line {0}")]
    InvalidKey(usize),
    #[error("YAML anchors, aliases, and tags are not supported")]
    UnsupportedValue,
    #[error("unknown key {0}")]
    UnknownRoot(String),
    #[error("orphan key on line {0}")]
    OrphanKey(usize),
    #[error("duplicate key {0}")]
    DuplicateKey(String),
    #[error("unterminated quoted list value")]
    UnterminatedQuote,
}

/// Flattened restricted YAML document. Nested keys use `root.child` paths.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct RestrictedYamlDocument {
    pub scalars: BTreeMap<String, String>,
    pub lists: BTreeMap<String, Vec<String>>,
}

impl RestrictedYamlDocument {
    pub fn scalar(&self, key: &str) -> Option<&str> {
        self.scalars.get(key).map(String::as_str)
    }

    pub fn list(&self, key: &str) -> &[String] {
        self.lists.get(key).map(Vec::as_slice).unwrap_or(&[])
    }

    pub fn paths(&self) -> impl Iterator<Item = &str> {
        self.scalars.keys().chain(self.lists.keys()).map(String::as_str)
    }

    pub fn parse(
        text: &str,
        allowed_roots: &[&str],
        preserve_unknown_roots: bool,
    ) -> Result<Self, YamlError> {
        if text.len() > MAX_BYTES || text.contains('\t') || text.contains("!!") || text.contains("!<")
        {
            return Err(YamlError::UnsupportedDocument);
        }
        let lines: Vec<&str> = text.split('\n').collect();
        if lines.len() > MAX_LINES {
            return Err(YamlError::TooManyLines);
        }

        let mut doc = RestrictedYamlDocument::default();
        let mut root: Option<String> = None;
        let mut list_path: Option<String> = None;
        let mut block: Option<BlockScalar> = None;

        for (index, raw_line) in lines.iter().enumerate() {
            let line_no = index + 1;
            let indent = raw_line.chars().take_while(|c| *c == ' ').count();
            let trimmed = raw_line.trim();

            if let Some(active) = block.as_mut() {
                if trimmed.is_empty() {
                    active.lines.push(String::new());
                    continue;
                }
                if indent >= active.indent {
                    let cut: String = raw_line.chars().skip(active.indent).collect();
                    active.lines.push(cut);
                    continue;
                }
                flush_block(&mut doc, block.take())?;
            }

            if trimmed.is_empty() || trimmed.starts_with('#') {
                continue;
            }
            if indent != 0 && indent != 2 {
                return Err(YamlError::InvalidIndentation(line_no));
            }
            if let Some(item) = trimmed.strip_prefix("- ") {
                let Some(path) = list_path.as_ref() else {
                    return Err(YamlError::UnexpectedList(line_no));
                };
                if indent != 2 {
                    return Err(YamlError::UnexpectedList(line_no));
                }
                doc.lists
                    .entry(path.clone())
                    .or_default()
                    .push(clean_scalar(item));
                continue;
            }
            let Some(separator) = trimmed.find(':') else {
                return Err(YamlError::MissingColon(line_no));
            };
            let key = trimmed[..separator].trim();
            if !is_valid_key(key) {
                return Err(YamlError::InvalidKey(line_no));
            }
            let value = trimmed[separator + 1..].trim();
            if value.starts_with('&') || value.starts_with('*') || value.starts_with('!') {
                return Err(YamlError::UnsupportedValue);
            }

            let path = if indent == 0 {
                if !allowed_roots.contains(&key) && !preserve_unknown_roots {
                    return Err(YamlError::UnknownRoot(key.to_string()));
                }
                root = if value.is_empty() {
                    Some(key.to_string())
                } else {
                    None
                };
                key.to_string()
            } else {
                let Some(root) = root.as_ref() else {
                    return Err(YamlError::OrphanKey(line_no));
                };
                format!("{root}.{key}")
            };
            if doc.scalars.contains_key(&path) || doc.lists.contains_key(&path) {
                return Err(YamlError::DuplicateKey(path));
            }

            if value == "|" || value == ">" {
                block = Some(BlockScalar {
                    path,
                    indent: indent + 2,
                    folded: value == ">",
                    lines: Vec::new(),
                });
                list_path = None;
            } else if value.starts_with('[') && value.ends_with(']') {
                let inner = &value[1..value.len() - 1];
                doc.lists.insert(path.clone(), inline_list(inner)?);
                list_path = Some(path);
            } else if value.is_empty() {
                list_path = Some(path);
            } else {
                doc.scalars.insert(path, clean_scalar(value));
                list_path = None;
            }
        }
        flush_block(&mut doc, block.take())?;
        Ok(doc)
    }
}

struct BlockScalar {
    path: String,
    indent: usize,
    folded: bool,
    lines: Vec<String>,
}

fn flush_block(doc: &mut RestrictedYamlDocument, block: Option<BlockScalar>) -> Result<(), YamlError> {
    let Some(mut block) = block else {
        return Ok(());
    };
    while block.lines.last().is_some_and(|line| line.is_empty()) {
        block.lines.pop();
    }
    let joined = if block.folded {
        block.lines.join(" ")
    } else {
        block.lines.join("\n")
    };
    if doc.scalars.contains_key(&block.path) || doc.lists.contains_key(&block.path) {
        return Err(YamlError::DuplicateKey(block.path));
    }
    let clipped: String = joined.chars().take(MAX_BLOCK_SCALAR_CHARS).collect();
    doc.scalars.insert(block.path, clipped);
    Ok(())
}

fn is_valid_key(key: &str) -> bool {
    let mut chars = key.chars();
    match chars.next() {
        Some(c) if c.is_ascii_alphabetic() => {}
        _ => return false,
    }
    chars.all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '-'))
}

fn clean_scalar(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.chars().count() < 2 {
        return trimmed.to_string();
    }
    if trimmed.starts_with('"') && trimmed.ends_with('"') {
        if let Ok(decoded) = serde_json::from_str::<String>(trimmed) {
            return decoded;
        }
        return trimmed[1..trimmed.len() - 1].to_string();
    }
    if trimmed.starts_with('\'') && trimmed.ends_with('\'') {
        return trimmed[1..trimmed.len() - 1].replace("''", "'");
    }
    trimmed.to_string()
}

fn inline_list(inner: &str) -> Result<Vec<String>, YamlError> {
    let mut values = Vec::new();
    let mut current = String::new();
    let mut quote: Option<char> = None;
    let mut escaped = false;
    for character in inner.chars() {
        if escaped {
            current.push(character);
            escaped = false;
            continue;
        }
        if character == '\\' && quote == Some('"') {
            current.push(character);
            escaped = true;
            continue;
        }
        if character == '"' || character == '\'' {
            match quote {
                None => quote = Some(character),
                Some(open) if open == character => quote = None,
                Some(_) => {}
            }
            current.push(character);
            continue;
        }
        if character == ',' && quote.is_none() {
            values.push(clean_scalar(&current));
            current.clear();
        } else {
            current.push(character);
        }
    }
    if quote.is_some() || escaped {
        return Err(YamlError::UnterminatedQuote);
    }
    if !current.trim().is_empty() {
        values.push(clean_scalar(&current));
    }
    Ok(values)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_two_level_document() {
        let doc = RestrictedYamlDocument::parse(
            "context:\n  required:\n  - voice\noutput:\n  format: plainText\n  risk: low\n",
            &["context", "output"],
            false,
        )
        .unwrap();
        assert_eq!(doc.list("context.required"), ["voice"]);
        assert_eq!(doc.scalar("output.format"), Some("plainText"));
        assert_eq!(doc.scalar("output.risk"), Some("low"));
    }

    #[test]
    fn rejects_tabs_tags_and_anchors() {
        assert!(RestrictedYamlDocument::parse("a:\tb", &["a"], false).is_err());
        assert!(RestrictedYamlDocument::parse("a: !!str x", &["a"], false).is_err());
        assert!(RestrictedYamlDocument::parse("a: &anchor x", &["a"], false).is_err());
        assert!(RestrictedYamlDocument::parse("a: *alias", &["a"], false).is_err());
    }

    #[test]
    fn rejects_duplicate_and_unknown_keys() {
        assert_eq!(
            RestrictedYamlDocument::parse("a: 1\na: 2", &["a"], false),
            Err(YamlError::DuplicateKey("a".into()))
        );
        assert_eq!(
            RestrictedYamlDocument::parse("b: 1", &["a"], false),
            Err(YamlError::UnknownRoot("b".into()))
        );
        assert!(RestrictedYamlDocument::parse("b: 1", &["a"], true).is_ok());
    }

    #[test]
    fn parses_quoted_scalars_and_inline_lists() {
        let doc = RestrictedYamlDocument::parse(
            "metadata:\n  version: \"1.2.0\"\n  title: 'it''s'\ntags: [a, \"b,c\", d]\n",
            &["metadata", "tags"],
            false,
        )
        .unwrap();
        assert_eq!(doc.scalar("metadata.version"), Some("1.2.0"));
        assert_eq!(doc.scalar("metadata.title"), Some("it's"));
        assert_eq!(doc.list("tags"), ["a", "b,c", "d"]);
    }

    #[test]
    fn parses_literal_and_folded_blocks() {
        let doc = RestrictedYamlDocument::parse(
            "description: |\n  line one\n  line two\nsummary: >\n  fold one\n  fold two\n",
            &["description", "summary"],
            false,
        )
        .unwrap();
        assert_eq!(doc.scalar("description"), Some("line one\nline two"));
        assert_eq!(doc.scalar("summary"), Some("fold one fold two"));
    }
}
