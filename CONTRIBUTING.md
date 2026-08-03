# Contributing to VibeCompose

Thank you for helping build this independent, unofficial community project.
Contributions are accepted under the repository's MIT License.

By participating, you agree to uphold our [Code of Conduct](CODE_OF_CONDUCT.md).

## Start Here

```bash
git clone https://github.com/forever-ivy/vibecompose.git
cd vibecompose
./scripts/build_and_run.sh
```

This one command packages, installs, and launches
`/Applications/VibeCompose.app`. Run the full pre-submit gate with:

```bash
./scripts/check.sh
```

Source builds require macOS 13 or later and Xcode Command Line Tools. If no
Apple development identity is available, prefix local commands with
`VIBECOMPOSE_ALLOW_ADHOC_SIGNING=1`.

## Development Flow

1. Run `./scripts/check.sh` before submitting changes.
2. Use `./scripts/build_and_run.sh` to validate the installed app path.
3. Keep `product.env` as the source of truth for product identity.
4. Keep `version.env` as the source of truth for release version metadata.
5. Update documentation when changing permissions, provider behavior, storage, packaging, startup, release assets, or public claims.
6. Write commit messages using the [Git Commit Messages](#git-commit-messages) rules below.

## Engineering Standards

- Keep the app macOS-native and keyboard-first.
- Preserve the single-trigger `F5` start/stop workflow.
- Keep the Public Alpha UI on the single ChatGPT OAuth provider path.
- Paste only when a current editable target is verified; otherwise preserve the transcript in the clipboard.
- Treat tokens, audio, transcripts, and recovery files as sensitive data.
- Keep undocumented upstream dependencies explicit in product copy and error handling.
- Do not add a second product identity, legacy brand alias, or compatibility path without an approved migration requirement.

## OAuth and Network Changes

The current login flow is OAuth 2.0 Authorization Code with PKCE and a
loopback callback. Before changing authentication or ChatGPT requests, read
[ChatGPT OAuth](docs/engineering/chatgpt-oauth.md) and
[Privacy data flow](docs/engineering/privacy-data-flow.md).

- Never commit or print access tokens, refresh tokens, ID tokens, cookies, or
  authorization headers.
- Keep managed requests pinned to approved HTTPS `chatgpt.com` paths.
- Preserve callback state, PKCE, timeout, duplicate-parameter, redirect, and
  session-generation checks.
- Update the README, privacy policy, tests, and installed-app acceptance when
  request contents or retention behavior changes.

## Issues and Pull Requests

- Search existing issues before opening a duplicate.
- Include the macOS version, VibeCompose version, installed app path,
  permission state, minimal reproduction, expected result, and actual result.
- Keep pull requests focused and explain the user-visible behavior and
  verification performed.
- Add tests for behavior changes and documentation for new user-visible data
  flow.
- Do not attach ChatGPT tokens, cookies, API credentials, recordings,
  transcripts, private documents, or raw crash reports.
- Report vulnerabilities through [SECURITY.md](SECURITY.md), not a public
  issue.

## Contributing Skills

Community Skills are declarative instructions and must not contain executable
code, scripts, network actions, or hidden data access. Start from
[`examples/skills/`](examples/skills/) and follow the
[Community Skill contribution guide](docs/engineering/community-skill-contribution-guide.md).

## Git Commit Messages

### Why this style

Industry practice for open and private product repos has converged on
**[Conventional Commits](https://www.conventionalcommits.org/)**
(`type[optional scope]: description`). It is the most common shared format
across GitHub, Angular/AngularJS lineage, many JS and mobile monorepos, and
tools that build changelogs or version bumps from history.

This repository already follows that shape in practice (`feat:`, `fix:`,
`test:`, `chore:`). There is **no commitlint, husky, or other automated
commit-message gate** in the tree today—the rules below are the **project
default for human authors and reviewers**, chosen so new commits stay
consistent with existing history without inventing tooling we do not run.

**Adopted default:** Conventional Commits 1.0.0, with the project-specific
choices called out in each subsection.

### Format

```text
<type>[optional scope][optional !]: <description>

[optional body]

[optional footer(s)]
```

| Part | Required | Meaning |
| --- | --- | --- |
| `type` | Yes | Kind of change (see table below). |
| `scope` | No | Area of the product or tree (see scope guidance). |
| `!` | No | Immediately before `:` marks a breaking change (see below). |
| `description` | Yes | Short imperative summary of **what** changed. |
| `body` | No | Motivation, approach, and non-obvious trade-offs. |
| `footer` | No | Issue links, `BREAKING CHANGE:`, reviewers notes. |

One blank line separates subject, body, and footer when body or footer is present.

### Types

Use these types. Prefer the narrowest accurate type.

| Type | When to use |
| --- | --- |
| `feat` | User-visible capability or product behavior. |
| `fix` | Bug fix; behavior now matches intent. |
| `test` | Tests or acceptance harnesses only (no production behavior change). |
| `docs` | Documentation only (README, legal, engineering docs, comments-as-docs). |
| `chore` | Tooling, repo hygiene, packaging scripts, metadata with no user feature. |
| `refactor` | Internal structure change with no intentional behavior change. |
| `perf` | Performance improvement with same external behavior. |
| `ci` | CI workflow or automation only (`.github/workflows`, etc.). |
| `build` | Build system or dependency packaging that is not a product feature. |
| `style` | Formatting-only (whitespace, ordering) with no logic change. |
| `revert` | Reverts a previous commit; reference the reverted subject or hash in the body. |

Historical commits on `main` have mostly used `feat`, `fix`, `test`, and
`chore`. Prefer those four when they fit; use the wider set above when they
describe the change more accurately.

### Scope (optional)

Scope is **optional**. Use it when it clarifies the area without padding the
subject. Prefer short lowercase tokens that match product surfaces or top-level
areas, for example:

- `hotkey`, `hud`, `settings`, `onboarding`
- `paste`, `history`, `terminology`, `skills`
- `provider`, `auth`, `updater`, `packaging`
- `docs`, `ci`, `release`

Examples: `feat(hotkey):`, `fix(paste):`, `docs(release):`.

Do not invent a long taxonomy. If no clear scope fits, omit it.

### Description (subject line)

- Use the **imperative mood**: `add`, `fix`, `harden`, not `added` / `adds` / `fixing`.
- Start with a **lowercase** letter after `: ` (unless the first word is a proper noun or acronym: `VibeCompose`, `HUD`, `Keychain`, `Sparkle`).
- **Do not** end the subject with a period.
- Keep the full subject line **≤ 72 characters** (hard limit). Prefer **≤ 50** when practical.
- Describe **one** primary change. Split unrelated work into separate commits.
- Be specific: name the capability or failure mode, not vague verbs alone (`update`, `improve`, `misc`, `wip`).

### Body

Use a body when the subject is not enough for a reviewer to understand **why**
or **what to verify**.

- Wrap body lines at about **72 characters**.
- Explain motivation, risk, and user-visible impact.
- Do not restate the subject.
- Bullet lists are fine.

### Footer and issue / PR links

This repository’s issue templates use titles such as `[Bug] …` and
`[Feature] …`. There is **no separate ticket-ID scheme** (for example no
required `PROJ-123`) enforced in-repo. When a commit closes or references a
GitHub issue or PR, use standard GitHub trailers in the footer:

```text
Fixes #12
Closes #34
Refs #56
```

Multiple trailers are allowed, one per line. Link PRs the same way when useful
(`Refs #78`). Do not invent project keys that are not used in GitHub Issues.

### Breaking changes

Mark a breaking change in **either or both** of these ways:

1. `!` after type/scope: `feat(api)!: remove legacy skill extension`
2. Footer (required detail when the subject alone is unclear):

```text
BREAKING CHANGE: skill packages must use the .vibecomposeskill extension;
.vibecomposeskill is no longer loaded.
```

`BREAKING CHANGE` must be uppercase and followed by `: ` and a full-sentence
description of the incompatibility and migration hint when applicable.

### Correct examples

Single-line (matches most of this project’s history):

```text
feat: add application-aware voice modes
```

```text
fix: harden permission and installed acceptance
```

```text
test: expand installed paste acceptance matrix
```

```text
chore: add repository hygiene gate
```

With optional scope:

```text
feat(skills): add declarative skill runtime
```

Multi-line with body and issue footer:

```text
feat(paste): verify paste insertion outcomes

Installed-app acceptance now asserts paste vs clipboard fallback when the
focused target is not editable, without reading live user transcripts.

Fixes #42
```

Breaking change:

```text
feat(packaging)!: rename release asset prefix to VibeCompose

BREAKING CHANGE: release ZIP and appcast asset names use the VibeCompose
prefix; consumers of the prior asset prefix must update URLs.
```

### Incorrect examples

```text
# Missing type prefix (not Conventional Commits)
updated voice modes
```

```text
# Non-imperative, trailing period, too vague
feat: Updated stuff.
```

```text
# Wrong type for a user-facing bugfix
chore: fix paste not inserting in Notes
```

```text
# Multiple unrelated changes in one subject
feat: add hotkeys and rewrite updater and fix CI
```

```text
# WIP / noise subjects
wip
fix
misc
```

### Pre-commit checklist

Before you create a commit:

- [ ] Subject matches `<type>[scope][!]?: <description>`.
- [ ] `type` is from the table above and matches the actual change.
- [ ] Description is imperative, no trailing period, ≤ 72 characters.
- [ ] Commit contains one logical change (or a tightly related set).
- [ ] Body explains why when the subject is not enough.
- [ ] Breaking behavior uses `!` and/or a `BREAKING CHANGE:` footer.
- [ ] Related GitHub issues use `Fixes` / `Closes` / `Refs` trailers when applicable.
- [ ] Product, docs, and verification steps in this guide still apply to the change itself.

## Verification

Minimum verification for product changes:

```bash
swift build --package-path .
swift test --package-path .
VIBECOMPOSE_ALLOW_ADHOC_SIGNING=1 ./scripts/check.sh
```

For packaging or install changes:

```bash
VIBECOMPOSE_ALLOW_ADHOC_SIGNING=1 ./scripts/package_app.sh
./scripts/install_app.sh
./scripts/check_packaged_app.sh
```

Native interaction changes require installed-app verification through `/Applications/VibeCompose.app` and the Computer Use flow described in `AGENTS.md`.
