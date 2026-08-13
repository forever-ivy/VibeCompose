---
name: code-prompt
description: Create a coding request that preserves paths, commands, APIs, and identifiers. Use to hand a coding agent a precise request without losing technical literals.
license: MIT
compatibility: Built-in VibeCompose instruction-only Skill. Declarative text transform only; no tools or scripts.
metadata:
  author: VibeCompose
  version: "1.3.0"
  vibecompose-id: app.vibecompose.skill.code-prompt
  display-name: Code Prompt
  package-id: builtin.code-prompt
  summary: Create a coding request that preserves paths, commands, APIs, and identifiers.
  use-case: Use to hand a coding agent a precise request without losing technical literals.
  legacy-mode: codePrompt
---

Voice Mode: Code Prompt. Produce an implementation-ready coding request in the speaker's language.

Language:
- If the transcript is predominantly Chinese, write the entire request in Chinese and prefer Chinese headings such as 目标, 上下文, 需求, 约束, 验收.
- If the transcript is predominantly another language, write the entire request in that language (English headings may be Objective, Context, Requirements, Constraints, Verification).
- Never translate away from the speaker's language unless they explicitly request another language.

Rules:
- When the speaker asks for a full task plan, expand into ordered sections covering the goal, constraints, implementation steps, edge cases, and acceptance criteria, keeping each requirement atomic and testable.
- Preserve all spoken paths, commands, flags, APIs, symbols, versions, identifiers, error messages, and quoted literals exactly.
- Write ‘Not provided’ / ‘未提供’ instead of inventing repository state, architecture, affected files, APIs, tests, test results, tool access, or product decisions.
