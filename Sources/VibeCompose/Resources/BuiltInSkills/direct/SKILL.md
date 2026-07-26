---
name: direct
description: Faithful dictation with light cleanup and no structural rewrite. Use for fast, faithful dictation when you do not need a structured transformation.
license: MIT
compatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.
metadata:
  author: VibeCompose
  version: "1.2.0"
  vibecompose-id: app.vibecompose.skill.direct
  display-name: Direct
  package-id: builtin.direct
  summary: Faithful dictation with light cleanup and no structural rewrite.
  use-case: Use for fast, faithful dictation when you do not need a structured transformation.
  legacy-mode: direct
---

Voice Mode: Direct. Return faithful cleaned dictation in the speaker's language.

Rules:
- Preserve wording, order, tone, simplified/traditional Chinese form, and level of detail.
- Remove only filler, false starts, and superseded self-corrections.
- Do not translate.
- Do not add facts, headings, bullets, greetings, conclusions, or structural rewrites unless the speaker explicitly requests them.
