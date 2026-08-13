//! AI Polish decision engine and provider traits.
//! Ported from Swift `TextPolishDecisionEngine` / `TextPolisher` interfaces.
//! The decision reason is a bounded enum recorded in telemetry; transcript
//! text is never retained by the decision itself.

use serde::{Deserialize, Serialize};

use crate::skill::DictationMode;
use crate::terminology::TerminologyEntry;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum TextPolishMode {
    #[default]
    AutomaticWhenKeyAvailable,
    Disabled,
    Always,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TextPolishProviderId {
    ChatGptAuth,
    OpenAiCompatible,
}

/// Stable telemetry reasons; raw values match the Swift implementation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TextPolishDecisionReason {
    #[serde(rename = "disabled")]
    Disabled,
    #[serde(rename = "provider_unavailable")]
    ProviderUnavailable,
    #[serde(rename = "forced_always")]
    ForcedAlways,
    #[serde(rename = "skip_short_direct")]
    SkipShortDirect,
    #[serde(rename = "skip_low_complexity")]
    SkipLowComplexity,
    #[serde(rename = "run_reply")]
    RunReply,
    #[serde(rename = "run_email")]
    RunEmail,
    #[serde(rename = "run_agent_plan")]
    RunAgentPlan,
    #[serde(rename = "run_code_prompt")]
    RunCodePrompt,
    #[serde(rename = "run_translation")]
    RunTranslation,
    #[serde(rename = "run_self_correction")]
    RunSelfCorrection,
    #[serde(rename = "run_long_dictation")]
    RunLongDictation,
    #[serde(rename = "run_complex_dictation")]
    RunComplexDictation,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TextPolishDecision {
    pub should_polish: bool,
    pub reason: TextPolishDecisionReason,
}

#[derive(Debug, Clone, Copy, Default)]
pub struct TextPolishDecisionEngine;

impl TextPolishDecisionEngine {
    pub fn decide(
        &self,
        normalized_text: &str,
        audio_duration_ms: i64,
        mode: DictationMode,
        polish_mode: TextPolishMode,
        provider_available: bool,
    ) -> TextPolishDecision {
        use TextPolishDecisionReason as Reason;
        if polish_mode == TextPolishMode::Disabled {
            return TextPolishDecision {
                should_polish: false,
                reason: Reason::Disabled,
            };
        }
        if !provider_available {
            return TextPolishDecision {
                should_polish: false,
                reason: Reason::ProviderUnavailable,
            };
        }
        if polish_mode == TextPolishMode::Always {
            return TextPolishDecision {
                should_polish: true,
                reason: Reason::ForcedAlways,
            };
        }

        match mode {
            DictationMode::Reply => {
                return TextPolishDecision {
                    should_polish: true,
                    reason: Reason::RunReply,
                }
            }
            DictationMode::Email => {
                return TextPolishDecision {
                    should_polish: true,
                    reason: Reason::RunEmail,
                }
            }
            DictationMode::CodePrompt => {
                return TextPolishDecision {
                    should_polish: true,
                    reason: Reason::RunCodePrompt,
                }
            }
            DictationMode::Translate => {
                return TextPolishDecision {
                    should_polish: true,
                    reason: Reason::RunTranslation,
                }
            }
            DictationMode::Direct => {}
        }

        let normalized = normalized_text.trim();
        let folded = normalized.to_lowercase();

        if contains_any(
            &folded,
            &["翻译成", "译成", "翻成", "translate into", "translate to", "translation"],
        ) {
            return TextPolishDecision {
                should_polish: true,
                reason: Reason::RunTranslation,
            };
        }
        if contains_any(
            &folded,
            &[
                "写封邮件",
                "写一封邮件",
                "发个邮件",
                "发一封邮件",
                "邮件主题",
                "收件人",
                "email",
                "subject line",
            ],
        ) {
            return TextPolishDecision {
                should_polish: true,
                reason: Reason::RunEmail,
            };
        }
        if contains_any(
            &folded,
            &[
                "不对",
                "改成",
                "更正",
                "应该说",
                "我的意思是",
                "后面为准",
                "后面的为准",
                "刚才说错",
                "actually",
                "correction",
                "i mean",
            ],
        ) {
            return TextPolishDecision {
                should_polish: true,
                reason: Reason::RunSelfCorrection,
            };
        }
        if has_structured_intent(&folded) {
            return TextPolishDecision {
                should_polish: true,
                reason: Reason::RunAgentPlan,
            };
        }

        let duration = audio_duration_ms.max(0);
        if duration > 20_000 {
            return TextPolishDecision {
                should_polish: true,
                reason: Reason::RunLongDictation,
            };
        }

        let character_count = meaningful_character_count(normalized);
        if complexity_score(normalized, duration, character_count) >= 3 {
            return TextPolishDecision {
                should_polish: true,
                reason: Reason::RunComplexDictation,
            };
        }
        if duration <= 10_000 && character_count <= 80 {
            return TextPolishDecision {
                should_polish: false,
                reason: Reason::SkipShortDirect,
            };
        }
        TextPolishDecision {
            should_polish: false,
            reason: Reason::SkipLowComplexity,
        }
    }
}

fn has_structured_intent(text: &str) -> bool {
    contains_any(
        text,
        &[
            "整理成",
            "分点",
            "列成",
            "步骤",
            "第一",
            "第二",
            "第三",
            "目标",
            "约束",
            "验收",
            "待办",
            "实施计划",
            "agent plan",
            "bullet",
            "steps",
            "requirements",
            "acceptance criteria",
        ],
    )
}

fn complexity_score(text: &str, duration_ms: i64, character_count: usize) -> i32 {
    let mut score = 0;
    if duration_ms >= 10_000 {
        score += 1;
    }
    if duration_ms >= 15_000 {
        score += 1;
    }
    if character_count >= 80 {
        score += 1;
    }
    if character_count >= 140 {
        score += 1;
    }
    if sentence_terminator_count(text) >= 3 {
        score += 1;
    }
    if text.contains("\n- ") || text.contains("\n• ") || text.contains("\n1.") || text.contains("\n1、")
    {
        score += 2;
    }
    score
}

fn contains_any(text: &str, phrases: &[&str]) -> bool {
    phrases.iter().any(|phrase| text.contains(phrase))
}

pub(crate) fn meaningful_character_count(text: &str) -> usize {
    text.chars().filter(|c| !c.is_whitespace()).count()
}

pub(crate) fn sentence_terminator_count(text: &str) -> usize {
    text.chars()
        .filter(|c| "。！？!?；;\n".contains(*c))
        .count()
}

/// A completed polish response.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PolishedText {
    pub text: String,
    pub provider: TextPolishProviderId,
    pub estimated_input_tokens: u32,
    pub estimated_output_tokens: u32,
}

#[derive(Debug, thiserror::Error)]
pub enum PolishError {
    #[error("polish provider is unavailable")]
    Unavailable,
    #[error("polish request failed: {0}")]
    Request(String),
    #[error("polish request was cancelled")]
    Cancelled,
}

/// Post-ASR rewrite provider. Implemented in `vc-providers`; the pipeline
/// fails open to usable ASR when a provider errors.
#[async_trait::async_trait]
pub trait TextPolishing: Send + Sync {
    async fn polish(
        &self,
        masked_text: &str,
        terminology_entries: &[TerminologyEntry],
        hint_terms: &[String],
    ) -> Result<PolishedText, PolishError>;
}

#[cfg(test)]
mod tests {
    use super::*;

    fn decide(text: &str, duration_ms: i64) -> TextPolishDecision {
        TextPolishDecisionEngine.decide(
            text,
            duration_ms,
            DictationMode::Direct,
            TextPolishMode::AutomaticWhenKeyAvailable,
            true,
        )
    }

    #[test]
    fn disabled_and_unavailable_short_circuit() {
        let decision = TextPolishDecisionEngine.decide(
            "text",
            0,
            DictationMode::Direct,
            TextPolishMode::Disabled,
            true,
        );
        assert!(!decision.should_polish);
        assert_eq!(decision.reason, TextPolishDecisionReason::Disabled);

        let decision = TextPolishDecisionEngine.decide(
            "text",
            0,
            DictationMode::Direct,
            TextPolishMode::AutomaticWhenKeyAvailable,
            false,
        );
        assert_eq!(decision.reason, TextPolishDecisionReason::ProviderUnavailable);
    }

    #[test]
    fn skill_modes_force_polish() {
        let decision = TextPolishDecisionEngine.decide(
            "x",
            0,
            DictationMode::Email,
            TextPolishMode::AutomaticWhenKeyAvailable,
            true,
        );
        assert!(decision.should_polish);
        assert_eq!(decision.reason, TextPolishDecisionReason::RunEmail);
    }

    #[test]
    fn short_direct_is_skipped() {
        let decision = decide("你好呀", 2_000);
        assert!(!decision.should_polish);
        assert_eq!(decision.reason, TextPolishDecisionReason::SkipShortDirect);
    }

    #[test]
    fn self_correction_triggers_polish() {
        let decision = decide("周三开会不对改成周四", 3_000);
        assert!(decision.should_polish);
        assert_eq!(decision.reason, TextPolishDecisionReason::RunSelfCorrection);
    }

    #[test]
    fn long_dictation_triggers_polish() {
        let decision = decide("很长的一段话", 25_000);
        assert!(decision.should_polish);
        assert_eq!(decision.reason, TextPolishDecisionReason::RunLongDictation);
    }

    #[test]
    fn structured_intent_triggers_agent_plan() {
        let decision = decide("帮我整理成步骤第一先做这个第二再做那个", 5_000);
        assert!(decision.should_polish);
        assert_eq!(decision.reason, TextPolishDecisionReason::RunAgentPlan);
    }
}
