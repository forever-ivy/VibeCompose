# VibeCompose Brand and Product Identity

> Working identity only. Public-distribution name clearance is currently
> **blocked**; see `brand-clearance-2026-07-14.md`.

## Canonical Identity

| Surface | Value |
| --- | --- |
| Product display name | `VibeCompose` |
| Repository slug | `vibecompose` |
| Swift package / executable target | `VibeCompose` |
| Test target | `VibeComposeTests` |
| Installed app | `/Applications/VibeCompose.app` |
| Bundle identifier | `app.vibecompose.mac` |
| LaunchAgent label | `app.vibecompose.mac` |
| Application Support | `~/Library/Application Support/VibeCompose/` |
| ChatGPT Keychain service | `app.vibecompose.mac.ChatGPTSession` |
| Recovery API Keychain service | `app.vibecompose.mac.OpenAICompatibleAPIKey` |
| Environment prefix | `VIBECOMPOSE_` |
| Release artifact prefix | `VibeCompose-<version>-macos-<arch>` |
| Homebrew Cask | `vibecompose` |

`product.env` is the shell-facing source of truth. `ProductIdentity.swift` is the runtime source of truth. Packaging checks must fail if generated metadata diverges.

## Naming Rules

- Use `VibeCompose` in user-facing copy and Apple product metadata.
- Use `vibecompose` for repository, Cask, URLs, and lowercase slugs.
- Use `VIBECOMPOSE_` for environment variables.
- Do not add prior product names, aliases, release histories, screenshots, or migration labels to product-facing assets.
- The MIT license and its existing copyright notice remain unchanged.

## Public-Launch Clearance

A previous working identity was blocked by a same-category macOS
speech-to-text project. The repository identity is now **VibeCompose**, but
this name has not yet completed trademark, domain, App Store, GitHub, or
social clearance.

Until a fresh clearance pass approves `VibeCompose`:

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
| Editable logo source | `packaging/assets/VibeComposeLogoSource.png` |
| Application icon | Color infinity-knot emblem on a light native macOS rounded-square plate |
| Menu bar icon | Monochrome transparent template derived from the same knot silhouette |
| Generated iconset | `dist/AppIcon.iconset` |
| Packaged application icon | `VibeCompose.app/Contents/Resources/AppIcon.icns` |
| Packaged menu bar template | `VibeCompose.app/Contents/Resources/StatusBarLogoTemplate.png` |
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
