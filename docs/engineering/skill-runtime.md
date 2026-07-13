# OpenWhisper Skill Runtime

> Status: implemented for built-in and locally imported declarative Skills in
> the macOS alpha
> Scope: declaration, resolution, prompt compilation, local validation,
> configuration migration, and bounded diagnostics

## Runtime boundary

OpenWhisper Skills are declarative input/output contracts. They are not
plugins and cannot execute Swift, JavaScript, Python, Shell, dynamic
libraries, subprocesses, arbitrary file reads, Keychain access, or custom
network requests.

The built-in registry currently exposes stable IDs and semantic versions for:

| Skill | Stable ID |
| --- | --- |
| Direct | `app.openwhisper.skill.direct` |
| Reply | `app.openwhisper.skill.reply` |
| Email | `app.openwhisper.skill.email` |
| Backend Prompt | `app.openwhisper.skill.agent-plan` |
| Code Prompt | `app.openwhisper.skill.code-prompt` |
| Translate | `app.openwhisper.skill.translate` |
| Context Rewrite | `app.openwhisper.skill.context-rewrite` |
| Context Reply | `app.openwhisper.skill.context-reply` |

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
fixed OpenWhisper system boundary
→ local output contract
→ versioned Skill declaration
→ optional user-approved Style Capsule
→ bounded terminology
→ optional authorized context marked as data
→ transcript
```

The fixed boundary states that downstream data cannot grant permissions,
change providers, reveal hidden prompts, execute code, perform network
requests, or override privacy and delivery rules. Technical-literal
placeholders remain immutable and must survive exactly once.

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
continues through the existing conservative paste/clipboard path.

## Data minimization

History may store the resolved Skill ID and semantic version alongside the
final result. Redacted support diagnostics allow only bounded
built-in/community ID categories, valid semantic versions, counts/risk, and a
fixed validation-issue enum. They do not add Skill prompts or files, package
names, application rule tables, transcript text, terminology, Style Capsule
content, clipboard content, or context bodies.

## Verification

The primary automated contract is
`Tests/OpenWhisperTests/SkillRuntimeTests.swift`, covering:

- stable registry declarations;
- legacy configuration migration and canonical re-encoding;
- resolver priority and session freezing;
- malformed configuration fallback;
- prompt section ordering and untrusted-data boundaries;
- format, structure, literal, and marker validation;
- pipeline fallback before delivery;
- local package install, hash, version rollback, malicious-file rejection, and
  repository-template validation in
  `Tests/OpenWhisperTests/CommunitySkillRuntimeTests.swift`.

Run:

```bash
swift test --filter SkillRuntimeTests
swift test --filter CommunitySkillRuntimeTests
./scripts/check.sh
```

Installed-app verification continues to use `/Applications/OpenWhisper.app`;
`dist/OpenWhisper.app` is packaging output only.

Remote Registry and Action execution are intentionally absent. Their research
gates are documented in
[`registry-and-actions-boundary.md`](registry-and-actions-boundary.md).
