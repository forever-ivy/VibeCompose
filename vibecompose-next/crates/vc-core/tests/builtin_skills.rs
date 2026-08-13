//! Golden acceptance: every bundled Skill package (copied verbatim from the
//! Swift app) must load, produce a valid definition, and honor the built-in
//! contract (only the Direct skill may auto-paste, etc.).

use std::path::PathBuf;

use vc_core::skill::registry::SkillRegistry;
use vc_core::skill::{SkillDeliveryPolicy, SkillRiskLevel, DIRECT_SKILL_ID};

fn skills_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../skills")
}

#[test]
fn all_builtin_packages_load() {
    let (registry, failures) = SkillRegistry::load_directory(&skills_dir());
    assert!(
        failures.is_empty(),
        "built-in skills failed to load: {failures:?}"
    );
    assert_eq!(registry.len(), 21, "expected 21 bundled skills");
}

#[test]
fn direct_skill_matches_swift_contract() {
    let (registry, _) = SkillRegistry::load_directory(&skills_dir());
    let direct = registry.definition(DIRECT_SKILL_ID).expect("direct skill present");
    assert_eq!(direct.name, "Direct");
    assert_eq!(direct.version, "1.2.0");
    assert_eq!(direct.output.delivery, SkillDeliveryPolicy::AutomaticPasteWhenVerified);
    assert_eq!(direct.output.risk, SkillRiskLevel::Low);
    assert!(direct.prompt_instruction.starts_with("Voice Mode: Direct."));
}

#[test]
fn only_low_risk_skills_auto_paste() {
    let (registry, _) = SkillRegistry::load_directory(&skills_dir());
    for skill in registry.all() {
        if skill.output.delivery == SkillDeliveryPolicy::AutomaticPasteWhenVerified {
            assert_eq!(
                skill.output.risk,
                SkillRiskLevel::Low,
                "{} auto-pastes but is not low risk",
                skill.id
            );
        }
    }
}

#[test]
fn code_prompt_carries_terminology_resource() {
    let (registry, _) = SkillRegistry::load_directory(&skills_dir());
    let code_prompt = registry
        .definition("app.vibecompose.skill.code-prompt")
        .expect("code-prompt present");
    assert!(
        !code_prompt.terminology_entries.is_empty(),
        "terminology.csv should be bound"
    );
    assert!(code_prompt
        .terminology_entries
        .iter()
        .any(|e| e.original == "OpenAPI"));
}

#[test]
fn all_ids_and_versions_are_valid() {
    use vc_core::skill::SkillDefinition;
    let (registry, _) = SkillRegistry::load_directory(&skills_dir());
    for skill in registry.all() {
        assert!(
            SkillDefinition::is_valid_identifier(&skill.id),
            "invalid id {}",
            skill.id
        );
        assert!(
            SkillDefinition::is_valid_version(&skill.version),
            "invalid version {} for {}",
            skill.version,
            skill.id
        );
        assert!(skill.id.starts_with("app.vibecompose.skill."));
    }
}
