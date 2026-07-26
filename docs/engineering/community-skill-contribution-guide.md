# Community Skill Contribution Guide

VibeCompose accepts Agent Skills standard directories or ZIP archives for local
testing. `SKILL.md` is the only required public entry. An optional
`vibecompose.yaml` may declare the Host Profile; it does not create a second
Skill definition.

This guide prepares curated Community Pilot content. It is not a public Registry
submission process.

## Quality gate

A candidate must:

- solve one clear, repeatable output task;
- explain when to use it in plain language;
- include at least two normal examples and one boundary or failure example;
- declare Required and Optional Context truthfully;
- use Preview or copy-only delivery when risk or target uncertainty requires it;
- preserve technical literals and define local Validators appropriate to the
  output contract;
- include reproducible Golden cases;
- provide complete English or Simplified Chinese user copy and explicitly mark
  the other language as unavailable if it is not authored;
- pass install, Test Bench, export, re-import, rollback, and uninstall checks;
- avoid unexplained permission, output-policy, risk, resource, or Validator
  expansion between revisions.

VibeCompose rejects or disables Skills that depend on executable scripts,
Shell, Hooks, MCP, Subagents, custom network access, arbitrary files, Keychain,
or external Actions. Packaging such files for another Host never makes them
executable in VibeCompose.

## Authoring flow

1. Open Skill Library → Created → New or Fork.
2. In Simple mode, write the portable name, purpose, when-to-use guidance, and
   input/output examples.
3. Choose only the Context needed by the task and the least-powerful delivery
   policy that works.
4. Run text and temporary voice samples in Test Bench.
5. Test empty, ambiguous, oversized, malformed, and missing-Context inputs.
6. Inspect the layered Prompt plan, data categories, budget, compatibility, and
   Validator result.
7. Save reviewed examples as Golden cases only after checking their exact
   content. Never save private participant data.
8. Install locally, use the Skill against a disposable editable target, and
   verify History and rollback behavior.
9. Export an Agent Skills standard directory or ZIP and re-import it. The
   portable name, revision, resources, and digest must remain stable.

## Required review notes

Provide these notes with a Pilot candidate:

- task and user pain addressed;
- before/after examples and the boundary example;
- Required/Optional Context rationale;
- requested and forced delivery policy;
- risk level and any professional-review warning;
- Validator and Golden-case coverage;
- resources included and why each is needed;
- compatibility limitations;
- revision changes, including permission, risk, delivery, and Validator diffs.

Do not include test audio, participant text, selection content, Writing Styles,
private terminology, History, credentials, or local paths.

## Reviewer checklist

- The package passes the same local scanner used for imports.
- `SKILL.md` describes one primary output behavior.
- The ordinary install review explains purpose, examples, Context, output, and
  risk without requiring hashes or YAML knowledge.
- Advanced Inspector accurately reports resources and ignored/quarantined
  features.
- Required Context blocks before Provider use; Optional Context degrades with a
  visible receipt.
- Validator fallback is explicit and cannot be applied without review.
- Target changes produce copy-only behavior.
- An update with expanded Context requires authorization again.
- A failed update leaves the active version intact and at least one previous
  version remains available for rollback.

Only the product owner can mark a candidate as curated for a Pilot build.
