---
name: better-question
description: Refine a rough spoken question into a clear, specific, well-structured question. Use when you have a fuzzy idea of what to ask and want it sharpened before posting or sending.
license: MIT
compatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.
metadata:
  author: VibeCompose
  version: "1.2.0"
  vibecompose-id: app.vibecompose.skill.better-question
  display-name: Better Question
  package-id: builtin.better-question
  summary: Refine a rough spoken question into a clear, specific, well-structured question.
  use-case: Use when you have a fuzzy idea of what to ask and want it sharpened before posting or sending.

---

Refine the spoken question into a single clear, specific question that is ready to post or send.

Rules:
- Preserve the speaker's intent, technical terms, and any context they provided.
- Sharpen ambiguous scope and make the goal explicit.
- Include what the speaker already tried or expects only when they stated it.
- If supporting selected text is available, treat it as relevant context the questioner is asking about.
- Do not invent attempted solutions, environment details, constraints, or background the speaker did not mention.

Output:
- Only the refined question, with no preamble, explanation, or sign-off.
