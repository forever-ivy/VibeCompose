# OpenWhisper macOS Release Process

## Release Status

OpenWhisper `0.1.0` is an alpha baseline. Do not publish it as production-ready until every required gate below is satisfied.

## Sources of Truth

- Product identity: `product.env`
- Runtime identity: `Sources/OpenWhisper/ProductIdentity.swift`
- Version/build: `version.env`
- Installed app: `/Applications/OpenWhisper.app`
- Packaged output: `dist/OpenWhisper.app`

## Local Verification

```bash
swift build --package-path .
swift test --package-path .
OPENWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/check.sh
OPENWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/package_app.sh
./scripts/install_app.sh
./scripts/check_packaged_app.sh
./scripts/generate_release_metadata.sh
```

Then verify the installed app:

1. Launch `/Applications/OpenWhisper.app` through LaunchServices.
2. Confirm English and Simplified Chinese UI.
3. Confirm Microphone and Accessibility states refresh correctly.
4. Focus a real editable target.
5. Start and stop with `F5`.
6. Cancel with `ESC` and the inline close control.
7. Verify safe paste and clipboard fallback.
8. Verify retry/re-entry after a recoverable failure.
9. Leave the normal installed app running after acceptance.

## Alpha Artifact Contract

For version `0.1.0` on Apple silicon, packaging emits:

```text
dist/OpenWhisper.app
dist/OpenWhisper-0.1.0-macos-arm64.zip
dist/OpenWhisper-0.1.0-macos-arm64.dmg
```

## Required Commercial Release Gates

### Security and Privacy

- Close all P0 findings in `docs/audits/security-audit-2026-07-13.md`.
- Managed tokens can reach only approved HTTPS origins and paths.
- Recovery paths cannot escape the recovery directory.
- Sign-out invalidates all late refresh operations.
- Successful audio is deleted by default.
- History and logs have retention limits and a Delete All Data action.
- No unverifiable editable target receives an automatic paste command.

### Distribution Integrity

- Stable Developer ID Application certificate and Team ID.
- Hardened Runtime entitlements reviewed.
- Archive signed, notarized, and stapled.
- Gatekeeper failure is fail-closed.
- Release ZIP/DMG hashes are generated and published.
- Homebrew Cask uses an exact SHA-256.
- Update manifest is signed and rollback-safe.

Current fail-closed foundations:

- `scripts/generate_release_metadata.sh` records exact ZIP/DMG SHA-256 values, byte counts, HTTPS URLs, version, build, architecture, bundle ID, and minimum macOS.
- `scripts/update_homebrew_cask.sh` writes the exact ZIP hash into the Cask; the tracked unreleased Cask uses an impossible all-zero checksum rather than `:no_check`.
- `scripts/install_app.sh` stages and validates a candidate, checks bundle ID/version/build/architecture/signature, and restores the previous app after a failed replacement.
- Sparkle 2.9.4 is pinned, embedded, linked through the app Frameworks rpath, and exposed through the menu and Advanced Settings.
- Ad-hoc local builds use a library-validation exception so the no-Team-ID app can load the no-Team-ID framework; Developer ID releases must retain library validation and the release gate rejects this entitlement.
- `scripts/generate_sparkle_appcast.sh` creates channel-specific signed appcasts without storing a private signing key in the repository.
- `scripts/verify_release_gate.sh` requires Developer ID, the expected Team ID, stapling, Gatekeeper, manifest/Cask consistency, updater feed/key configuration, the pinned embedded framework, and a matching signed appcast.
- Private-alpha packages omit production feed/key values; the commercial release gate intentionally fails until permanent update hosting and signing-key material are supplied.

### Product and Support

- Four-step onboarding completes from clean TCC state.
- Crash and diagnostics collection is explicit and privacy-preserving, with a user-initiated redacted ZIP export.
- Bilingual privacy policy, terms, refund policy, and support scope exist for private alpha.
- Public payment remains blocked until the commercial operator and permanent legal/privacy/support contacts are finalized.
- The default upstream route has a documented recovery path and incident kill switch.

## Versioning

- `0.1.x`: private alpha and productization
- `0.2.x`: closed beta after P0 closure
- `0.5.x`: release candidate after signing, notarization, updater, and privacy controls
- `1.0.0`: first supported commercial macOS release

Do not reuse historical version claims that were not issued under the OpenWhisper identity.

## Commercial Release Command

After obtaining a valid Developer ID certificate, Team ID, notary profile, Sparkle feed, and EdDSA key pair:

```bash
OPENWHISPER_REQUIRE_DEVELOPER_ID=1 \
OPENWHISPER_TEAM_ID=YOUR_TEAM_ID \
OPENWHISPER_NOTARIZE=1 \
OPENWHISPER_NOTARY_PROFILE=YOUR_NOTARY_PROFILE \
OPENWHISPER_SPARKLE_FEED_URL=https://updates.example/stable/appcast.xml \
OPENWHISPER_SPARKLE_PUBLIC_ED_KEY=BASE64_PUBLIC_KEY \
./scripts/package_app.sh

./scripts/generate_release_metadata.sh
OPENWHISPER_SPARKLE_PRIVATE_KEY_FILE=/secure/path/openwhisper-ed25519.key \
./scripts/generate_sparkle_appcast.sh
./scripts/update_homebrew_cask.sh
OPENWHISPER_TEAM_ID=YOUR_TEAM_ID ./scripts/verify_release_gate.sh
```

The final command must fail unless the packaged app, signed appcast, release manifest, Cask checksum, Developer ID identity, notarization, stapling, and Gatekeeper assessment all agree.
