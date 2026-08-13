//! The dictation pipeline: ASR → terminology normalization → optional AI
//! Polish (with literal masking) → post-normalization → Skill output
//! validation, with fail-open fallback to the normalized transcript.
//! Ported from Swift `DictationPipeline`.

use std::time::Instant;

use serde::{Deserialize, Serialize};

use crate::literal::{LiteralTokenizer, TokenStyle, Tokenization};
use crate::polish::{
    meaningful_character_count, sentence_terminator_count, TextPolishDecision,
    TextPolishDecisionEngine, TextPolishDecisionReason, TextPolishMode, TextPolishProviderId,
    TextPolishing,
};
use crate::skill::validator::SkillValidatorEngine;
use crate::skill::{ResolvedSkillExecutionPlan, SkillCapability, DIRECT_SKILL_ID};
use crate::skill::prompt::SkillPromptContext;
use crate::terminology::{TerminologyEntry, TranscriptNormalizing};

/// Recorded audio handed to a transcriber.
#[derive(Debug, Clone)]
pub struct RecordedAudio {
    pub wav_path: std::path::PathBuf,
    pub duration_ms: i64,
    pub sample_rate_hz: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TranscriptionMetrics {
    pub audio_duration_ms: i64,
    pub transcribe_ms: i64,
    pub audio_bytes: u64,
    pub provider: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TranscriptionResult {
    pub text: String,
    pub metrics: TranscriptionMetrics,
}

#[derive(Debug, thiserror::Error)]
pub enum TranscriptionError {
    #[error("no ChatGPT session; connect an account or configure an API key")]
    NotAuthenticated,
    #[error("audio file rejected: {0}")]
    InvalidAudio(String),
    #[error("transcription request failed: {0}")]
    Request(String),
    #[error("transcription was cancelled")]
    Cancelled,
}

#[async_trait::async_trait]
pub trait Transcriber: Send + Sync {
    async fn transcribe(&self, audio: &RecordedAudio) -> Result<TranscriptionResult, TranscriptionError>;
}

/// Bounded metrics captured for one prepared dictation.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DictationMetrics {
    pub transcription: TranscriptionMetrics,
    pub normalization_ms: i64,
    pub polish_ms: i64,
    pub text_polish_attempted: bool,
    pub text_polish_decision_reason: Option<TextPolishDecisionReason>,
    pub text_polish_provider: Option<TextPolishProviderId>,
    pub text_polish_error_message: Option<String>,
    pub estimated_polish_input_tokens: u32,
    pub estimated_polish_output_tokens: u32,
    pub skill_id: Option<String>,
    pub skill_version: Option<String>,
    pub skill_validation_issue_codes: Vec<String>,
    pub context_capability_codes: Vec<String>,
    pub selection_character_count: usize,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PreparedDictation {
    pub raw_text: String,
    pub final_text: String,
    pub normalization_applied: bool,
    pub exact_replacement_count: usize,
    pub fuzzy_replacement_count: usize,
    pub metrics: DictationMetrics,
}

pub struct DictationPipeline<'a> {
    pub transcriber: &'a dyn Transcriber,
    pub normalizer: &'a dyn TranscriptNormalizing,
    pub imported_entries: Vec<TerminologyEntry>,
    pub hint_terms: Vec<String>,
    pub text_polisher: Option<&'a dyn TextPolishing>,
    pub polish_mode: TextPolishMode,
    pub plan: ResolvedSkillExecutionPlan,
    pub prompt_context: SkillPromptContext,
}

impl<'a> DictationPipeline<'a> {
    pub async fn prepare(&self, audio: &RecordedAudio) -> Result<PreparedDictation, TranscriptionError> {
        let plan = &self.plan;
        let transcription = self.transcriber.transcribe(audio).await?;

        let normalization_started = Instant::now();
        let pre_polish = self.normalizer.normalize(
            &transcription.text,
            &self.imported_entries,
            &self.hint_terms,
        );
        let mut normalization_ms = normalization_started.elapsed().as_millis() as i64;

        let mut final_text = pre_polish.text.clone();
        let mut text_polish_attempted = false;
        let mut text_polish_provider = None;
        let mut text_polish_error_message: Option<String> = None;
        let mut estimated_input_tokens = 0u32;
        let mut estimated_output_tokens = 0u32;
        let mut polish_ms = 0i64;
        let mut skill_validation_issue_codes: Vec<String> = Vec::new();

        let decision = TextPolishDecisionEngine.decide(
            &pre_polish.text,
            transcription.metrics.audio_duration_ms,
            if plan.skill.id == DIRECT_SKILL_ID {
                crate::skill::DictationMode::Direct
            } else {
                match plan.legacy_mode() {
                    // A non-Direct Skill without a legacy mode still forces polish.
                    crate::skill::DictationMode::Direct => crate::skill::DictationMode::Reply,
                    other => other,
                }
            },
            self.polish_mode,
            self.text_polisher.is_some(),
        );

        if decision.should_polish {
            if let Some(polisher) = self.text_polisher {
                text_polish_attempted = true;
                let polish_started = Instant::now();
                match self
                    .run_polish(polisher, &pre_polish.text, plan, &decision)
                    .await
                {
                    Ok(outcome) => {
                        polish_ms = polish_started.elapsed().as_millis() as i64;
                        estimated_input_tokens = outcome.estimated_input_tokens;
                        estimated_output_tokens = outcome.estimated_output_tokens;
                        match outcome.result {
                            PolishOutcomeResult::Accepted {
                                text,
                                provider,
                                extra_normalization_ms,
                                issue_codes,
                            } => {
                                normalization_ms += extra_normalization_ms;
                                skill_validation_issue_codes = issue_codes;
                                text_polish_provider = Some(provider);
                                final_text = text;
                            }
                            PolishOutcomeResult::Rejected {
                                error_message,
                                issue_codes,
                            } => {
                                skill_validation_issue_codes = issue_codes;
                                text_polish_error_message = Some(error_message);
                                final_text =
                                    self.fallback_final_text(&pre_polish.text);
                            }
                        }
                    }
                    Err(error) => {
                        polish_ms = polish_started.elapsed().as_millis() as i64;
                        text_polish_error_message = Some(error.to_string());
                    }
                }
            }
        }

        Ok(PreparedDictation {
            raw_text: transcription.text.clone(),
            normalization_applied: pre_polish.applied || final_text != pre_polish.text,
            exact_replacement_count: pre_polish.exact_replacement_count,
            fuzzy_replacement_count: pre_polish.fuzzy_replacement_count,
            final_text,
            metrics: DictationMetrics {
                transcription: transcription.metrics,
                normalization_ms,
                polish_ms,
                text_polish_attempted,
                text_polish_decision_reason: Some(decision.reason),
                text_polish_provider,
                text_polish_error_message,
                estimated_polish_input_tokens: estimated_input_tokens,
                estimated_polish_output_tokens: estimated_output_tokens,
                skill_id: Some(plan.skill.id.clone()),
                skill_version: Some(plan.skill.version.clone()),
                skill_validation_issue_codes,
                context_capability_codes: self.context_capability_codes(),
                selection_character_count: self
                    .prompt_context
                    .selection
                    .as_deref()
                    .map(|s| s.chars().count())
                    .unwrap_or(0),
            },
        })
    }

    async fn run_polish(
        &self,
        polisher: &dyn TextPolishing,
        pre_polish_text: &str,
        plan: &ResolvedSkillExecutionPlan,
        _decision: &TextPolishDecision,
    ) -> Result<PolishOutcome, crate::polish::PolishError> {
        let tokenization = if plan.skill.protects_voice_technical_literals() {
            LiteralTokenizer.tokenize(pre_polish_text, TokenStyle::ModelSafe)
        } else {
            Tokenization::passthrough(pre_polish_text)
        };

        let polished = polisher
            .polish(
                &tokenization.masked_text,
                &self.imported_entries,
                &self.hint_terms,
            )
            .await?;

        let estimated_input_tokens = polished.estimated_input_tokens;
        let estimated_output_tokens = polished.estimated_output_tokens;

        // 1. Every masked literal must survive exactly once.
        let Some(literal_safe_text) = tokenization.restore_literals(&polished.text, true) else {
            return Ok(PolishOutcome {
                estimated_input_tokens,
                estimated_output_tokens,
                result: PolishOutcomeResult::Rejected {
                    error_message:
                        "AI Polish changed a protected technical literal; VibeCompose used the normalized transcript instead."
                            .into(),
                    issue_codes: vec![],
                },
            });
        };

        // 2. Direct output must not look truncated.
        if plan.skill.id == DIRECT_SKILL_ID
            && is_suspicious_polish_truncation(pre_polish_text, &literal_safe_text)
        {
            return Ok(PolishOutcome {
                estimated_input_tokens,
                estimated_output_tokens,
                result: PolishOutcomeResult::Rejected {
                    error_message:
                        "AI Polish output looked truncated; VibeCompose used the normalized transcript instead."
                            .into(),
                    issue_codes: vec![],
                },
            });
        }

        // 3. Post-normalize and validate against the Skill contract.
        let post_started = Instant::now();
        let post_polish = self.normalizer.normalize(
            &literal_safe_text,
            &self.imported_entries,
            &self.hint_terms,
        );
        let extra_normalization_ms = post_started.elapsed().as_millis() as i64;

        let validation = SkillValidatorEngine::default().validate(
            &post_polish.text,
            plan.skill.validation_source_text(
                pre_polish_text,
                self.prompt_context.selection.as_deref(),
            ),
            plan,
        );
        let issue_codes = validation.issue_codes();
        if !validation.is_valid() {
            return Ok(PolishOutcome {
                estimated_input_tokens,
                estimated_output_tokens,
                result: PolishOutcomeResult::Rejected {
                    error_message: format!(
                        "Skill output failed local validation ({}); VibeCompose used the normalized transcript instead.",
                        issue_codes.join(", ")
                    ),
                    issue_codes,
                },
            });
        }

        Ok(PolishOutcome {
            estimated_input_tokens,
            estimated_output_tokens,
            result: PolishOutcomeResult::Accepted {
                text: post_polish.text,
                provider: polished.provider,
                extra_normalization_ms,
                issue_codes,
            },
        })
    }

    /// Selection-primary skills must not deliver the spoken instruction as the
    /// replacement body when polish/validation fails.
    fn fallback_final_text(&self, pre_polish_text: &str) -> String {
        if self.plan.skill.uses_selection_as_primary_input() {
            if let Some(selection) = self.prompt_context.selection.as_deref() {
                let trimmed = selection.trim();
                if !trimmed.is_empty() {
                    return trimmed.to_string();
                }
            }
        }
        pre_polish_text.to_string()
    }

    fn context_capability_codes(&self) -> Vec<String> {
        let mut values = Vec::new();
        if self.prompt_context.selection.is_some() {
            values.push(SkillCapability::Selection.code().to_string());
        }
        if self.prompt_context.style_capsule.is_some() {
            values.push(SkillCapability::StyleCapsule.code().to_string());
        }
        values
    }
}

struct PolishOutcome {
    estimated_input_tokens: u32,
    estimated_output_tokens: u32,
    result: PolishOutcomeResult,
}

enum PolishOutcomeResult {
    Accepted {
        text: String,
        provider: TextPolishProviderId,
        extra_normalization_ms: i64,
        issue_codes: Vec<String>,
    },
    Rejected {
        error_message: String,
        issue_codes: Vec<String>,
    },
}

fn is_suspicious_polish_truncation(original: &str, polished: &str) -> bool {
    let original_count = meaningful_character_count(original);
    let polished_count = meaningful_character_count(polished);
    if original_count < 80 {
        return false;
    }
    if polished_count >= usize::max(40, (original_count as f64 * 0.35) as usize) {
        return false;
    }
    sentence_terminator_count(original) >= 3 && sentence_terminator_count(polished) <= 1
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::polish::{PolishError, PolishedText};
    use crate::skill::{
        DictationMode, SkillDefinition, SkillDeliveryPolicy, SkillOutputContract,
        SkillOutputFormat, SkillResolutionSource, SkillRiskLevel, SkillValidatorPolicy,
    };
    use crate::terminology::TerminologyNormalizer;

    struct FakeTranscriber(String);

    #[async_trait::async_trait]
    impl Transcriber for FakeTranscriber {
        async fn transcribe(
            &self,
            _audio: &RecordedAudio,
        ) -> Result<TranscriptionResult, TranscriptionError> {
            Ok(TranscriptionResult {
                text: self.0.clone(),
                metrics: TranscriptionMetrics {
                    audio_duration_ms: 3_000,
                    transcribe_ms: 100,
                    audio_bytes: 1_000,
                    provider: "fake".into(),
                },
            })
        }
    }

    struct FakePolisher {
        response: Box<dyn Fn(&str) -> String + Send + Sync>,
    }

    #[async_trait::async_trait]
    impl TextPolishing for FakePolisher {
        async fn polish(
            &self,
            masked_text: &str,
            _terminology_entries: &[TerminologyEntry],
            _hint_terms: &[String],
        ) -> Result<PolishedText, PolishError> {
            Ok(PolishedText {
                text: (self.response)(masked_text),
                provider: TextPolishProviderId::ChatGptAuth,
                estimated_input_tokens: 10,
                estimated_output_tokens: 10,
            })
        }
    }

    fn direct_plan() -> ResolvedSkillExecutionPlan {
        ResolvedSkillExecutionPlan {
            skill: SkillDefinition {
                schema_version: 1,
                id: DIRECT_SKILL_ID.into(),
                version: "1.2.0".into(),
                name: "Direct".into(),
                author: "VibeCompose".into(),
                minimum_app_version: "0.1.0".into(),
                required_capabilities: vec![SkillCapability::Voice],
                optional_capabilities: vec![],
                terminology_entries: vec![],
                prompt_instruction: "direct".into(),
                output: SkillOutputContract {
                    format: SkillOutputFormat::PlainText,
                    delivery: SkillDeliveryPolicy::AutomaticPasteWhenVerified,
                    risk: SkillRiskLevel::Low,
                },
                validators: SkillValidatorPolicy::default(),
                legacy_mode: Some(DictationMode::Direct),
                summary: None,
                use_case: None,
            },
            source: SkillResolutionSource::GlobalDefault,
            matched_application_rule_id: None,
        }
    }

    fn audio() -> RecordedAudio {
        RecordedAudio {
            wav_path: std::path::PathBuf::from("/tmp/x.wav"),
            duration_ms: 3_000,
            sample_rate_hz: 24_000,
        }
    }

    #[tokio::test]
    async fn short_direct_skips_polish_and_normalizes() {
        let transcriber = FakeTranscriber("我在 K8s 上部署".into());
        let normalizer = TerminologyNormalizer::default();
        let entries = vec![TerminologyEntry::term("Kubernetes", &["K8s"], "starter")];
        let pipeline = DictationPipeline {
            transcriber: &transcriber,
            normalizer: &normalizer,
            imported_entries: entries,
            hint_terms: vec![],
            text_polisher: None,
            polish_mode: TextPolishMode::AutomaticWhenKeyAvailable,
            plan: direct_plan(),
            prompt_context: SkillPromptContext::default(),
        };
        let prepared = pipeline.prepare(&audio()).await.unwrap();
        assert_eq!(prepared.final_text, "我在 Kubernetes 上部署");
        assert!(!prepared.metrics.text_polish_attempted);
        assert_eq!(
            prepared.metrics.text_polish_decision_reason,
            Some(TextPolishDecisionReason::ProviderUnavailable)
        );
    }

    #[tokio::test]
    async fn polish_rejection_falls_back_to_normalized_transcript() {
        // Polisher deletes the literal placeholder → restoration fails → fallback.
        let long_text = "先跑 ./scripts/check.sh 然后我们再看结果。这个流程要重复三次。每次都要记录数据。最后汇总一份报告出来给大家看。还要加上性能对比的部分。";
        let transcriber = FakeTranscriber(long_text.into());
        let normalizer = TerminologyNormalizer::default();
        let polisher = FakePolisher {
            response: Box::new(|_masked| "完全不同的输出没有令牌".to_string()),
        };
        let pipeline = DictationPipeline {
            transcriber: &transcriber,
            normalizer: &normalizer,
            imported_entries: vec![],
            hint_terms: vec![],
            text_polisher: Some(&polisher),
            polish_mode: TextPolishMode::Always,
            plan: direct_plan(),
            prompt_context: SkillPromptContext::default(),
        };
        let prepared = pipeline.prepare(&audio()).await.unwrap();
        assert_eq!(prepared.final_text, long_text);
        assert!(prepared.metrics.text_polish_attempted);
        assert!(prepared
            .metrics
            .text_polish_error_message
            .as_deref()
            .unwrap()
            .contains("technical literal"));
    }

    #[tokio::test]
    async fn accepted_polish_is_post_normalized() {
        let transcriber = FakeTranscriber("发个消息给团队说进度正常".into());
        let normalizer = TerminologyNormalizer::default();
        let polisher = FakePolisher {
            response: Box::new(|masked| format!("{masked}，已经整理好了")),
        };
        let pipeline = DictationPipeline {
            transcriber: &transcriber,
            normalizer: &normalizer,
            imported_entries: vec![],
            hint_terms: vec![],
            text_polisher: Some(&polisher),
            polish_mode: TextPolishMode::Always,
            plan: direct_plan(),
            prompt_context: SkillPromptContext::default(),
        };
        let prepared = pipeline.prepare(&audio()).await.unwrap();
        assert!(prepared.final_text.ends_with("已经整理好了"));
        assert_eq!(
            prepared.metrics.text_polish_provider,
            Some(TextPolishProviderId::ChatGptAuth)
        );
        assert_eq!(
            prepared.metrics.text_polish_decision_reason,
            Some(TextPolishDecisionReason::ForcedAlways)
        );
    }

    #[tokio::test]
    async fn truncated_direct_polish_is_rejected() {
        let long_text = "第一句话详细说明这次任务的目标和背景。第二句话详细说明所有已知的约束条件。第三句话详细说明验收标准和检查方式。第四句话补充各种边界情况的处理策略。第五句话强调测试覆盖必须完整无遗漏。第六句话总结整个计划的关键节点和时间安排。";
        let transcriber = FakeTranscriber(long_text.into());
        let normalizer = TerminologyNormalizer::default();
        let polisher = FakePolisher {
            response: Box::new(|_masked| "太短".to_string()),
        };
        let pipeline = DictationPipeline {
            transcriber: &transcriber,
            normalizer: &normalizer,
            imported_entries: vec![],
            hint_terms: vec![],
            text_polisher: Some(&polisher),
            polish_mode: TextPolishMode::Always,
            plan: direct_plan(),
            prompt_context: SkillPromptContext::default(),
        };
        let prepared = pipeline.prepare(&audio()).await.unwrap();
        assert_eq!(prepared.final_text, long_text);
        assert!(prepared
            .metrics
            .text_polish_error_message
            .as_deref()
            .unwrap()
            .contains("truncated"));
    }
}
