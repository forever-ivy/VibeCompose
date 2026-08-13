//! Spec-fixture acceptance: the JSON golden files under `spec/fixtures/` are
//! the language-neutral contract shared with the Swift implementation. This
//! test consumes them directly so the Rust port cannot drift from the spec.

use std::path::PathBuf;

use vc_core::literal::{LiteralTokenizer, TokenStyle};
use vc_core::polish::{TextPolishDecisionEngine, TextPolishMode};
use vc_core::skill::DictationMode;

fn fixture(name: &str) -> serde_json::Value {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../spec/fixtures")
        .join(name);
    serde_json::from_str(&std::fs::read_to_string(path).expect("fixture readable"))
        .expect("fixture is valid JSON")
}

#[test]
fn decision_engine_matches_spec() {
    let doc = fixture("decision-engine.json");
    for case in doc["cases"].as_array().unwrap() {
        let text = case["text"].as_str().unwrap();
        let duration = case["audioDurationMs"].as_i64().unwrap();
        let mode = match case["mode"].as_str() {
            Some("reply") => DictationMode::Reply,
            Some("email") => DictationMode::Email,
            Some("codePrompt") => DictationMode::CodePrompt,
            Some("translate") => DictationMode::Translate,
            _ => DictationMode::Direct,
        };
        let polish_mode = match case["polishMode"].as_str() {
            Some("disabled") => TextPolishMode::Disabled,
            Some("always") => TextPolishMode::Always,
            _ => TextPolishMode::AutomaticWhenKeyAvailable,
        };
        let provider_available = case["providerAvailable"].as_bool().unwrap_or(true);

        let decision =
            TextPolishDecisionEngine.decide(text, duration, mode, polish_mode, provider_available);
        let expected_should = case["expect"]["shouldPolish"].as_bool().unwrap();
        let expected_reason = case["expect"]["reason"].as_str().unwrap();
        let actual_reason = serde_json::to_value(decision.reason).unwrap();

        assert_eq!(
            decision.should_polish, expected_should,
            "shouldPolish mismatch for {text:?}"
        );
        assert_eq!(
            actual_reason.as_str().unwrap(),
            expected_reason,
            "reason mismatch for {text:?}"
        );
    }
}

#[test]
fn literal_tokenizer_matches_spec() {
    let doc = fixture("literal-tokenizer.json");
    for case in doc["cases"].as_array().unwrap() {
        let text = case["text"].as_str().unwrap();
        let tokenization = LiteralTokenizer.tokenize(text, TokenStyle::ModelSafe);
        for literal in case["mustProtect"].as_array().unwrap() {
            let literal = literal.as_str().unwrap();
            assert!(
                tokenization
                    .literals
                    .iter()
                    .any(|protected| protected.contains(literal)),
                "expected {literal:?} protected in {text:?}, got {:?}",
                tokenization.literals
            );
        }
        // Round-trip: masked text restores to the original.
        let restored = tokenization
            .restore_literals(&tokenization.masked_text, true)
            .expect("masked text must restore");
        assert_eq!(restored, text);
    }
}

#[test]
fn skill_resolution_matches_spec() {
    use vc_core::skill::registry::SkillRegistry;
    use vc_core::skill::resolver::{AppSkillRule, LaunchAppContext, SkillResolver, SkillsConfig};
    use vc_core::skill::{SkillDefinition, SkillOutputContract, SkillValidatorPolicy};

    let doc = fixture("skill-resolution.json");
    let mut registry = SkillRegistry::new();
    for id in doc["registrySkillIds"].as_array().unwrap() {
        let id = id.as_str().unwrap();
        registry.insert(SkillDefinition {
            schema_version: 1,
            id: id.into(),
            version: "1.0.0".into(),
            name: id.into(),
            author: "spec".into(),
            minimum_app_version: "0.1.0".into(),
            required_capabilities: vec![],
            optional_capabilities: vec![],
            terminology_entries: vec![],
            prompt_instruction: "spec".into(),
            output: SkillOutputContract::default(),
            validators: SkillValidatorPolicy::default(),
            legacy_mode: None,
            summary: None,
            use_case: None,
        });
    }

    let base_config = &doc["config"];
    for case in doc["cases"].as_array().unwrap() {
        let enabled: Vec<String> = case["overrideEnabledSkillIds"]
            .as_array()
            .unwrap_or_else(|| base_config["enabledSkillIds"].as_array().unwrap())
            .iter()
            .map(|v| v.as_str().unwrap().to_string())
            .collect();
        let config = SkillsConfig {
            default_skill_id: base_config["defaultSkillId"].as_str().unwrap().into(),
            enabled_skill_ids: enabled,
            application_rules: base_config["applicationRules"]
                .as_array()
                .unwrap()
                .iter()
                .map(|rule| AppSkillRule {
                    id: uuid::Uuid::new_v4(),
                    application_id: rule["applicationId"].as_str().unwrap().into(),
                    application_name: String::new(),
                    skill_id: rule["skillId"].as_str().unwrap().into(),
                    is_enabled: rule["isEnabled"].as_bool().unwrap(),
                })
                .collect(),
        };
        let launch = case["launchAppId"].as_str().map(|id| LaunchAppContext {
            application_id: Some(id.to_string()),
            application_name: None,
        });
        let plan = SkillResolver.resolve(
            &registry,
            case["manualSkillId"].as_str(),
            &config,
            launch.as_ref(),
        );
        assert_eq!(
            plan.skill.id,
            case["expect"]["skillId"].as_str().unwrap(),
            "skill mismatch for case {case}"
        );
        let source = serde_json::to_value(plan.source).unwrap();
        assert_eq!(
            source.as_str().unwrap(),
            case["expect"]["source"].as_str().unwrap(),
            "source mismatch for case {case}"
        );
    }
}
