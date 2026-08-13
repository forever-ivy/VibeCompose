//! Transcription prompt: instructions sent alongside the audio upload
//! (multipart `prompt` field) steering cleanup, punctuation width, and term
//! spelling. Ported from Swift `TranscriptionPromptBuilder`.

use crate::config::TranscriptPunctuationPreference;

pub const MAX_HINT_TERMS: usize = 24;
pub const MAX_HINT_CHARACTERS: usize = 400;

#[derive(Debug, Clone, Copy, Default)]
pub struct TranscriptionPromptBuilder;

impl TranscriptionPromptBuilder {
    pub fn build_prompt(
        &self,
        hint_terms: &[String],
        speech_cleanup_enabled: bool,
        punctuation_preference: TranscriptPunctuationPreference,
        locale: &str,
    ) -> String {
        let hints = clipped_hint_terms(hint_terms);

        let mut lines: Vec<String> = vec![
            "Transcribe this speech into text that can be pasted directly.".into(),
            "Add natural punctuation and sentence breaks, but do not rewrite meaning.".into(),
            "Preserve the speaker's language exactly. If they spoke Chinese, keep Chinese (including the original simplified/traditional form). If they spoke English or another language, keep that language. Do not translate.".into(),
            "Keep mixed-language phrases as spoken.".into(),
            punctuation_instruction(punctuation_preference).into(),
            "Do not alter filenames, version numbers, paths, URLs, emails, product names, commands, or parameter names.".into(),
            "Do not treat system UI, placeholder text, or button labels as spoken content.".into(),
            "Prefer correct spellings for terms, acronyms, and brand names.".into(),
            "Return only the final transcript text.".into(),
            format!("Locale: {locale}"),
        ];

        if speech_cleanup_enabled {
            lines.insert(
                2,
                "Remove filler words, meaningless repeats, hesitation sounds, and mid-sentence self-corrections; keep only the final intended wording.".into(),
            );
            lines.insert(
                3,
                "If the speaker dictates a list, steps, or bullet points, use concise line breaks or bullets without expanding the content.".into(),
            );
        }

        if !hints.is_empty() {
            lines.push("Pay special attention to these terms:".into());
            lines.extend(hints.iter().map(|term| format!("- {term}")));
        }

        lines.join("\n")
    }
}

fn punctuation_instruction(preference: TranscriptPunctuationPreference) -> &'static str {
    match preference {
        TranscriptPunctuationPreference::Automatic => {
            "Choose punctuation style from the language of each phrase: full-width for Chinese runs, half-width for pure English runs."
        }
        TranscriptPunctuationPreference::FullWidth => "Use Chinese full-width punctuation.",
        TranscriptPunctuationPreference::HalfWidth => "Use ASCII half-width punctuation.",
        TranscriptPunctuationPreference::Preserve => {
            "Preserve the transcript's original punctuation width; do not convert full-width and half-width forms."
        }
    }
}

/// Deduplicates (case-insensitively) and bounds hint terms: at most
/// [`MAX_HINT_TERMS`] entries within a [`MAX_HINT_CHARACTERS`] total budget.
/// The Swift original also folds diacritics; lowercase folding is the
/// portable approximation.
fn clipped_hint_terms(terms: &[String]) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    let mut output = Vec::new();
    let mut total_characters = 0usize;

    for term in terms {
        let trimmed = term.trim();
        if trimmed.is_empty() {
            continue;
        }
        if !seen.insert(trimmed.to_lowercase()) {
            continue;
        }
        let projected = total_characters + trimmed.chars().count();
        if projected > MAX_HINT_CHARACTERS {
            break;
        }
        total_characters = projected;
        output.push(trimmed.to_string());
        if output.len() >= MAX_HINT_TERMS {
            break;
        }
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cleanup_lines_are_inserted_only_when_enabled() {
        let with_cleanup = TranscriptionPromptBuilder.build_prompt(
            &[],
            true,
            TranscriptPunctuationPreference::Automatic,
            "zh-CN",
        );
        assert!(with_cleanup.contains("Remove filler words"));
        assert!(with_cleanup.contains("bullet points"));

        let without_cleanup = TranscriptionPromptBuilder.build_prompt(
            &[],
            false,
            TranscriptPunctuationPreference::Automatic,
            "zh-CN",
        );
        assert!(!without_cleanup.contains("Remove filler words"));
    }

    #[test]
    fn punctuation_preference_changes_the_instruction() {
        let full = TranscriptionPromptBuilder.build_prompt(
            &[],
            true,
            TranscriptPunctuationPreference::FullWidth,
            "zh-CN",
        );
        assert!(full.contains("Use Chinese full-width punctuation."));
        let preserve = TranscriptionPromptBuilder.build_prompt(
            &[],
            true,
            TranscriptPunctuationPreference::Preserve,
            "zh-CN",
        );
        assert!(preserve.contains("do not convert full-width and half-width forms"));
    }

    #[test]
    fn hint_terms_are_deduplicated_and_bounded() {
        let terms = vec![
            " VibeCompose ".to_string(),
            "vibecompose".to_string(),
            "Kubernetes".to_string(),
            "".to_string(),
        ];
        let prompt = TranscriptionPromptBuilder.build_prompt(
            &terms,
            true,
            TranscriptPunctuationPreference::Automatic,
            "zh-CN",
        );
        assert!(prompt.contains("Pay special attention to these terms:"));
        assert_eq!(prompt.matches("- VibeCompose").count(), 1);
        assert!(prompt.contains("- Kubernetes"));

        let many: Vec<String> = (0..40).map(|i| format!("term-{i}")).collect();
        assert_eq!(clipped_hint_terms(&many).len(), MAX_HINT_TERMS);

        let long = vec!["x".repeat(500)];
        assert!(clipped_hint_terms(&long).is_empty());
    }

    #[test]
    fn locale_is_appended() {
        let prompt = TranscriptionPromptBuilder.build_prompt(
            &[],
            true,
            TranscriptPunctuationPreference::Automatic,
            "en-US",
        );
        assert!(prompt.contains("Locale: en-US"));
    }
}
