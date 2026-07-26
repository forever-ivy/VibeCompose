# VibeCompose

[简体中文](README.zh-CN.md)

**Voice-first writing for macOS.** One hotkey. Speak your mind. Get text that's ready to send — shaped by declarative Skills that never run code on your machine.

VibeCompose is MIT-licensed, native, and local-first. Press `F5` to record, press again to stop. Your words land in the active field — or stay safe in the clipboard when auto-paste can't be verified.

## Why VibeCompose

Most voice tools stop at transcription. VibeCompose goes further: a **Skill Runtime** transforms raw speech into emails, commit messages, bug reports, code prompts, or any structured format — using plain-text instructions, not executable scripts.

- **One key, many outputs** — Same `F5` workflow regardless of whether you need a raw transcript, a polished reply, or a structured task
- **Declarative, not executable** — Skills are prompt files. They can't access your filesystem, run shell commands, or make network requests
- **Context-aware** — Selected text, clipboard, writing styles, and terminology feed into Skill resolution without manual setup
- **Privacy-first** — Zero telemetry, local history, no account system, no remote Skill store

## Current Status

**macOS Alpha · v0.1.0** — Actively developed. Not production-signed yet.

What's already working:

- Native AppKit + SwiftUI menu bar app with English and Simplified Chinese UI
- Configurable global hotkey (default `F5`) with conflict detection and atomic rollback
- Three visual feedback modes: Status Bar, Edge Glow, and Hidden — with Reduce Motion, Increase Contrast, and VoiceOver support
- Browser-based ChatGPT connection with Keychain-backed session storage
- Transcription → terminology alignment → optional AI Polish pipeline with an Auto mode that skips short dictation to reduce latency
- **21 reviewed built-in Skills** covering dictation, reply, email, developer tasks, meetings, product, support, translation, and context workflows
- Global Skill Switcher, Skill Library (Installed / Discover / Created), editable Preview, redacted Skill Run receipts, safe Undo, and Creator/Test Bench
- Selected-text context with per-Skill permissions, sensitive-app blocking, local Diff Preview, and target verification before replacement
- Five built-in Writing Styles plus custom style creation, per-Skill assignment, and export
- Layered terminology: personal corrections → Skill-local terms → Domain Packs (Backend Engineering, Medical, Kubernetes)
- `.vibecomposeskill` package import with file validation, SHA-256 verification, multi-version support, rollback, and Skill Inspector
- Conservative paste: clipboard fallback, retry-to-clipboard, verified insertion
- Bounded local history, failed-audio recovery, privacy controls, and performance benchmarking
- Sensitive-app exclusions and Delete All Data
- Redacted support-diagnostics ZIP export
- OpenAI-Compatible transcription as an advanced recovery route with Keychain API key and connection testing
- Signed provider-safety policy enforcement for managed transcription and AI Polish incidents
- Sparkle updates, pinned dependency notices, and SHA-256 license verification

## Product Boundary

The default ChatGPT account route depends on undocumented upstream behavior. It is **not** a stable public API, an OpenAI partnership, or an enterprise SLA.

The current Alpha closes all original managed-endpoint, recovery-path, auth-refresh, and unsafe-context-paste findings. Sparkle 2.9.4 and the signed provider capability-policy client are integrated. Signed public distribution is gated by Developer ID signing, notarization, production hosting, and final acceptance testing. See the [security baseline](docs/audits/security-baseline-2026-07-13.md).

## Requirements

- macOS 13+
- A usable ChatGPT account (default route)
- Microphone permission (recording)
- Accessibility permission (auto-paste; without it, transcripts stay in the clipboard)

## Quick Start

```bash
swift build --package-path .
swift test --package-path .
./scripts/check.sh
./scripts/package_app.sh
./scripts/install_app.sh
open -n /Applications/VibeCompose.app
```

For local debugging without a valid Apple signing identity:

```bash
VIBECOMPOSE_ALLOW_ADHOC_SIGNING=1 ./scripts/check.sh
VIBECOMPOSE_ALLOW_ADHOC_SIGNING=1 ./scripts/package_app.sh
```

Ad-hoc signing is for local validation only. It may prevent macOS from showing a stable Accessibility permission row.

> **Important:** Always use `/Applications/VibeCompose.app` for permission and interaction verification. Do not launch `dist/VibeCompose.app` as the live app.

### Accessibility Structure Precheck

```bash
VIBECOMPOSE_ALLOW_ADHOC_SIGNING=1 ./scripts/accessibility_acceptance.sh --install
```

Checks all nine Settings panes, four Onboarding steps, History, Terminology, and Quick Add for non-empty SwiftUI accessibility trees and named actionable controls.

### Interaction Acceptance

```bash
VIBECOMPOSE_ALLOW_ADHOC_SIGNING=1 \
  ./scripts/interaction_acceptance.sh --install settings account
./scripts/interaction_acceptance.sh --restore
```

## Runtime Data

Local application data lives at:

```text
~/Library/Application Support/VibeCompose/
```

### Privacy Defaults

| Data | Default |
| --- | --- |
| Transcript history | On · 30 days / 500 records max |
| Raw ASR text | Off · Only final text retained unless explicitly enabled |
| Successful recordings | Deleted after processing · Never enters Recovery |
| Failed recordings | On for retry · 24 hours / 10 records max |
| Local diagnostics | On · 14 days / 1,000 records max |
| Product metrics | Off · When enabled: 30 days / 5,000 events max |
| Sensitive apps | Password managers and Keychain excluded from history and recovery |
| Retry files | Temporary · Time-limited · Cleaned on next launch |

Diagnostics contain only timing, byte counts, provider labels, and error categories — never audio, transcript text, clipboard contents, or tokens. Local files are created with owner-only permissions.

### Keychain Storage

- ChatGPT session: `app.vibecompose.mac.ChatGPTSession`
- Recovery API key: `app.vibecompose.mac.OpenAICompatibleAPIKey` (never read from `OPENAI_API_KEY` or written to `config.json`)

### Data Management

- **Settings → Context & Privacy → Export Product Metrics** — Aggregate JSON without individual timestamps
- **Settings → Advanced → Export Diagnostics** — Redacted ZIP excluding audio, transcripts, credentials, and personal data
- **Settings → Context & Privacy → Delete All Data** — Removes everything and returns to signed-out defaults

## Website

The marketing site and Skill catalog live in [`website/`](website/). Static Next.js (App Router) export for GitHub Pages with full bilingual routes (`/zh-Hans`, `/en`).

```bash
cd website
pnpm install
pnpm dev          # local preview
pnpm build        # static export → website/out
pnpm verify       # build + catalog check + content contract
```

The Skill catalog is generated at build time from [`Sources/VibeCompose/Resources/BuiltInSkills`](Sources/VibeCompose/Resources/BuiltInSkills). No remote Skill registry, no account system.

## Repository Layout

```text
Sources/VibeCompose/          macOS application source
Tests/VibeComposeTests/       unit and integration tests
scripts/                      build, package, install, benchmark, and acceptance tools
website/                      Next.js marketing site + Skill catalog (static export)
examples/skills/              reviewed declarative Community Skill template
packaging/homebrew/           Homebrew Cask metadata
docs/product/                 PRD, Community Skills, brand, and product plans
docs/audits/                  security and logic audits
docs/research/                UI and competitive research
docs/engineering/             architecture, release, and acceptance docs
docs/design/                  visual specifications
```

## Documentation

- [Documentation index](docs/README.md)
- [Architecture](docs/engineering/architecture.md)
- [Skill Runtime](docs/engineering/skill-runtime.md)
- [Context and Preview](docs/engineering/context-and-preview.md)
- [Community Skill SDK](docs/engineering/community-skill-sdk.md)
- [Registry and Actions boundary](docs/engineering/registry-and-actions-boundary.md)
- [Release process](docs/engineering/release.md)
- [Security audit](docs/audits/security-audit-2026-07-13.md)
- [Security baseline](docs/audits/security-baseline-2026-07-13.md)
- [Privacy Policy](docs/legal/privacy-policy.md)
- [Terms of Use](docs/legal/terms-of-use.md)
- [Support Policy](docs/support/support-policy.md)
- [Security reporting](SECURITY.md)

## License

MIT. See [LICENSE](LICENSE).

PermissionFlow, Sparkle, and Sparkle's bundled components retain their own licenses. Pinned dependency metadata and full notices are in [`Sources/VibeCompose/Resources/Legal`](Sources/VibeCompose/Resources/Legal) and available via **Settings → Advanced → View Third-Party Licenses**.
