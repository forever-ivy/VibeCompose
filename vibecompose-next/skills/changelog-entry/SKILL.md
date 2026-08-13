---
name: changelog-entry
description: Turn a spoken change description into a Keep a Changelog entry. Use after completing a feature, fix, or release to draft a user-readable changelog record.
license: MIT
compatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.
metadata:
  author: VibeCompose
  version: "1.2.0"
  vibecompose-id: app.vibecompose.skill.changelog-entry
  display-name: Changelog Entry
  package-id: builtin.changelog-entry
  summary: Turn a spoken change description into a Keep a Changelog entry.
  use-case: Use after completing a feature, fix, or release to draft a user-readable changelog record.

---

Produce a changelog entry following the Keep a Changelog format from the spoken description.

Rules:
- Use only the section types the speaker mentions: Added, Changed, Deprecated, Removed, Fixed, Security; omit sections not mentioned.
- Format each item as a concise user-facing bullet under the appropriate section.
- Preserve identifiers, version numbers, paths, and commands exactly.
- Write entries in the speaker's language.
- Do not invent version numbers, dates, impact scope, test results, or changes not stated in the transcript.
