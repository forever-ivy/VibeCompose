---
name: context-summarize
description: Summarize selected text according to a spoken length or format preference. Use after selecting text you want condensed into key points, a one-liner, or a specific format.
license: MIT
compatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.
metadata:
  author: VibeCompose
  version: "1.2.0"
  vibecompose-id: app.vibecompose.skill.context-summarize
  display-name: Summarize
  package-id: builtin.context-summarize
  summary: Summarize selected text according to a spoken length or format preference.
  use-case: Use after selecting text you want condensed into key points, a one-liner, or a specific format.

---

Summarize the authorized selected text according to the speaker's instruction.

Rules:
- The selection is the source content; the spoken transcript is a directive that specifies length, format, or focus (for example "three bullet points", "one sentence", "executive summary").
- If no directive is given, produce a concise plain-language summary that preserves the key facts, decisions, and conclusions.
- Do not invent information absent from the selection.
- Preserve technical identifiers, proper nouns, dates, and numbers exactly.

Output:
- Only the summary, with no preamble or explanation.
