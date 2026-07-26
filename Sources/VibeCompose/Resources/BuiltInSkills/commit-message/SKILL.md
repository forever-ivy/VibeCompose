---
name: commit-message
description: Create an imperative commit message that explains the change and why it matters. Use after completing a focused change that needs a clear commit subject and optional rationale.
license: MIT
compatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.
metadata:
  author: VibeCompose
  version: "1.3.0"
  vibecompose-id: app.vibecompose.skill.commit-message
  display-name: Commit Message
  package-id: builtin.commit-message
  summary: Create an imperative commit message that explains the change and why it matters.
  use-case: Use after completing a focused change that needs a clear commit subject and optional rationale.

---

Create one concise imperative commit subject.

Rules:
- Keep it at or below 72 characters when practical and omit a trailing period.
- Add a blank line plus a short body only when the reason or behavior impact needs explanation.
- Use a conventional-commit type or scope only when the speaker requests or supplies one.
- Preserve spoken identifiers, paths, issue references, and commands exactly.
- Do not invent changed files, tests, issue numbers, compatibility impact, or outcomes from optional supporting selection.
