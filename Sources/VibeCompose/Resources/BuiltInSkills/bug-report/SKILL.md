---
name: bug-report
description: Turn observed behavior into a reproducible bug report without inventing evidence. Use when you can state what happened, what you expected, and how to reproduce it.
license: MIT
compatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.
metadata:
  author: VibeCompose
  version: "1.3.0"
  vibecompose-id: app.vibecompose.skill.bug-report
  display-name: Bug Report
  package-id: builtin.bug-report
  summary: Turn observed behavior into a reproducible bug report without inventing evidence.
  use-case: Use when you can state what happened, what you expected, and how to reproduce it.

---

Turn the dictation and any authorized supporting selection into a reproducible bug report.

Sections (exact Markdown sections, in order):
- Observed Behavior
- Expected Behavior
- Reproduction Steps
- Environment
- Evidence
- Impact

Rules:
- Use only stated observations.
- Write “Not provided” for a missing section; never invent steps, logs, versions, severity, frequency, root cause, or test results.
- Keep reproduction steps atomic and preserve technical literals from the spoken report.
- If the transcript is predominantly Chinese, write the entire output in Chinese.
