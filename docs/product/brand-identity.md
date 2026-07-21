# OpenWhisper Brand and Product Identity

> Working identity only. Public-distribution name clearance is currently
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

- do not issue a Stable notarized release under this name;
- do not publish production domains, Sparkle feeds, Homebrew listings, or
  marketplace entries under this name;
- do not mark `release/brand-clearance.json` as approved;
- continue repository engineering only as a working identity.

Any future rename must repeat the single-identity migration across source,
bundle ID, data paths, Keychain, packaging, update metadata, legal copy,
support surfaces, and release evidence while preserving the MIT license
notice.

## Visual Identity

| Surface | Asset / rule |
| --- | --- |
| Editable logo source | `packaging/assets/OpenWhisperLogoSource.png` |
| Application icon | Color infinity-knot emblem on a light native macOS rounded-square plate |
| Menu bar icon | Monochrome transparent template derived from the same knot silhouette |
| Generated iconset | `dist/AppIcon.iconset` |
| Packaged application icon | `OpenWhisper.app/Contents/Resources/AppIcon.icns` |
| Packaged menu bar template | `OpenWhisper.app/Contents/Resources/StatusBarLogoTemplate.png` |
| Canonical interaction blue | `#0074FF` / `RGB 0, 116, 255` |
| Light sidebar selection | `#EFEFEF` background with canonical-blue icon and label |

`scripts/render_app_icon.swift` is the canonical asset generator. Generated
iconset, ICNS, and status-bar PNG files must not be edited independently.
The menu bar must use the template variant so macOS can supply the correct
light/dark tint; it must not display the white App Icon plate in the menu bar.
Native control tint, selected-sidebar labels and icons, active links, and the
website accent use the canonical interaction blue. The sidebar selection fill
uses the approved light reference color and switches to a translucent neutral
fill in Dark Appearance.
