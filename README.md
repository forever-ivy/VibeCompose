# OpenWhisper

[简体中文](README.zh-CN.md)

OpenWhisper is an MIT-licensed, native macOS push-to-talk voice input app. Press `F5` to start recording, press `F5` again to stop, and OpenWhisper returns the transcript to the current editable field or leaves it in the clipboard when automatic insertion is not safe.

## Status

OpenWhisper is currently a **macOS alpha** under productization. The working version is `0.1.0`; no production-ready commercial release is declared yet.

The current implementation already includes:

- native AppKit + SwiftUI menu bar app
- global `F5` start/stop workflow
- English and Simplified Chinese UI
- browser-based ChatGPT connection with Keychain-backed local session storage
- transcription, terminology alignment, and optional AI polish with an Auto
  mode that skips short, low-complexity dictation to avoid unnecessary latency
- conservative paste behavior with clipboard fallback
- retry results that are copied for manual paste instead of being injected automatically
- microphone and Accessibility permission diagnostics
- bounded local history, failed-audio recovery, privacy controls, and benchmark tooling
- sensitive-app exclusions and a Delete All Data action
- redacted support-diagnostics ZIP export
- signed provider-safety policy enforcement for managed transcription and AI
  Polish incidents
- OpenAI-compatible transcription as an advanced recovery route, with native
  endpoint/model controls, a Keychain-backed API key, explicit paid-API
  confirmation, and a synthetic-silence connection test
- pinned third-party dependency notices, SHA-256 license verification, and
  packaged in-app license review

## Product Boundary

The default ChatGPT account route depends on undocumented upstream behavior. It is not presented as a stable public API, an OpenAI partnership, or an enterprise SLA.

The current alpha closes the original managed-endpoint, recovery-path,
auth-refresh, and unsafe-context-paste findings. Sparkle 2.9.4 and the signed
provider capability-policy client are integrated, but commercial distribution
is still gated by Developer ID signing, notarization, production update and
capability-policy hosting/keys, installed update/incident proof, full
installed-app onboarding/interaction acceptance, and final commercial
operator/contact details. See the
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
open -n /Applications/OpenWhisper.app
```

For local debugging when no valid Apple signing identity is available:

```bash
OPENWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/check.sh
OPENWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/package_app.sh
```

Ad-hoc signing is for local validation only. It can prevent macOS from showing a stable Accessibility permission row.

Do not launch `dist/OpenWhisper.app` as the live app. Permission and interaction verification must use `/Applications/OpenWhisper.app`.

Automated product-surface screenshots run in an isolated acceptance mode with
default configuration, empty in-memory credentials, and no live history,
recovery, or terminology records.

## Runtime Data

OpenWhisper stores local application data under:

```text
~/Library/Application Support/OpenWhisper/
```

Current privacy defaults:

| Data | Default |
| --- | --- |
| Transcript history | Enabled; 30 days and at most 500 records |
| Raw ASR text | Disabled; only final text is retained unless explicitly enabled |
| Successful recordings | Deleted after processing and never added to Recovery |
| Failed recordings | Enabled for retry; 24 hours and at most 10 records |
| Local diagnostics | Enabled; 14 days and at most 1,000 records |
| Sensitive apps | Known password managers, Keychain, and Passwords are excluded from history and recovery |
| Retry files | Temporary, time-limited, and removed on the next startup if orphaned |

Diagnostics contain timing, byte counts, provider labels, bounded AI Polish
decision reasons, and error categories. They do not contain audio, transcript
text, clipboard contents, or tokens. Local data files are created with
owner-only permissions where supported.

**Settings → Advanced → Export Diagnostics** creates a local, reviewable ZIP containing redacted runtime, permission, latency, and crash-summary data. It excludes audio, transcripts, clipboard text, account email, credentials, terminology, custom endpoints, raw crash reports, history, Recovery metadata, and `config.json`.

The ChatGPT session is stored in Keychain under
`app.openwhisper.mac.ChatGPTSession`. The optional OpenAI-Compatible Recovery
API key is stored separately under
`app.openwhisper.mac.OpenAICompatibleAPIKey`; it is never read from
`OPENAI_API_KEY` or written to `config.json`. **Settings → Advanced** manages
the endpoint, model, Keychain credential, real connection test, paid-route
confirmation, and switch back to the ChatGPT account route. Recovery changes
dictation ASR only; AI Polish remains ChatGPT-authenticated.

**Settings → Privacy → Delete All Data** removes settings, terminology,
transcript history, failed recordings, diagnostics, retry files, the saved
ChatGPT session, and the Recovery API key, then returns OpenWhisper to its
signed-out defaults.

## Repository Layout

```text
Sources/OpenWhisper/          macOS application source
Tests/OpenWhisperTests/       unit and integration tests
scripts/                      build, package, install, benchmark, and acceptance tools
packaging/homebrew/           Homebrew Cask metadata
docs/product/                 PRD, commercialization, brand, and productization plans
docs/audits/                  security and logic audits
docs/research/                UI and competitive research
docs/engineering/             architecture, release, and acceptance documentation
docs/design/                  visual specifications
```

## Key Documentation

- [Documentation index](docs/README.md)
- [macOS productization plan](docs/product/macos-productization-plan-2026-07-13.md)
- [Product and commercialization analysis](docs/product/product-and-commercialization-plan-2026-07-13.md)
- [Security audit](docs/audits/security-audit-2026-07-13.md)
- [Current security baseline](docs/audits/security-baseline-2026-07-13.md)
- [UI comparison research](docs/research/ui-open-source-comparison-2026-07-12.md)
- [Architecture](docs/engineering/architecture.md)
- [Release process](docs/engineering/release.md)
- [Updater decision](docs/engineering/updater.md)
- [Privacy Policy](docs/legal/privacy-policy.md)
- [Terms of Use](docs/legal/terms-of-use.md)
- [Refund Policy](docs/legal/refund-policy.md)
- [Support Policy](docs/support/support-policy.md)
- [Security reporting](SECURITY.md)

## License

MIT. See [LICENSE](LICENSE). The existing copyright and permission notice must remain in distributed copies or substantial portions of the software.

PermissionFlow, Sparkle, and Sparkle's bundled third-party components retain
their own licenses. The exact pinned dependency metadata and full notices are
stored under
[`Sources/OpenWhisper/Resources/Legal`](Sources/OpenWhisper/Resources/Legal)
and are available in **Settings → Advanced → View Third-Party Licenses**.
Build, package, packaged-app, and commercial-release checks fail if
`Package.resolved`, license hashes, notices, or App resources diverge.
