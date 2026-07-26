# VibeCompose Skill Runtime

> Status: implemented for built-in and locally imported declarative Skills in
> the macOS alpha
> Scope: declaration, resolution, prompt compilation, local validation,
> configuration migration, and bounded diagnostics

## Runtime boundary

VibeCompose Skills are declarative input/output contracts. They are not
plugins and cannot execute Swift, JavaScript, Python, Shell, dynamic
libraries, subprocesses, arbitrary file reads, Keychain access, or custom
network requests.

The built-in registry currently exposes 13 stable declarations at version
`1.1.0`:

| Skill | Stable ID | Context | Output / delivery | Scenario validator |
| --- | --- | --- | --- | --- |
| Direct | `app.vibecompose.skill.direct` | Voice | Plain text / automatic when verified / low | Non-empty, bounded, spoken technical literals |
| Reply | `app.vibecompose.skill.reply` | Voice; optional Style | Plain text / automatic when verified / low | 4,000 characters, spoken technical literals |
| Email | `app.vibecompose.skill.email` | Voice; optional Style | Plain text / Preview / medium | 8,000 characters, spoken technical literals |
| Backend Prompt | `app.vibecompose.skill.agent-plan` | Voice; optional Style | Markdown / Preview / medium | Goal, Constraints, Implementation Steps, Edge Cases, Acceptance Criteria; closed fences |
| Code Prompt | `app.vibecompose.skill.code-prompt` | Voice; optional Style | Markdown / Preview / medium | Closed fences, spoken technical literals |
| Translate | `app.vibecompose.skill.translate` | Voice; optional Style | Plain text / Preview / medium | Spoken technical literals |
| Context Rewrite | `app.vibecompose.skill.context-rewrite` | **Required Voice + Selection**; optional Style | Plain text / Preview / medium | Selected-source technical literals |
| Context Reply | `app.vibecompose.skill.context-reply` | **Required Voice + Selection**; optional Style | Plain text / Preview / medium | 5,000 characters; no forced echo of source literals |
| Bug Report | `app.vibecompose.skill.bug-report` | Voice; optional Selection + Style | Markdown / Preview / medium | Six required report sections, 8,000 characters, closed fences |
| Commit Message | `app.vibecompose.skill.commit-message` | Voice; optional Selection + Style | Plain text / Preview / medium | 1,000 characters, spoken technical literals |
| Meeting Action Items | `app.vibecompose.skill.meeting-action-items` | Voice; optional Selection + Style | Markdown / Preview / medium | Decisions, Action Items, Open Questions; 8,000 characters, closed fences |
| Product Brief | `app.vibecompose.skill.product-brief` | Voice; optional Selection + Style | Markdown / Preview / medium | Seven required brief sections, 8,000 characters, closed fences |
| Customer Support Reply | `app.vibecompose.skill.customer-support-reply` | Voice; optional Selection + Style | Plain text / Preview / medium | 5,000 characters, spoken technical literals, unsupported-guarantee phrases |

## Built-in configuration source

The app-owned declarations are reviewed **Agent Skills standard packages**, not
downloaded prompts and not a second Community format:

- Each built-in Skill is a directory under
  `Sources/VibeCompose/Resources/BuiltInSkills/<portable-name>/` containing
  required `SKILL.md` (YAML frontmatter + instructions) and optional
  `vibecompose.yaml` Host Profile, plus Skill-local `terminology.csv` when
  needed.
- `BuiltInSkillCatalog` in `Sources/VibeCompose/AgentSkillRuntime.swift` loads
  those packages in a fixed order, maps reserved
  `metadata.vibecompose-id` values (`app.vibecompose.skill.*`) into
  `SkillDefinition`, and feeds `SkillRegistry.builtIn`.
- `DictationMode.promptInstruction` in `Sources/VibeCompose/VoiceModes.swift`
  reads the same loaded instructions for the six legacy-mapped Skills so old
  Voice Mode storage continues to decode without a second prompt source of
  truth.
- `SkillDefinition.localizedSummary` and `localizedUseCase` expose public task
  copy without revealing the internal prompt.
- `SkillDiscoveryDetail.exampleValues` owns reviewed UI examples. Contract
  examples must be reviewed with any prompt or validator update; automated
  contract tests cover the runtime declaration and representative outputs.

Package layout for each built-in Skill:

```text
Sources/VibeCompose/Resources/BuiltInSkills/<portable-name>/
  SKILL.md              required (name, description, metadata, instructions)
  vibecompose.yaml      Host Profile (context, output, validators, resources)
  terminology.csv       optional Skill-local terms
```

`scripts/package_app.sh` copies `Sources/VibeCompose/Resources` into the app
bundle so packaged builds resolve `BuiltInSkills` via `Bundle.main`. Debug and
`swift test` resolve the same tree relative to the source file or the
repository root.

Bundled Skill installation IDs intentionally keep the original `1.0.0`
identity seed while `version` and `revision` advance. This preserves Favorites,
App Defaults, and Global Default references across app upgrades without
misreporting which declaration a frozen run used. Imported and Community Skill
installation identities remain revision-specific.

The legacy `agentPlan` storage value remains mapped to the Backend Prompt
Skill so existing user configuration and historical records continue to
decode.

Community Skill v1 can merge one active installed semantic version per
third-party Skill ID into this Registry. Package loading remains declarative
and reuses the same resolver, Prompt Compiler, Validator, Context Broker,
Preview, and output routing. See
[`community-skill-sdk.md`](community-skill-sdk.md).

## Resolution and session freezing

`SkillResolver` uses this priority:

1. explicit manual Skill for the current invocation;
2. enabled exact bundle-identifier application rule;
3. configured global default;
4. built-in Direct fallback.

`AppCoordinator` captures the foreground application before recording and
stores one `ResolvedSkillExecutionPlan` in the per-session transcription
configuration. Switching applications while recording therefore cannot
change the Skill ID, version, output contract, or resolution source for the
active session.

Only the resolved runtime configuration reaches the processing pipeline. The
full application-rule table remains local.

## Configuration migration

`TranscriptionConfig` decodes the canonical `skills` object first. When it is
absent, the decoder migrates the legacy `voiceModes` object:

```text
default mode → stable built-in Skill ID
application mode rule → AppSkillRule
unknown or disabled Skill → Direct
```

New writes contain `skills` and omit `voiceModes`. A source-level compatibility
property remains for one migration cycle so older tests and internal call
sites can be retired incrementally without changing the persisted schema.

## Prompt compilation

`SkillPromptCompiler` always emits sections in this order:

```text
fixed VibeCompose system boundary
→ local output contract
→ versioned Skill declaration
→ approved runtime-visible Skill resources
→ optional user-approved Writing Style
→ bounded terminology
→ optional authorized context marked as data
→ transcript
```

The fixed boundary states that downstream data cannot grant permissions,
change providers, reveal hidden prompts, execute code, perform network
requests, or override privacy and delivery rules. Technical-literal
placeholders remain immutable and must survive exactly once.

Input roles are explicit:

- for ordinary and optional-Context Skills, voice is the primary content and
  selected text is supporting Context; optional Context literals are not all
  forced into a summary, reply, or commit message;
- when Selection is required, Selection is the primary source and voice is a
  transformation instruction. Technical literals in that instruction are not
  immutable output content; selected-source literals remain locally checked.

The same distinction drives Preview: only a required-selection Skill uses the
selection as its Diff source or may offer **Replace Selection**. Optional
selection remains supporting Context, so summaries, reports, and replies are
compared with the spoken request and cannot overwrite the supporting source.

## Local validation and fallback

`SkillValidatorEngine` supports only app-owned declarative checks:

- non-empty output;
- maximum character count;
- parseable JSON;
- closed Markdown fences;
- required section alternatives;
- protected technical literals;
- forbidden phrases;
- internal prompt/context marker leakage.

When validation fails, `DictationPipeline` does not deliver the model output.
It uses the already normalized ASR result, records bounded issue codes, and
forces Preview. The fallback can be copied, but replacement/paste stays
disabled until the user edits it into output that passes the Skill contract.

The generic suspicious-truncation fallback applies only to Direct. Structured
and extraction Skills may intentionally compress a long dictation; their
versioned output contract, local Validator, Preview, and explicit delivery
policy govern acceptance instead.

## Data minimization

History may store the resolved Skill ID and semantic version alongside the
final result. Redacted support diagnostics allow only bounded
built-in/community ID categories, valid semantic versions, counts/risk, and a
fixed validation-issue enum. They do not add Skill prompts or files, package
names, application rule tables, transcript text, terminology, Writing Style
content, clipboard content, or context bodies.

## Verification

The primary automated contract is
`Tests/VibeComposeTests/SkillRuntimeTests.swift`, covering:

- stable registry declarations;
- legacy configuration migration and canonical re-encoding;
- resolver priority and session freezing;
- malformed configuration fallback;
- prompt section ordering and untrusted-data boundaries;
- format, structure, literal, and marker validation;
- pipeline fallback before delivery;
- local package install, hash, version rollback, malicious-file rejection, and
  repository-template validation in
  `Tests/VibeComposeTests/CommunitySkillRuntimeTests.swift`.

Run:

```bash
swift test --filter SkillRuntimeTests
swift test --filter CommunitySkillRuntimeTests
./scripts/check.sh
```

Installed-app verification continues to use `/Applications/VibeCompose.app`;
`dist/VibeCompose.app` is packaging output only.

Remote Registry and Action execution are intentionally absent. Their research
gates are documented in
[`registry-and-actions-boundary.md`](registry-and-actions-boundary.md).
