# VibeWhisper Registry, Connectors, and Action Boundary

> Status: Phase 6 research boundary completed; Registry and Action execution
> are not enabled in the current macOS alpha

## 1. Decision

VibeWhisper may later distribute declarative Skills through a Registry and may
later support a small set of external actions through app-owned Connectors.
Neither feature is allowed to turn a Skill package into arbitrary code or a
general automation runtime.

The current shipping boundary remains:

- local `.vibewhisperskill` directory import only;
- no remote Registry fetch or automatic package update;
- no publisher trust badge;
- no package-defined network endpoint;
- no `externalAction` capability;
- no `actionPreview` output;
- no arbitrary Shell, process, dynamic library, file-system, Keychain,
  browser-DOM, MCP, or custom-network access.

## 2. Registry trust model

The Registry is a distribution index, not a runtime authority. A future
Registry record should contain only:

- immutable Skill ID and semantic version;
- app compatibility range;
- package byte count and SHA-256;
- declared capabilities, output contract, and risk;
- publisher key identifier and signature metadata;
- source/repository and license metadata;
- reproducible Golden-test status;
- publication, deprecation, and revocation state.

Installing a Registry package must reuse the same local package inspector,
limits, copy-then-reinspect flow, prompt boundary, validators, permissions, and
safe output routing as local import. Registry provenance must never bypass a
local safety check.

## 3. Publisher signatures

Recommended signing envelope:

```text
canonical registry record
+ exact package SHA-256
+ Skill ID
+ semantic version
+ minimum app version
+ declared capability/output digest
→ Ed25519 signature
```

Requirements:

- publishers sign offline with a key not stored by the app;
- the Registry stores public keys and key history, never private keys;
- signature verification happens before package installation;
- package SHA-256 is re-computed locally after download and after private
  copying;
- signatures bind the exact Skill ID and version to prevent substitution;
- key rotation uses an old-key transition signature or an operator-reviewed
  recovery process;
- a “verified publisher” label proves identity and artifact continuity only,
  not output correctness or professional suitability.

VibeWhisper should support more than one trusted Registry root so product
safety does not depend on one long-lived key.

## 4. Hashing, caching, and reproducibility

Future Registry downloads should be content-addressed:

```text
Skills/Cache/<sha256>.vibewhisperskill
```

The app should:

1. download to an owner-only temporary file or directory;
2. enforce a strict byte limit during transfer;
3. verify transport HTTPS separately from artifact authenticity;
4. verify the signed Registry record;
5. verify the downloaded hash;
6. inspect the full package with the existing Community Skill v1 loader;
7. copy into the private installed-version directory;
8. inspect and hash the installed copy again;
9. activate only after every stage succeeds.

Golden cases remain deterministic contract tests. A Registry may publish
reproducible test evidence, but VibeWhisper must not treat model-quality claims
as a security signature.

## 5. Deprecation, revocation, and takedown

Registry state should distinguish:

| State | Installed behavior |
| --- | --- |
| Published | Normal install/update eligibility |
| Deprecated | Existing version may run; UI recommends a replacement |
| Quarantined | New installs and activation blocked pending review |
| Revoked | Version disabled locally after signed policy verification |
| Removed | Hidden from discovery; signed historical metadata retained |

Rules:

- a takedown or revocation document must itself be signed and revisioned;
- rollback/replay of older Registry state must be rejected;
- emergency revocation can disable a package but cannot delete user data or
  silently install a replacement;
- users should see the affected ID, version, reason category, effective date,
  and available safe alternatives;
- local-only packages outside the Registry are not remotely deleted;
- professional or malicious-content reports need a documented appeal and
  restoration path;
- revocation telemetry remains local unless the user explicitly submits a
  report.

## 6. Connector architecture

A future Connector is app-owned, reviewed code shipped with VibeWhisper. A
Skill can request a typed action intent, but it never receives credentials or
direct network access.

```text
voice + authorized context
→ declarative Skill result
→ local Validator
→ typed Action Draft
→ app-owned Connector Broker
→ Action Preview
→ explicit user confirmation
→ allowlisted Connector
→ result receipt / safe retry
```

Connector Broker responsibilities:

- expose a finite typed operation list, such as `github.createIssue`;
- validate every field against an app-owned schema;
- resolve the exact account, organization, workspace, repository, project, or
  database locally;
- keep OAuth tokens or API keys in Keychain under a Connector-specific
  service;
- use fixed HTTPS origins and routes owned by the Connector implementation;
- prevent redirects to unapproved origins;
- enforce per-operation rate, size, and timeout limits;
- produce a bounded local receipt without storing unrelated response bodies.

No generic HTTP Connector, arbitrary URL field, Shell Connector, file-system
Connector, or “run any MCP tool” capability belongs in the first Action
release.

## 7. Action Preview contract

Action Preview is a separate confirmation surface, not a Markdown simulation.
It must show:

- Connector and operation;
- account identity;
- destination organization/workspace/repository/project;
- object type and target;
- every field that will be written;
- attachment names and byte counts, if a future operation supports them;
- whether the action is reversible;
- duplicate/idempotency warning;
- validation and permission state.

Confirmation rules:

- every write requires an explicit user action;
- a Preview expires when the target account, destination, fields, or source
  context changes;
- retry after an uncertain network result must first query by an idempotency
  key or show an “outcome unknown” state;
- destructive actions require a stronger confirmation and should not be in
  the first Connector set;
- `Esc` cancels and never executes;
- a Skill cannot hide fields, pre-confirm, or change the Connector after
  Preview opens.

## 8. Permission model

Permissions should be scoped by:

```text
Connector
× account
× operation
× destination
× session or persistent grant
```

Example:

```text
GitHub
× user@example.com
× createIssue
× forever-ivy/vibewhisper
× allow once
```

Read and write permissions must be separate. A user may authorize repository
metadata lookup without authorizing issue creation. Selection, clipboard,
window, document, and Writing Style access remain separate Context Broker
capabilities and are not implied by Connector authorization.

## 9. Initial Connector candidates

Research priority:

1. GitHub Issue creation;
2. Linear Issue creation;
3. Notion page draft creation.

Each candidate must have:

- a narrow and stable API surface;
- explicit account and destination selection;
- a typed create-only operation;
- idempotency or duplicate detection;
- a clear human-readable Preview;
- no arbitrary query language;
- no attachment upload in the first iteration;
- installed-app permission, cancellation, offline, rate-limit, duplicate, and
  uncertain-result acceptance coverage.

Slack send, Jira mutation, Git execution, Shell/SQL, and generic MCP are
deferred because their destination ambiguity or impact is materially higher.

## 10. Release gates for Registry or Actions

Do not enable Registry installation until all are true:

- signed index/envelope format and key rotation are implemented;
- package download, hash, reinspection, cache, rollback, quarantine, and
  revocation tests pass;
- publisher identity and reporting/takedown operations exist;
- privacy and support documents describe remote discovery metadata;
- installed-app update and incident drills are complete.

Do not enable external actions until all are true:

- a separate `externalAction` permission store exists;
- Action Draft has an app-owned schema and Validator;
- Action Preview is implemented and cannot be bypassed;
- Connector credentials are isolated in Keychain;
- origins, paths, redirects, timeouts, sizes, and retries fail closed;
- idempotency and uncertain outcomes are handled;
- sensitive-app and context boundaries remain enforced;
- audit/diagnostic records are redacted and bounded;
- the complete installed-app confirmation/cancel/retry matrix passes.

Until then, manifests declaring `externalAction` or `actionPreview` must
continue to fail import.
