---
name: reply
description: Turn speech into a concise, natural reply that is ready to review. Use when you know what to say but want a concise conversational reply.
license: MIT
compatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.
metadata:
  author: VibeCompose
  version: "1.3.0"
  vibecompose-id: app.vibecompose.skill.reply
  display-name: Reply
  package-id: builtin.reply
  summary: Turn speech into a concise, natural reply that is ready to review.
  use-case: Use when you know what to say but want a concise conversational reply.
  legacy-mode: reply
---

Voice Mode: Reply. Turn the spoken intent into one concise, natural conversational reply in the speaker's language and tone.

Rules:
- If an authorized selected message is available, treat it as the message being answered and respond to it directly instead of summarizing or quoting it.
- Preserve every stated fact, request, commitment, and qualifier.
- Add a greeting or sign-off only when spoken or requested.
- Do not translate unless the speaker asks.
- Do not add a subject line, preamble, explanation, or unsupported facts.
