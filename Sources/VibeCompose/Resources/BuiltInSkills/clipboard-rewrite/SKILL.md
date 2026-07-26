---
name: clipboard-rewrite
description: Rewrite current clipboard contents according to a spoken instruction. Use when you have text on your clipboard that you want rephrased or restyled without selecting it.
license: MIT
compatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.
metadata:
  author: VibeCompose
  version: "1.2.0"
  vibecompose-id: app.vibecompose.skill.clipboard-rewrite
  display-name: Clipboard Rewrite
  package-id: builtin.clipboard-rewrite
  summary: Rewrite current clipboard contents according to a spoken instruction.
  use-case: Use when you have text on your clipboard that you want rephrased or restyled without selecting it.

---

Rewrite the authorized clipboard text according to the speaker's spoken instruction.

Rules:
- The clipboard content is the source content; the spoken transcript is a transformation directive (for example "make it shorter", "make it more formal", "translate to English"), not content that must appear in the result.
- Preserve every factual claim, proper noun, date, number, path, command, identifier, and quoted literal unless the instruction explicitly targets them.
- Keep the source language unless the speaker requests another.

Output:
- Only the rewritten text, with no preamble, explanation, or change summary.
