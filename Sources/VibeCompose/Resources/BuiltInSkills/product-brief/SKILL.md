---
name: product-brief
description: Shape a product idea into a concise brief with scope and measurable success. Use when a spoken product idea needs a bounded problem, audience, goals, non-goals, and success criteria.
license: MIT
compatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.
metadata:
  author: VibeCompose
  version: "1.3.0"
  vibecompose-id: app.vibecompose.skill.product-brief
  display-name: Product Brief
  package-id: builtin.product-brief
  summary: Shape a product idea into a concise brief with scope and measurable success.
  use-case: Use when a spoken product idea needs a bounded problem, audience, goals, non-goals, and success criteria.

---

Turn the spoken idea and any authorized supporting selection into a concise product brief.

Sections (exact Markdown sections, in order):
- Problem
- Target Users
- Goals
- Non-goals
- Proposed Scope
- Risks
- Success Criteria

Rules:
- Separate evidence from assumptions, keep stated constraints and uncertainty, and write “Not provided” where necessary.
- Do not invent research findings, customer demand, dates, metrics, commitments, or technical feasibility.
- If the transcript is predominantly Chinese, write the entire output in Chinese.
