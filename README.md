# VibeWhisper

[简体中文](README.zh-CN.md)

VibeWhisper is an MIT-licensed, native macOS push-to-talk voice input app. Press the configured global shortcut (default `F5`) to start recording, press the same shortcut again to stop, and VibeWhisper returns the transcript to the current editable field or leaves it in the clipboard when automatic insertion is not safe.

## Status

VibeWhisper is currently a **macOS alpha**. The working version is `0.1.0`; no production-ready signed release is declared yet.

The current implementation already includes:

- native AppKit + SwiftUI menu bar app
- one configurable global start/stop shortcut, defaulting to `F5`, with
  conflict-safe registration and rollback
- Refined HUD, Blue Signal Frame, and Hidden visual-feedback modes with
  Reduce Motion, Increase Contrast, VoiceOver announcements, menu Retry, and
  optional completion notifications
- English and Simplified Chinese UI
- browser-based ChatGPT connection with Keychain-backed local session storage
- transcription, terminology alignment, and optional AI polish with an Auto
  mode that skips short, low-complexity dictation to avoid unnecessary latency
- a versioned declarative Skill Runtime with 13 reviewed built-in tasks,
  including Direct, Reply, Email, developer, meeting, product, support, and
  selected-text workflows; app rules use only the application name
  and exact bundle identifier, Skill resolution is frozen when recording
  starts, and invalid model output falls back before delivery
- a global Skill Switcher, dedicated Installed/Discover/Created Skill Library,
  editable Preview, redacted Skill Run receipts, safe Undo, and Creator/Test
  Bench flow for standard Agent Skills
- opt-in selected-text context for Context Rewrite and Context Reply, with
  per-Skill Ask/Always/Never permissions, sensitive-app blocking, a local Diff
  Preview, and exact target/range/text verification before replacement
- five built-in Writing Styles plus local custom Writing Style creation, editing,
  per-Skill assignment, deletion, and export; source samples are analyzed in
  memory and cleared instead of being stored by default
- layered terminology with personal corrections, Skill-local terms, and
  Backend Engineering, Medical, and Kubernetes Domain Packs; conflicts are
  visible and the high-risk Medical pack forces Preview
- local declarative `.vibewhisperskill` import with package review, hard file
  limits, path/symlink/executable rejection, content SHA-256, multiple
  versions, rollback, disable/uninstall, Skill Inspector, and Golden contract
  tests; arbitrary code, custom network, and external actions remain blocked
- conservative paste behavior with clipboard fallback
- retry results that are copied for manual paste instead of being injected automatically
- microphone and Accessibility permission diagnostics
- bounded local history, failed-audio recovery, privacy controls, and benchmark tooling
- sensitive-app exclusions and a Delete All Data action
- redacted support-diagnostics ZIP export
- opt-in, local-only product metrics for onboarding and dictation-result
  analysis, using enums and duration/latency buckets without persistent user
  identifiers or automatic upload
- signed provider-safety policy enforcement for managed transcription and AI
  Polish incidents
- OpenAI-compatible transcription as an advanced recovery route, with native
  endpoint/model controls, a Keychain-backed API key, a third-party billing
  disclosure, and a synthetic-silence connection test
- pinned third-party dependency notices, SHA-256 license verification, and
  packaged in-app license review

## Product Boundary

The default ChatGPT account route depends on undocumented upstream behavior. It is not presented as a stable public API, an OpenAI partnership, or an enterprise SLA.

The current alpha closes the original managed-endpoint, recovery-path,
auth-refresh, and unsafe-context-paste findings. Sparkle 2.9.4 and the signed
provider capability-policy client are integrated, but signed distribution
is still gated by Developer ID signing, notarization, production update and
capability-policy hosting/keys, installed update/incident proof, full
installed-app onboarding/interaction acceptance, and final signed-release
support/contact details. See the
[current security baseline](docs/audits/security-baseline-2026-07-13.md).

## Requirements

- macOS 13 or later
- a usable ChatGPT account for the default route
- Microphone permission for recording
- Accessibility permission for automatic paste; without it, transcripts remain available in the clipboard

## Build, Install, and Run

```bash
swift build --package-path .
swift test --package-path .
./scripts/check.sh
./scripts/package_app.sh
./scripts/install_app.sh
open -n /Applications/VibeWhisper.app
```

For local debugging when no valid Apple signing identity is available:

```bash
VIBEWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/check.sh
VIBEWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/package_app.sh
```

Ad-hoc signing is for local validation only. It can prevent macOS from showing a stable Accessibility permission row.

Do not launch `dist/VibeWhisper.app` as the live app. Permission and interaction verification must use `/Applications/VibeWhisper.app`.

Automated product-surface screenshots run in an isolated acceptance mode with
default configuration, empty in-memory credentials, and no live history,
recovery, or terminology records.

Installed accessibility structure precheck:

```bash
VIBEWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/accessibility_acceptance.sh --install
```

This checks all nine Settings panes, every one of the four Onboarding steps,
History, Terminology, and Quick Add for a non-empty SwiftUI accessibility tree
and named actionable controls. It complements—but does not replace—keyboard
and VoiceOver interaction acceptance.

For official Computer Use interaction acceptance without loading the user's
live configuration, credentials, history, Recovery data, or terminology:

```bash
VIBEWHISPER_ALLOW_ADHOC_SIGNING=1 \
  ./scripts/interaction_acceptance.sh --install settings account
./scripts/interaction_acceptance.sh --restore
```

The first command leaves the requested installed-app surface open in a private,
non-persistent presentation mode. The restore command closes the transient
acceptance process and relaunches the normal installed menu bar app.

## Runtime Data

VibeWhisper stores local application data under:

```text
~/Library/Application Support/VibeWhisper/
```

Current privacy defaults:

| Data | Default |
| --- | --- |
| Transcript history | Enabled; 30 days and at most 500 records |
| Raw ASR text | Disabled; only final text is retained unless explicitly enabled |
| Successful recordings | Deleted after processing and never added to Recovery |
| Failed recordings | Enabled for retry; 24 hours and at most 10 records |
| Local diagnostics | Enabled; 14 days and at most 1,000 records |
| Local product metrics | Disabled; when enabled, 30 days and at most 5,000 enum/bucket events |
| Sensitive apps | Known password managers, Keychain, and Passwords are excluded from history and recovery |
| Retry files | Temporary, time-limited, and removed on the next startup if orphaned |

Diagnostics contain timing, byte counts, provider labels, bounded AI Polish
decision reasons, and error categories. They do not contain audio, transcript
text, clipboard contents, or tokens. Local data files are created with
owner-only permissions where supported.

Optional product metrics are disabled by default and remain on this Mac. They
contain only product version/build, completed Onboarding step, provider
category, duration and latency buckets, result category, and failure category.
They do not contain app names, paths, account details, content, or persistent
identifiers and are never uploaded automatically. When metrics are enabled,
**Settings → Context & Privacy → Export Product Metrics** creates an aggregate JSON
report without individual event timestamps for you to review or share
manually.

**Settings → Advanced → Export Diagnostics** creates a local, reviewable ZIP containing redacted runtime, permission, latency, optional product-metric, and crash-summary data. It excludes audio, transcripts, clipboard text, account email, credentials, terminology, custom endpoints, raw crash reports, history, Recovery metadata, and `config.json`.

The export also excludes Writing Style summaries/examples/source samples,
Community Skill prompts/files, and installed package names. It may contain
only bounded counts, risk indicators, semantic versions, and validator issue
codes for these features.

The ChatGPT session is stored in Keychain under
`app.vibewhisper.mac.ChatGPTSession`. The optional OpenAI-Compatible Recovery
API key is stored separately under
`app.vibewhisper.mac.OpenAICompatibleAPIKey`; it is never read from
`OPENAI_API_KEY` or written to `config.json`. **Settings → Advanced** manages
the endpoint, model, Keychain credential, real connection test, third-party
billing disclosure, and switch back to the ChatGPT account route. Recovery changes
dictation ASR only; AI Polish remains ChatGPT-authenticated.

**Settings → Context & Privacy → Delete All Data** removes settings, terminology, custom
Writing Styles, installed Community Skills, transcript history, failed
recordings, diagnostics, product metrics, retry files, the saved ChatGPT
session, and the Recovery API key, then returns VibeWhisper to its signed-out
defaults.

## Repository Layout

```text
Sources/VibeWhisper/          macOS application source
Tests/VibeWhisperTests/       unit and integration tests
scripts/                      build, package, install, benchmark, and acceptance tools
examples/skills/              reviewed declarative Community Skill template
packaging/homebrew/           Homebrew Cask metadata
docs/product/                 PRD, Community Skills, brand, and product plans
docs/audits/                  security and logic audits
docs/research/                UI and competitive research
docs/engineering/             architecture, release, and acceptance documentation
docs/design/                  visual specifications
```

## Key Documentation

- [Documentation index](docs/README.md)
- [Community Skills core plan](docs/product/community-skills-core-next-step-plan-2026-07-15.md)
- [Security audit](docs/audits/security-audit-2026-07-13.md)
- [Current security baseline](docs/audits/security-baseline-2026-07-13.md)
- [UI comparison research](docs/research/ui-open-source-comparison-2026-07-12.md)
- [Architecture](docs/engineering/architecture.md)
- [Skill Runtime](docs/engineering/skill-runtime.md)
- [Context and Preview](docs/engineering/context-and-preview.md)
- [Community Skill SDK](docs/engineering/community-skill-sdk.md)
- [Registry and Actions boundary](docs/engineering/registry-and-actions-boundary.md)
- [Release process](docs/engineering/release.md)
- [Updater decision](docs/engineering/updater.md)
- [Privacy Policy](docs/legal/privacy-policy.md)
- [Terms of Use](docs/legal/terms-of-use.md)
- [Support Policy](docs/support/support-policy.md)
- [Security reporting](SECURITY.md)

## License

MIT. See [LICENSE](LICENSE). The existing copyright and permission notice must remain in distributed copies or substantial portions of the software.

PermissionFlow, Sparkle, and Sparkle's bundled third-party components retain
their own licenses. The exact pinned dependency metadata and full notices are
stored under
[`Sources/VibeWhisper/Resources/Legal`](Sources/VibeWhisper/Resources/Legal)
and are available in **Settings → Advanced → View Third-Party Licenses**.
Build, package, packaged-app, and signed-release checks fail if
`Package.resolved`, license hashes, notices, or App resources diverge.
