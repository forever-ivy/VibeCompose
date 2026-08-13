//! Shared context-extraction helpers, platform-independent and unit-tested
//! everywhere. Platform backends supply raw element text; this module turns
//! it into the bounded snippets the prompt compiler accepts.

/// Extracts the paragraph nearest the insertion point. The backends cannot
/// report the caret offset reliably, so the last non-empty paragraph stands
/// in for "the paragraph being written" — dictation inserts at the end of
/// what the user is typing. Output is trimmed and bounded to `max_chars`
/// (tail-biased: keep the newest text when the paragraph is oversized).
pub fn trailing_paragraph(text: &str, max_chars: usize) -> Option<String> {
    if max_chars == 0 {
        return None;
    }
    let paragraph = text
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .next_back()?;

    let chars: Vec<char> = paragraph.chars().collect();
    let clipped: String = if chars.len() > max_chars {
        chars[chars.len() - max_chars..].iter().collect()
    } else {
        paragraph.to_string()
    };
    Some(clipped)
}

/// Bounds a captured snippet to `max_chars` (head-biased for selections and
/// clipboard text, whose beginning carries the intent).
pub fn clipped_snippet(text: &str, max_chars: usize) -> Option<String> {
    let trimmed = text.trim();
    if trimmed.is_empty() || max_chars == 0 {
        return None;
    }
    Some(trimmed.chars().take(max_chars).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn trailing_paragraph_picks_the_last_non_empty_block() {
        let text = "第一段。\n\n第二段还在写";
        assert_eq!(trailing_paragraph(text, 100).as_deref(), Some("第二段还在写"));
        assert_eq!(
            trailing_paragraph("单行\n\n\n  \n", 100).as_deref(),
            Some("单行")
        );
        assert_eq!(trailing_paragraph("", 100), None);
        assert_eq!(trailing_paragraph("   \n \n", 100), None);
    }

    #[test]
    fn trailing_paragraph_is_tail_biased_when_oversized() {
        let text = format!("{}尾部", "头".repeat(100));
        let clipped = trailing_paragraph(&text, 10).unwrap();
        assert_eq!(clipped.chars().count(), 10);
        assert!(clipped.ends_with("尾部"));
    }

    #[test]
    fn clipped_snippet_is_head_biased_and_rejects_blank() {
        assert_eq!(clipped_snippet("  hello world  ", 5).as_deref(), Some("hello"));
        assert_eq!(clipped_snippet("   ", 5), None);
        assert_eq!(clipped_snippet("text", 0), None);
    }
}
