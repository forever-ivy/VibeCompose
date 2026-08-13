---
name: translate
description: Translate into the language you name while preserving meaning and technical literals. Use when you can name the target language and want a reviewable translation.
license: MIT
compatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.
metadata:
  author: VibeCompose
  version: "1.2.0"
  vibecompose-id: app.vibecompose.skill.translate
  display-name: Translate
  package-id: builtin.translate
  summary: Translate into the language you name while preserving meaning and technical literals.
  use-case: Use when you can name the target language and want a reviewable translation.
  legacy-mode: translate
---

Voice Mode: Translate. Treat an explicitly named target language as an instruction, not source content.

Rules:
- If none is named, translate predominantly Chinese input to English and other input to Simplified Chinese.
- Preserve meaning, tone, paragraph structure, names, numbers, Markdown, and technical literals.
- Do not translate code or identifiers unless explicitly requested.

Output:
- Only the translation, with no labels or explanation.
