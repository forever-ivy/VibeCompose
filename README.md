# OpenWhisper

[简体中文](README.zh-CN.md)

OpenWhisper is an open-source, native macOS push-to-talk voice input app. Press `F5` to start recording, press `F5` again to stop, and OpenWhisper returns the transcript to the current editable field or leaves it in the clipboard when automatic insertion is not safe.

## Status

OpenWhisper is currently a **macOS alpha** under productization. The working version is `0.1.0`; no production-ready commercial release is declared yet.

The current implementation already includes:

- native AppKit + SwiftUI menu bar app
- global `F5` start/stop workflow
- English and Simplified Chinese UI
- browser-based ChatGPT connection with Keychain-backed local session storage
- transcription, terminology alignment, and optional AI polish
- conservative paste behavior with clipboard fallback
- microphone and Accessibility permission diagnostics
- local history, recovery records, and benchmark tooling
- OpenAI-compatible transcription as an advanced recovery route

## Product Boundary

The default ChatGPT account route depends on undocumented upstream behavior. It is not presented as a stable public API, an OpenAI partnership, or an enterprise SLA. Commercial distribution remains gated by the security, privacy, release-integrity, and provider-continuity work in the productization plan.

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
OPENWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/package_app.sh
```

Ad-hoc signing is for local validation only. It can prevent macOS from showing a stable Accessibility permission row.

Do not launch `dist/OpenWhisper.app` as the live app. Permission and interaction verification must use `/Applications/OpenWhisper.app`.

## Runtime Data

OpenWhisper stores application data under:

```text
~/Library/Application Support/OpenWhisper/
```

The ChatGPT session is stored in Keychain under the OpenWhisper service identity. Successful commercial release must include explicit retention controls, data deletion, and audited token-to-endpoint restrictions.

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
- [UI comparison research](docs/research/ui-open-source-comparison-2026-07-12.md)
- [Architecture](docs/engineering/architecture.md)
- [Release process](docs/engineering/release.md)

## License

MIT. See [LICENSE](LICENSE). The existing copyright and permission notice must remain in distributed copies or substantial portions of the software.
