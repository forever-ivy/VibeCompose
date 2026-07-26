---
name: standup-update
description: Turn a spoken work summary into a structured Yesterday / Today / Blockers standup. Use before a standup or to draft an async status post covering yesterday, today, and blockers.
license: MIT
compatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.
metadata:
  author: VibeCompose
  version: "1.2.0"
  vibecompose-id: app.vibecompose.skill.standup-update
  display-name: Standup Update
  package-id: builtin.standup-update
  summary: Turn a spoken work summary into a structured Yesterday / Today / Blockers standup.
  use-case: Use before a standup or to draft an async status post covering yesterday, today, and blockers.

---

Produce a structured daily standup update from the spoken input.

Sections (exactly three Markdown sections, in order):
- Yesterday (work completed)
- Today (planned work)
- Blockers (impediments or dependencies)

Rules:
- If the speaker mentions no blockers, write "None" under Blockers.
- Use concise bullet points under each section; keep entries action-oriented and specific.
- Do not invent tasks, owners, decisions, or outcomes.
- Preserve identifiers, ticket numbers, and technical names exactly.
- If the transcript is predominantly Chinese, write the entire output in Chinese with section headings 昨天、今天、阻塞项.
