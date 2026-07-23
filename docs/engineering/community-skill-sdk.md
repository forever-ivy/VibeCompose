# VibeWhisper Community Skill SDK

> Status: local declarative package import is implemented in the macOS alpha
> Schema: Community Skill v1 / `schemaVersion: 1`
> Runtime boundary: prompts, terminology, localization, examples, and
> app-owned validators only

## 1. What a Community Skill is

A Community Skill is a local `.vibewhisperskill` **directory package** that
describes how VibeWhisper should transform authorized voice and selected-text
input. It is not an executable plugin.

The current runtime can:

- import and inspect a local package;
- install multiple semantic versions;
- select or roll back the active version;
- enable or disable the Skill without deleting it;
- uninstall one version;
- merge the active declaration into the built-in Skill Registry;
- run local Golden-case contract checks;
- show permissions, output policy, validators, reviewed files, and a content
  SHA-256 before or after installation.

The current runtime cannot:

- execute Swift, JavaScript, Python, Shell, WebAssembly, binaries, dynamic
  libraries, or scripts;
- launch processes;
- read arbitrary files, Keychain items, the whole screen, browser DOM,
  clipboard, terminal history, or an entire document;
- make package-defined network requests or change the configured provider;
- request `externalAction`, emit `actionPreview`, or directly create, send,
  update, or delete external objects;
- bypass selection consent, sensitive-app denial, Preview, Validators, safe
  paste checks, History/Recovery policy, or redacted diagnostics.

## 2. Quick start

Copy the repository example:

```bash
cp -R \
  examples/skills/IssueDraft.vibewhisperskill \
  /tmp/MyIssueDraft.vibewhisperskill
```

Edit its ID, version, name, prompt, validators, examples, and terminology.
Then open:

```text
VibeWhisper Settings
→ AI Polish
→ Local Community Skills
→ Import Skill…
```

Choose the `.vibewhisperskill` directory, review the declared permissions,
files, output policy, and SHA-256, then install it.

The maintained example is:

- [`examples/skills/IssueDraft.vibewhisperskill`](../../examples/skills/IssueDraft.vibewhisperskill)

## 3. Package layout

```text
MySkill.vibewhisperskill/
  skill.yaml                 required
  prompt.md                  required
  terminology.csv            optional
  validators.json            optional
  examples.jsonl             optional
  localizations/
    en.json                  optional
    zh-Hans.json             optional
  tests/
    golden.jsonl             optional
```

No other file or directory is accepted. `.DS_Store` is ignored.

Hard limits:

| Limit | Value |
| --- | ---: |
| Files | 64 |
| One file | 256 KiB |
| Complete package | 1 MiB |
| `skill.yaml` | 64 KiB and 1,000 lines |
| `prompt.md` | 64 KiB and 1–40,000 readable characters |
| JSONL records per file | 200 |
| Skill-local terminology entries | 1,000 |

Every accepted file must be a local regular file, UTF-8 where text is
required, non-symlinked, and have no executable bit. VibeWhisper rejects path
traversal, unsupported nesting, shebang content, known executable extensions,
Mach-O magic bytes, unknown files, oversized input, and packages that change
while being copied.

## 4. `skill.yaml`

VibeWhisper intentionally parses a constrained YAML subset:

- spaces only, with 0 / 2 / 4-space indentation;
- scalar values and simple lists;
- no tags, anchors, aliases, tabs, multiline blocks, or custom object graphs;
- no duplicate or unknown declarations.

Minimal example:

```yaml
schemaVersion: 1
id: com.example.vibewhisper.issue-draft
version: 1.0.0
name: Issue Draft
author: Example Publisher
minimumAppVersion: 0.1.0

permissions:
  required:
    - voice
  optional:
    - selection
    - styleCapsule

output:
  format: markdown
  delivery: previewThenPaste
  risk: medium

validators:
  requireNonEmpty: true
  maximumCharacters: 12000
  preserveTechnicalLiterals: true
  requireClosedMarkdownFences: true
  requiredSections:
    - Goal
    - Context
    - Acceptance Criteria
```

### Identity and compatibility

| Field | Rule |
| --- | --- |
| `schemaVersion` | Must be `1` |
| `id` | Lowercase reverse-domain style; letters, digits, dots, and hyphens; at most 160 UTF-8 bytes |
| `id` namespace | Must not use the reserved `app.vibewhisper.skill.*` prefix |
| `version` | Semantic version such as `1.2.0` or `1.2.0-beta.1`; at most 64 UTF-8 bytes with bounded numeric components |
| `minimumAppVersion` | Semantic version and not newer than the running app |
| `name` | Required, at most 120 characters |
| `author` | Optional, at most 120 characters; defaults to `Community` |

### Permissions

Community Skill v1 supports:

| Capability | Declaration | Runtime behavior |
| --- | --- | --- |
| Voice | Required | Must be present in `permissions.required` |
| Selected text | Optional | Must be in `permissions.optional`; the user still controls Ask / Always / Never |
| Writing Style | Optional | Must be in `permissions.optional`; only a user-approved assignment is injected |

`selection` and `styleCapsule` cannot be required. The current version rejects
`focusedParagraph`, `conversationWindow`, `clipboard`, and `externalAction`.

### Output contract

Supported formats:

- `plainText`
- `markdown`
- `code`
- `json`
- `template`

Supported delivery policies:

- `automaticPasteWhenVerified`
- `previewThenPaste`
- `copyOnly`

Supported risk levels:

- `low`
- `medium`
- `high`

Only a low-risk Community Skill may request
`automaticPasteWhenVerified`. Medium- and high-risk packages must Preview or
copy. A high-risk Domain Pack can force Preview even when the base Skill
requests a lower-friction route. `actionPreview` is rejected.

### Accepted forward-compatible metadata

`description`, `homepage`, `license`, `triggers.*`, and `context.*` are
accepted by the constrained manifest parser, but Community Skill v1 does not
use them to grant authority. In particular:

- `triggers.defaultForBundleIdentifiers` does not create App Rules;
- `context.maximumCharacters` does not override the app-owned selection
  budget;
- `context.includeSelectionOnly` does not add a new context provider.

Users configure App Rules and context grants in VibeWhisper Settings.

## 5. `prompt.md`

`prompt.md` defines writing shape, not authority. Keep it specific:

- state the intended output;
- list required sections or formatting;
- define what must be preserved;
- define what must not be invented;
- describe how authorized selection should be treated;
- avoid instructions about providers, credentials, hidden prompts, local
  files, network requests, process execution, or delivery.

At runtime, VibeWhisper compiles content in this fixed order:

```text
VibeWhisper safety and factual-fidelity shell
→ local output contract
→ untrusted Skill prompt
→ optional user-approved Writing Style
→ resolved terminology
→ authorized selected text marked as data
→ transcript
```

The package cannot move itself ahead of the safety shell. A prompt that says
“ignore previous instructions” remains untrusted text and gains no additional
capability.

## 6. `terminology.csv`

Use the same structured CSV format as the personal dictionary:

```csv
type,original,replacement,enabled,aliases
term,OpenAPI,,true,open api
correction,kuber netes,Kubernetes,true,k8s
```

Rules:

- `term` preserves canonical spelling and casing;
- `correction` requires a replacement;
- aliases are optional;
- installed entries are scoped to the Skill;
- VibeWhisper assigns deterministic local IDs and the source
  `skill:<skill-id>`;
- duplicate or invalid entries are normalized or dropped by the app-owned
  terminology pipeline.

Runtime precedence is:

```text
user explicit correction
> Skill-local terminology
> user normal terminology
> enabled Domain Pack
> ASR hints / original result
```

## 7. `validators.json`

`validators.json` overrides the inline manifest validator values and must be a
JSON object containing only:

```json
{
  "requireNonEmpty": true,
  "maximumCharacters": 12000,
  "preserveTechnicalLiterals": true,
  "requireClosedMarkdownFences": true,
  "requiredSectionAlternatives": [
    ["Goal", "目标"],
    ["Acceptance Criteria", "验收标准"]
  ],
  "forbiddenPhrases": [
    "I accessed your files"
  ]
}
```

Supported app-owned checks:

- non-empty output;
- maximum character count, clamped to 1–100,000;
- parseable JSON when `output.format` is `json`;
- balanced triple-backtick Markdown fences;
- at least one label from every required-section alternative group;
- every protected technical literal appears exactly once;
- forbidden phrase absence;
- no internal VibeWhisper marker or selection tag leakage.

Community packages cannot provide executable validators. If validation fails,
the model result is not delivered; VibeWhisper falls back to normalized ASR
before the existing Preview/paste/clipboard boundary.

## 8. Localization, examples, and Golden cases

### `localizations/<locale>.json`

Each file must be a JSON object with at most 500 string-to-string entries.
Community Skill v1 currently reads `name`, preferring the selected app
localization and then `en`.

```json
{
  "name": "Issue Draft"
}
```

### `examples.jsonl`

Each non-empty line must be valid JSON. The current app validates and reviews
the file but does not send examples automatically to the provider.

### `tests/golden.jsonl`

Each line uses:

```json
{"name":"basic","transcript":"Create an issue for /api/users.","selectedText":"Optional source text","expectedOutput":"# Goal\nFix /api/users.\n\n# Acceptance Criteria\n- The reported case is covered."}
```

Fields:

| Field | Required | Purpose |
| --- | --- | --- |
| `name` | No | Human-readable case name |
| `transcript` | Yes | Spoken input used for literal checks |
| `selectedText` | No | Authorized selection used for literal checks |
| `expectedOutput` | Yes | Candidate output validated locally |

The current Golden runner is a deterministic **contract check**, not a live
model quality benchmark. It proves that:

- the fixed safety shell still precedes the package prompt;
- `expectedOutput` satisfies the declared output and validator contract.

It does not call a provider or compare a live model response.

## 9. Installation, versions, and rollback

Packages are installed under:

```text
~/Library/Application Support/VibeWhisper/Skills/Installed/
  <skill-id>/
    <semantic-version>/
```

VibeWhisper writes directories as `0700`, files as `0600`, and computes a
SHA-256 over the sorted relative file paths and bytes. Installation copies
into a private temporary directory, re-inspects the copy, verifies the
definition and hash, and only then atomically moves the version into place.

One version per Skill ID is active in the Registry. Installing a second
version keeps the first version available. Select an older **Active Version**
to roll back. The separate Skill toggle disables resolution without deleting
installed files.

If the configured version is missing, the loader chooses the highest valid
installed semantic version. If an installed package is damaged or cannot be
loaded, it is reported as blocked; unresolved defaults and App Rules preserve
their IDs in configuration but resolve safely to built-in Direct at runtime.

## 10. Privacy and diagnostics

Support diagnostics may record only bounded counts and risk indicators, such
as installed Community Skill count, active Skill ID category, validator issue
code, enabled terminology count, and whether a high-risk pack is enabled.

They do not include:

- `prompt.md`;
- package files or package names;
- transcript, selected text, Preview content, or clipboard content;
- Writing Style summaries, examples, or source samples;
- terminology text;
- full App Rules;
- custom endpoints, credentials, or tokens.

Snapshot acceptance mode does not read real locally installed Skills or Style
Capsules.

## 11. Author checklist

Before distributing a local package:

1. use an ID you control and increment a valid semantic version;
2. keep `voice` required and all other supported capabilities optional;
3. request only the smallest output risk and delivery policy that is safe;
4. keep technical-literal preservation enabled unless the transformation
   genuinely requires changing supplied literals;
5. include bilingual required-section alternatives where practical;
6. add at least one Golden case for structure and one for literal
   preservation;
7. inspect the package in VibeWhisper and review every listed file;
8. run Golden tests from Skill Inspector;
9. test Preview, copy fallback, disabled state, version rollback, and
   uninstall;
10. never instruct users to add executable files or manually write inside the
    private installed-Skills directory.

Repository verification:

```bash
swift test --filter CommunitySkillRuntimeTests
python3 scripts/verify_repository_hygiene.py
```
