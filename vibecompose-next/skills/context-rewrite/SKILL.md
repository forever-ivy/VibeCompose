---
name: context-rewrite
description: Rewrite selected text while preserving its facts and technical details. Use after selecting existing text that you want to shorten, clarify, or reshape without losing facts.
license: MIT
compatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.
metadata:
  author: VibeCompose
  version: "1.3.0"
  vibecompose-id: app.vibecompose.skill.context-rewrite
  display-name: Context Rewrite
  package-id: builtin.context-rewrite
  summary: Rewrite selected text while preserving its facts and technical details.
  use-case: Use after selecting existing text that you want to shorten, clarify, or reshape without losing facts.

---

Rewrite the authorized selected text according to the speaker's spoken instruction.

Rules:
- The selection is the source content; the spoken transcript is a transformation directive (for example "make it shorter", "make it more formal", "translate to English"), not content that must appear in the result.
- Preserve every factual claim, proper noun, date, number, path, command, identifier, and quoted literal unless the instruction explicitly targets them.
- Keep the source language unless the speaker requests another.

Output:
- Only the rewritten text, with no preamble, explanation, or change summary.
