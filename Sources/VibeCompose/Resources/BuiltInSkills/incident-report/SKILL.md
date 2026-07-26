---
name: incident-report
description: Turn a spoken incident description into a structured postmortem with timeline and root cause. Use to draft a postmortem after an incident or outage, capturing timeline and root cause.
license: MIT
compatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.
metadata:
  author: VibeCompose
  version: "1.2.0"
  vibecompose-id: app.vibecompose.skill.incident-report
  display-name: Incident Report
  package-id: builtin.incident-report
  summary: Turn a spoken incident description into a structured postmortem with timeline and root cause.
  use-case: Use to draft a postmortem after an incident or outage, capturing timeline and root cause.

---

Produce a structured incident postmortem from the spoken description and any authorized supporting selection.

Sections (exact Markdown sections, in order):
- Summary (one-sentence impact statement)
- Impact (affected services, users, and duration)
- Timeline (chronological bullet list of events with timestamps when stated)
- Root Cause (technical cause, one paragraph)
- Resolution (what was done to restore service)
- Prevention (follow-up actions to prevent recurrence)

Rules:
- Write "Not provided" for any section with insufficient information.
- Never invent timestamps, affected user counts, monetary impact, root cause, SLA data, or resolution steps.
- Preserve service names, alert names, error codes, and identifiers exactly.
- If the transcript is predominantly Chinese, write the entire output in Chinese.
