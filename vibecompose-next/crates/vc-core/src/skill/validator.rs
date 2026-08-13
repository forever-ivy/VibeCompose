//! Local output validation: model output that fails the Skill's declared
//! contract causes the pipeline to fall back to the normalized transcript.
//! Ported from Swift `SkillValidatorEngine`.

use serde::{Deserialize, Serialize};

use super::prompt::INTERNAL_MARKERS;
use super::ResolvedSkillExecutionPlan;
use crate::literal::{LiteralTokenizer, TokenStyle};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ValidationIssueCode {
    Empty,
    TooLong,
    InvalidJson,
    UnclosedMarkdownFence,
    MissingRequiredSection,
    ChangedTechnicalLiteral,
    ForbiddenPhrase,
    LeakedInternalMarker,
}

impl ValidationIssueCode {
    /// Stable telemetry code, matching Swift raw values.
    pub fn code(&self) -> &'static str {
        match self {
            Self::Empty => "empty",
            Self::TooLong => "tooLong",
            Self::InvalidJson => "invalidJSON",
            Self::UnclosedMarkdownFence => "unclosedMarkdownFence",
            Self::MissingRequiredSection => "missingRequiredSection",
            Self::ChangedTechnicalLiteral => "changedTechnicalLiteral",
            Self::ForbiddenPhrase => "forbiddenPhrase",
            Self::LeakedInternalMarker => "leakedInternalMarker",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ValidationIssue {
    pub code: ValidationIssueCode,
    pub field: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct ValidationReport {
    pub issues: Vec<ValidationIssue>,
}

impl ValidationReport {
    pub fn is_valid(&self) -> bool {
        self.issues.is_empty()
    }

    pub fn issue_codes(&self) -> Vec<String> {
        self.issues.iter().map(|i| i.code.code().to_string()).collect()
    }
}

#[derive(Debug, Default, Clone, Copy)]
pub struct SkillValidatorEngine {
    tokenizer: LiteralTokenizer,
}

impl SkillValidatorEngine {
    pub fn validate(
        &self,
        output: &str,
        original_text: &str,
        plan: &ResolvedSkillExecutionPlan,
    ) -> ValidationReport {
        let policy = &plan.skill.validators;
        let normalized = output.trim();
        let mut issues = Vec::new();

        if policy.require_non_empty && normalized.is_empty() {
            issues.push(ValidationIssue {
                code: ValidationIssueCode::Empty,
                field: None,
            });
        }

        if output.chars().count() > policy.maximum_characters {
            issues.push(ValidationIssue {
                code: ValidationIssueCode::TooLong,
                field: Some(policy.maximum_characters.to_string()),
            });
        }

        if plan.skill.output.format == super::SkillOutputFormat::Json
            && !normalized.is_empty()
            && serde_json::from_str::<serde_json::Value>(normalized).is_err()
        {
            issues.push(ValidationIssue {
                code: ValidationIssueCode::InvalidJson,
                field: None,
            });
        }

        if policy.require_closed_markdown_fences && markdown_fence_count(output) % 2 != 0 {
            issues.push(ValidationIssue {
                code: ValidationIssueCode::UnclosedMarkdownFence,
                field: None,
            });
        }

        let folded_output = output.to_lowercase();
        for alternatives in &policy.required_section_alternatives {
            if alternatives.is_empty() {
                continue;
            }
            let found = alternatives
                .iter()
                .any(|section| folded_output.contains(&section.to_lowercase()));
            if !found {
                issues.push(ValidationIssue {
                    code: ValidationIssueCode::MissingRequiredSection,
                    field: alternatives.first().cloned(),
                });
            }
        }

        if policy.preserve_technical_literals {
            let literals = self
                .tokenizer
                .tokenize(original_text, TokenStyle::PrivateUse)
                .literals;
            for literal in literals {
                if occurrence_count(&literal, output) != 1 {
                    issues.push(ValidationIssue {
                        code: ValidationIssueCode::ChangedTechnicalLiteral,
                        field: None,
                    });
                    break;
                }
            }
        }

        for phrase in &policy.forbidden_phrases {
            if !phrase.is_empty() && folded_output.contains(&phrase.to_lowercase()) {
                issues.push(ValidationIssue {
                    code: ValidationIssueCode::ForbiddenPhrase,
                    field: None,
                });
                break;
            }
        }

        if INTERNAL_MARKERS.iter().any(|marker| output.contains(marker)) {
            issues.push(ValidationIssue {
                code: ValidationIssueCode::LeakedInternalMarker,
                field: None,
            });
        }

        ValidationReport { issues }
    }
}

fn markdown_fence_count(value: &str) -> usize {
    value.matches("```").count()
}

fn occurrence_count(needle: &str, haystack: &str) -> usize {
    if needle.is_empty() {
        return 0;
    }
    haystack.matches(needle).count()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::skill::{
        SkillDefinition, SkillDeliveryPolicy, SkillOutputContract, SkillOutputFormat,
        SkillResolutionSource, SkillRiskLevel, SkillValidatorPolicy,
    };

    fn plan_with(policy: SkillValidatorPolicy, format: SkillOutputFormat) -> ResolvedSkillExecutionPlan {
        ResolvedSkillExecutionPlan {
            skill: SkillDefinition {
                schema_version: 1,
                id: "t.v".into(),
                version: "1.0.0".into(),
                name: "T".into(),
                author: "t".into(),
                minimum_app_version: "0.1.0".into(),
                required_capabilities: vec![],
                optional_capabilities: vec![],
                terminology_entries: vec![],
                prompt_instruction: "x".into(),
                output: SkillOutputContract {
                    format,
                    delivery: SkillDeliveryPolicy::PreviewThenPaste,
                    risk: SkillRiskLevel::Medium,
                },
                validators: policy,
                legacy_mode: None,
                summary: None,
                use_case: None,
            },
            source: SkillResolutionSource::GlobalDefault,
            matched_application_rule_id: None,
        }
    }

    #[test]
    fn flags_empty_and_too_long() {
        let plan = plan_with(
            SkillValidatorPolicy {
                maximum_characters: 5,
                ..Default::default()
            },
            SkillOutputFormat::PlainText,
        );
        let report = SkillValidatorEngine::default().validate("", "src", &plan);
        assert!(report.issues.iter().any(|i| i.code == ValidationIssueCode::Empty));
        let report = SkillValidatorEngine::default().validate("太长的输出啊", "src", &plan);
        assert!(report.issues.iter().any(|i| i.code == ValidationIssueCode::TooLong));
    }

    #[test]
    fn validates_json_format() {
        let plan = plan_with(SkillValidatorPolicy::default(), SkillOutputFormat::Json);
        let bad = SkillValidatorEngine::default().validate("not json", "src", &plan);
        assert!(bad.issues.iter().any(|i| i.code == ValidationIssueCode::InvalidJson));
        let good = SkillValidatorEngine::default().validate("{\"a\":1}", "src", &plan);
        assert!(good.is_valid());
    }

    #[test]
    fn requires_sections_with_alternatives() {
        let plan = plan_with(
            SkillValidatorPolicy {
                required_section_alternatives: vec![vec![
                    "Observed Behavior".into(),
                    "实际行为".into(),
                ]],
                ..Default::default()
            },
            SkillOutputFormat::Markdown,
        );
        let engine = SkillValidatorEngine::default();
        assert!(engine.validate("## 实际行为\n描述", "src", &plan).is_valid());
        let missing = engine.validate("## 别的\n描述", "src", &plan);
        assert!(missing
            .issues
            .iter()
            .any(|i| i.code == ValidationIssueCode::MissingRequiredSection));
    }

    #[test]
    fn detects_changed_literal_and_leaked_marker() {
        let plan = plan_with(SkillValidatorPolicy::default(), SkillOutputFormat::PlainText);
        let engine = SkillValidatorEngine::default();
        let original = "跑一下 ./scripts/check.sh 再看";
        let dropped = engine.validate("跑一下再看", original, &plan);
        assert!(dropped
            .issues
            .iter()
            .any(|i| i.code == ValidationIssueCode::ChangedTechnicalLiteral));
        let leaked = engine.validate(
            "[VIBECOMPOSE_SYSTEM_RULES] 泄露 ./scripts/check.sh",
            original,
            &plan,
        );
        assert!(leaked
            .issues
            .iter()
            .any(|i| i.code == ValidationIssueCode::LeakedInternalMarker));
    }

    #[test]
    fn unclosed_fence_detection() {
        let plan = plan_with(
            SkillValidatorPolicy {
                require_closed_markdown_fences: true,
                ..Default::default()
            },
            SkillOutputFormat::Markdown,
        );
        let engine = SkillValidatorEngine::default();
        assert!(!engine.validate("```rust\nfn main() {}\n", "src", &plan).is_valid());
        assert!(engine
            .validate("```rust\nfn main() {}\n```", "src", &plan)
            .is_valid());
    }
}
