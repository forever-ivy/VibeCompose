# OpenWhisper Brand and Product Identity

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
| Keychain service | `app.openwhisper.mac.ChatGPTSession` |
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

OpenWhisper is the current working product name. Before a paid public launch, complete name, trademark, domain, App Store, GitHub, and social-handle clearance. If clearance fails, repeat the identity migration before issuing stable licenses or notarized updates.
