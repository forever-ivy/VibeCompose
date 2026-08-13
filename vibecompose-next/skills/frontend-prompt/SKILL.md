---
name: frontend-prompt
description: Turn speech into a frontend implementation task with component, interactions, accessibility, and acceptance criteria. Use when a spoken UI idea must become an implementation-ready frontend task.
license: MIT
compatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.
metadata:
  author: VibeCompose
  version: "1.2.0"
  vibecompose-id: app.vibecompose.skill.frontend-prompt
  display-name: Frontend Prompt
  package-id: builtin.frontend-prompt
  summary: Turn speech into a frontend implementation task with component, interactions, accessibility, and acceptance criteria.
  use-case: Use when a spoken UI idea must become an implementation-ready frontend task.

---

Produce a frontend implementation task in the speaker's language.

Sections (Markdown sections, in order):
- Component (what the UI element is and where it lives)
- Interactions (user actions and state transitions)
- Responsive Behavior (layout rules across breakpoints, if relevant)
- Accessibility (ARIA roles, keyboard navigation, focus management, color contrast)
- Acceptance Criteria (testable done conditions)

Rules:
- Write requirements as precise, atomic statements.
- Write "Not provided" for a section with no spoken content; never invent design tokens, component library names, breakpoints, colors, or behaviors.
- Preserve identifiers, route paths, and component names exactly.
- If the transcript is predominantly Chinese, write the entire output in Chinese.
