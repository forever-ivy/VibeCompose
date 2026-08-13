//! Skill registry: stable, versioned Skill declarations loaded from bundled
//! package directories, merged with installed community Skills.

use std::collections::BTreeMap;
use std::path::Path;

use super::package::{load_package, SkillPackageError};
use super::{SkillDefinition, DIRECT_SKILL_ID};

#[derive(Debug, Clone, Default)]
pub struct SkillRegistry {
    definitions: BTreeMap<String, SkillDefinition>,
    order: Vec<String>,
}

impl SkillRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Loads every package directory under `root` (one directory per Skill).
    /// Damaged packages are skipped and reported, never fatal: a broken
    /// community Skill cannot take the registry down.
    pub fn load_directory(root: &Path) -> (Self, Vec<(String, SkillPackageError)>) {
        let mut registry = Self::new();
        let mut failures = Vec::new();
        let Ok(entries) = std::fs::read_dir(root) else {
            return (registry, failures);
        };
        let mut dirs: Vec<_> = entries
            .flatten()
            .filter(|e| e.path().is_dir())
            .map(|e| e.path())
            .collect();
        dirs.sort();
        for dir in dirs {
            let label = dir
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_default();
            match load_package(&dir).and_then(|package| package.definition()) {
                Ok(definition) => registry.insert(definition),
                Err(error) => failures.push((label, error)),
            }
        }
        (registry, failures)
    }

    pub fn insert(&mut self, definition: SkillDefinition) {
        if !self.definitions.contains_key(&definition.id) {
            self.order.push(definition.id.clone());
        }
        self.definitions.insert(definition.id.clone(), definition);
    }

    /// Merges another registry on top of this one (installed Skills over
    /// built-ins). Existing IDs are replaced but keep their position.
    pub fn merged_with(mut self, other: SkillRegistry) -> SkillRegistry {
        for id in other.order {
            let definition = other.definitions[&id].clone();
            self.insert(definition);
        }
        self
    }

    pub fn definition(&self, id: &str) -> Option<&SkillDefinition> {
        self.definitions.get(id)
    }

    pub fn contains(&self, id: &str) -> bool {
        self.definitions.contains_key(id)
    }

    pub fn direct(&self) -> Option<&SkillDefinition> {
        self.definition(DIRECT_SKILL_ID)
    }

    /// Definitions in load order (bundled ordering, then installs).
    pub fn all(&self) -> Vec<&SkillDefinition> {
        self.order
            .iter()
            .filter_map(|id| self.definitions.get(id))
            .collect()
    }

    pub fn len(&self) -> usize {
        self.definitions.len()
    }

    pub fn is_empty(&self) -> bool {
        self.definitions.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::skill::{SkillOutputContract, SkillValidatorPolicy};

    fn definition(id: &str) -> SkillDefinition {
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

    #[test]
    fn merge_replaces_by_id_and_keeps_order() {
        let mut base = SkillRegistry::new();
        base.insert(definition("a"));
        base.insert(definition("b"));
        let mut overlay = SkillRegistry::new();
        let mut replacement = definition("a");
        replacement.version = "2.0.0".into();
        overlay.insert(replacement);
        overlay.insert(definition("c"));

        let merged = base.merged_with(overlay);
        assert_eq!(merged.len(), 3);
        assert_eq!(merged.definition("a").unwrap().version, "2.0.0");
        let ids: Vec<&str> = merged.all().iter().map(|d| d.id.as_str()).collect();
        assert_eq!(ids, ["a", "b", "c"]);
    }
}
