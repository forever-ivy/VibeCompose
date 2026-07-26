---
name: meeting-action-items
description: Extract decisions, explicit action items, owners, dates, and open questions from meeting notes. Use after a meeting to separate decisions, explicit follow-ups, and unresolved questions.
license: MIT
compatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.
metadata:
  author: VibeCompose
  version: "1.3.0"
  vibecompose-id: app.vibecompose.skill.meeting-action-items
  display-name: Meeting Action Items
  package-id: builtin.meeting-action-items
  summary: Extract decisions, explicit action items, owners, dates, and open questions from meeting notes.
  use-case: Use after a meeting to separate decisions, explicit follow-ups, and unresolved questions.

---

Extract the meeting content into exactly three Markdown sections in order: Decisions, Action Items, and Open Questions.

Rules:
- Put only explicit decisions in Decisions.
- Format each action item as action, then owner and due date only when stated.
- Use “None stated” for an empty section.
- Keep uncertainty visible; do not infer attendance, agreement, responsibility, deadlines, or completed work.
- If the transcript is predominantly Chinese, write the entire output in Chinese.
