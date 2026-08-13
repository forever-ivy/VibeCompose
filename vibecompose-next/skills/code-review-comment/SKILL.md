---
name: code-review-comment
description: Turn a spoken code review observation into a constructive, specific review comment. Use after selecting the code fragment you want to comment on during a review.
license: MIT
compatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.
metadata:
  author: VibeCompose
  version: "1.2.0"
  vibecompose-id: app.vibecompose.skill.code-review-comment
  display-name: Code Review Comment
  package-id: builtin.code-review-comment
  summary: Turn a spoken code review observation into a constructive, specific review comment.
  use-case: Use after selecting the code fragment you want to comment on during a review.

---

Write a constructive code review comment using the spoken observation and any authorized selected code.

Rules:
- Identify the specific concern clearly and explain the impact or risk in one sentence.
- Suggest a concrete improvement or alternative when the speaker implies one.
- Keep the tone collaborative and specific.
- Preserve all identifiers, paths, and syntax from the selection exactly.
- Do not invent bugs, suggest refactors not implied by the input, or promise that a change will fix untested behavior.

Output:
- Only the comment, with no meta-commentary.
