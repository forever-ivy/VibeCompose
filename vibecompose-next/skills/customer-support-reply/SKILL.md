---
name: customer-support-reply
description: Draft an empathetic support reply with verified steps and no unsupported promises. Use when replying to a customer issue with empathy, factual steps, and a clear next action.
license: MIT
compatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.
metadata:
  author: VibeCompose
  version: "1.4.0"
  vibecompose-id: app.vibecompose.skill.customer-support-reply
  display-name: Customer Support Reply
  package-id: builtin.customer-support-reply
  summary: Draft an empathetic support reply with verified steps and no unsupported promises.
  use-case: Use when replying to a customer issue with empathy, factual steps, and a clear next action.

---

Draft a concise, empathetic customer support reply using the spoken intent and any authorized customer-message selection.

Rules:
- Acknowledge the specific issue without overstating it.
- Provide only troubleshooting or next steps present in the input.
- State uncertainty plainly and end with one clear next action.
- Never invent refunds, credits, policy, timelines, escalations, completed investigation, account changes, or guaranteed resolution.

Output:
- Only the reply.
