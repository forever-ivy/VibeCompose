# OpenWhisper Brand and Product Identity

> Working identity only. Commercial/public launch clearance is currently
> **blocked**; see `brand-clearance-2026-07-14.md`.

## Canonical Identity

| Surface | Value |
| --- | --- |
| Product display name | `OpenWhisper` |
| Repository slug | `openwhisper` |
| Swift package / executable target | `OpenWhisper` |
| Test target | `OpenWhisperTests` |
| Installed app | `/Applications/OpenWhisper.app` |
| Bundle identifier | `app.openwhisper.mac` |
| LaunchAgent label | `app.openwhisper.mac` |
| Application Support | `~/Library/Application Support/OpenWhisper/` |
| ChatGPT Keychain service | `app.openwhisper.mac.ChatGPTSession` |
| Recovery API Keychain service | `app.openwhisper.mac.OpenAICompatibleAPIKey` |
| Environment prefix | `OPENWHISPER_` |
| Release artifact prefix | `OpenWhisper-<version>-macos-<arch>` |
| Homebrew Cask | `openwhisper` |

`product.env` is the shell-facing source of truth. `ProductIdentity.swift` is the runtime source of truth. Packaging checks must fail if generated metadata diverges.

## Naming Rules

- Use `OpenWhisper` in user-facing copy and Apple product metadata.
- Use `openwhisper` for repository, Cask, URLs, and lowercase slugs.
- Use `OPENWHISPER_` for environment variables.
- Do not add prior product names, aliases, release histories, screenshots, or migration labels to product-facing assets.
- The MIT license and its existing copyright notice remain unchanged.

## Public-Launch Clearance

OpenWhisper remains the current repository and alpha working name, but the
clearance gate has failed: an independently maintained macOS speech-to-text
application already uses the same name and publishes releases.

Until the product owner chooses a distinct name or obtains documented legal
clearance:

- do not issue paid licenses or a Stable notarized release under this name;
- do not publish production domains, Sparkle feeds, Homebrew listings, or
  marketplace entries under this name;
- do not mark `release/brand-clearance.json` as approved;
- continue repository engineering only as a working identity.

Any future rename must repeat the single-identity migration across source,
bundle ID, data paths, Keychain, packaging, update metadata, legal copy,
support surfaces, and release evidence while preserving the MIT license
notice.
