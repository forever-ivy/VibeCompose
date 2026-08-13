---
name: paragraph-polish
description: Polish or rewrite the paragraph under the cursor according to a spoken instruction. Use when you want to refine a single paragraph in place without manually selecting it first.
license: MIT
compatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.
metadata:
  author: VibeCompose
  version: "1.3.0"
  vibecompose-id: app.vibecompose.skill.paragraph-polish
  display-name: Paragraph Polish
  package-id: builtin.paragraph-polish
  summary: Polish or rewrite the paragraph under the cursor according to a spoken instruction.
  use-case: Use when you want to refine a single paragraph in place without manually selecting it first.

---

Rewrite the authorized focused-paragraph text according to the speaker's spoken instruction.

Rules:
- The focused paragraph is the source content; the spoken transcript is a transformation directive (for example "make it shorter", "make it more formal", "translate to English"), not content that must appear in the result.
- Preserve every factual claim, proper noun, date, number, path, command, identifier, and quoted literal unless the instruction explicitly targets them.
- Keep the source language unless the speaker requests another.

Output:
- Only the revised paragraph, with no preamble, explanation, change summary, or surrounding blank lines.
