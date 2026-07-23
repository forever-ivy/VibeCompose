# VibeWhisper Brand and Product Identity

> Working identity only. Public-distribution name clearance is currently
> **blocked**; see `brand-clearance-2026-07-14.md`.

## Canonical Identity

| Surface | Value |
| --- | --- |
| Product display name | `VibeWhisper` |
| Repository slug | `vibewhisper` |
| Swift package / executable target | `VibeWhisper` |
| Test target | `VibeWhisperTests` |
| Installed app | `/Applications/VibeWhisper.app` |
| Bundle identifier | `app.vibewhisper.mac` |
| LaunchAgent label | `app.vibewhisper.mac` |
| Application Support | `~/Library/Application Support/VibeWhisper/` |
| ChatGPT Keychain service | `app.vibewhisper.mac.ChatGPTSession` |
| Recovery API Keychain service | `app.vibewhisper.mac.OpenAICompatibleAPIKey` |
| Environment prefix | `VIBEWHISPER_` |
| Release artifact prefix | `VibeWhisper-<version>-macos-<arch>` |
| Homebrew Cask | `vibewhisper` |

`product.env` is the shell-facing source of truth. `ProductIdentity.swift` is the runtime source of truth. Packaging checks must fail if generated metadata diverges.

## Naming Rules

- Use `VibeWhisper` in user-facing copy and Apple product metadata.
- Use `vibewhisper` for repository, Cask, URLs, and lowercase slugs.
- Use `VIBEWHISPER_` for environment variables.
- Do not add prior product names, aliases, release histories, screenshots, or migration labels to product-facing assets.
- The MIT license and its existing copyright notice remain unchanged.

## Public-Launch Clearance

The previous working name `OpenWhisper` was blocked by a same-category macOS
speech-to-text project (`dimatura/open-whisper`). The repository identity is
now **VibeWhisper**, but that new name has not yet completed trademark, domain,
App Store, GitHub, or social clearance.

Until a fresh clearance pass approves `VibeWhisper`:

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
| Editable logo source | `packaging/assets/VibeWhisperLogoSource.png` |
| Application icon | Color infinity-knot emblem on a light native macOS rounded-square plate |
| Menu bar icon | Monochrome transparent template derived from the same knot silhouette |
| Generated iconset | `dist/AppIcon.iconset` |
| Packaged application icon | `VibeWhisper.app/Contents/Resources/AppIcon.icns` |
| Packaged menu bar template | `VibeWhisper.app/Contents/Resources/StatusBarLogoTemplate.png` |
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
