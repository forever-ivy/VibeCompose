//! Skill resolution: manual selection → exact application rule → global
//! default → Direct safety fallback. The resolved plan is frozen when
//! recording begins. Ported from Swift `SkillResolver`.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::registry::SkillRegistry;
use super::{ResolvedSkillExecutionPlan, SkillResolutionSource, DIRECT_SKILL_ID};

/// A per-application Skill rule: exact application identifier only, never
/// window or document content. On macOS this is a bundle identifier; on
/// Windows the executable's canonical name; on Linux the desktop app id.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppSkillRule {
    #[serde(default = "Uuid::new_v4")]
    pub id: Uuid,
    pub application_id: String,
    #[serde(default)]
    pub application_name: String,
    pub skill_id: String,
    #[serde(default = "default_true")]
    pub is_enabled: bool,
}

fn default_true() -> bool {
    true
}

impl AppSkillRule {
    pub fn normalized_application_id(raw: &str) -> String {
        raw.trim().to_lowercase()
    }
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SkillsConfig {
    pub default_skill_id: String,
    pub enabled_skill_ids: Vec<String>,
    pub application_rules: Vec<AppSkillRule>,
}

impl SkillsConfig {
    pub fn is_enabled(&self, skill_id: &str) -> bool {
        self.enabled_skill_ids.iter().any(|id| id == skill_id)
    }
}

/// The foreground application at recording start.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct LaunchAppContext {
    pub application_id: Option<String>,
    pub application_name: Option<String>,
}

#[derive(Debug, Clone, Copy, Default)]
pub struct SkillResolver;

impl SkillResolver {
    pub fn resolve(
        &self,
        registry: &SkillRegistry,
        manual_skill_id: Option<&str>,
        config: &SkillsConfig,
        launch_app: Option<&LaunchAppContext>,
    ) -> ResolvedSkillExecutionPlan {
        if let Some(manual_id) = manual_skill_id {
            if config.is_enabled(manual_id) {
                if let Some(skill) = registry.definition(manual_id) {
                    return ResolvedSkillExecutionPlan {
                        skill: skill.clone(),
                        source: SkillResolutionSource::Manual,
                        matched_application_rule_id: None,
                    };
                }
            }
        }

        let normalized_app_id = launch_app
            .and_then(|ctx| ctx.application_id.as_deref())
            .map(AppSkillRule::normalized_application_id);
        if let Some(app_id) = normalized_app_id {
            if let Some(rule) = config
                .application_rules
                .iter()
                .find(|rule| rule.is_enabled && rule.application_id.to_lowercase() == app_id)
            {
                if config.is_enabled(&rule.skill_id) {
                    if let Some(skill) = registry.definition(&rule.skill_id) {
                        return ResolvedSkillExecutionPlan {
                            skill: skill.clone(),
                            source: SkillResolutionSource::ApplicationRule,
                            matched_application_rule_id: Some(rule.id),
                        };
                    }
                }
            }
        }

        if config.is_enabled(&config.default_skill_id) {
            if let Some(skill) = registry.definition(&config.default_skill_id) {
                return ResolvedSkillExecutionPlan {
                    skill: skill.clone(),
                    source: SkillResolutionSource::GlobalDefault,
                    matched_application_rule_id: None,
                };
            }
        }

        // Unknown, disabled, or missing installations resolve to the Direct
        // safety fallback.
        let direct = registry
            .definition(DIRECT_SKILL_ID)
            .cloned()
            .unwrap_or_else(fallback_direct_definition);
        ResolvedSkillExecutionPlan {
            skill: direct,
            source: SkillResolutionSource::DirectFallback,
            matched_application_rule_id: None,
        }
    }
}

/// A minimal in-code Direct declaration used only when the bundled package
/// directory is unavailable; keeps dictation usable in a broken install.
fn fallback_direct_definition() -> super::SkillDefinition {
    super::SkillDefinition {
        schema_version: 1,
        id: DIRECT_SKILL_ID.into(),
        version: "1.0.0".into(),
        name: "Direct".into(),
        author: "VibeCompose".into(),
        minimum_app_version: "0.1.0".into(),
        required_capabilities: vec![super::SkillCapability::Voice],
        optional_capabilities: vec![],
        terminology_entries: vec![],
        prompt_instruction: "Voice Mode: Direct. Return faithful cleaned dictation in the speaker's language. Remove only filler, false starts, and superseded self-corrections. Do not translate. Do not add facts, headings, bullets, greetings, conclusions, or structural rewrites unless the speaker explicitly requests them.".into(),
        output: super::SkillOutputContract {
            format: super::SkillOutputFormat::PlainText,
            delivery: super::SkillDeliveryPolicy::AutomaticPasteWhenVerified,
            risk: super::SkillRiskLevel::Low,
        },
        validators: super::SkillValidatorPolicy::default(),
        legacy_mode: Some(super::DictationMode::Direct),
        summary: None,
        use_case: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::skill::{SkillDefinition, SkillOutputContract, SkillValidatorPolicy};

    fn skill(id: &str) -> SkillDefinition {
        SkillDefinition {
            schema_version: 1,
            id: id.into(),
            version: "1.0.0".into(),
            name: id.into(),
            author: "t".into(),
            minimum_app_version: "0.1.0".into(),
            required_capabilities: vec![],
            optional_capabilities: vec![],
            terminology_entries: vec![],
            prompt_instruction: "x".into(),
            output: SkillOutputContract::default(),
            validators: SkillValidatorPolicy::default(),
            legacy_mode: None,
            summary: None,
            use_case: None,
        }
    }

    fn registry() -> SkillRegistry {
        let mut registry = SkillRegistry::new();
        registry.insert(skill(DIRECT_SKILL_ID));
        registry.insert(skill("app.vibecompose.skill.email"));
        registry.insert(skill("app.vibecompose.skill.reply"));
        registry
    }

    fn config() -> SkillsConfig {
        SkillsConfig {
            default_skill_id: "app.vibecompose.skill.email".into(),
            enabled_skill_ids: vec![
                DIRECT_SKILL_ID.into(),
                "app.vibecompose.skill.email".into(),
                "app.vibecompose.skill.reply".into(),
            ],
            application_rules: vec![AppSkillRule {
                id: Uuid::new_v4(),
                application_id: "com.tencent.xinwechat".into(),
                application_name: "WeChat".into(),
                skill_id: "app.vibecompose.skill.reply".into(),
                is_enabled: true,
            }],
        }
    }

    #[test]
    fn manual_selection_wins() {
        let plan = SkillResolver.resolve(
            &registry(),
            Some("app.vibecompose.skill.reply"),
            &config(),
            None,
        );
        assert_eq!(plan.skill.id, "app.vibecompose.skill.reply");
        assert_eq!(plan.source, SkillResolutionSource::Manual);
    }

    #[test]
    fn application_rule_matches_exact_id_case_insensitively() {
        let launch = LaunchAppContext {
            application_id: Some("com.tencent.xinWeChat".into()),
            application_name: Some("WeChat".into()),
        };
        let plan = SkillResolver.resolve(&registry(), None, &config(), Some(&launch));
        assert_eq!(plan.skill.id, "app.vibecompose.skill.reply");
        assert_eq!(plan.source, SkillResolutionSource::ApplicationRule);
        assert!(plan.matched_application_rule_id.is_some());
    }

    #[test]
    fn falls_back_to_global_default_then_direct() {
        let plan = SkillResolver.resolve(&registry(), None, &config(), None);
        assert_eq!(plan.skill.id, "app.vibecompose.skill.email");
        assert_eq!(plan.source, SkillResolutionSource::GlobalDefault);

        let mut disabled = config();
        disabled.enabled_skill_ids = vec![DIRECT_SKILL_ID.into()];
        let plan = SkillResolver.resolve(&registry(), None, &disabled, None);
        assert_eq!(plan.skill.id, DIRECT_SKILL_ID);
        assert_eq!(plan.source, SkillResolutionSource::DirectFallback);
    }

    #[test]
    fn disabled_manual_id_falls_through() {
        let mut cfg = config();
        cfg.enabled_skill_ids = vec![DIRECT_SKILL_ID.into(), "app.vibecompose.skill.email".into()];
        let plan = SkillResolver.resolve(
            &registry(),
            Some("app.vibecompose.skill.reply"),
            &cfg,
            None,
        );
        assert_eq!(plan.source, SkillResolutionSource::GlobalDefault);
    }
}
