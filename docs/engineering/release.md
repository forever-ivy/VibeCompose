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

### Product and Support

- Four-step onboarding completes from clean TCC state.
- Crash and diagnostics collection is explicit and privacy-preserving.
- Privacy policy, terms, refund policy, support scope, and independent-project statement are published.
- The default upstream route has a documented recovery path and incident kill switch.

## Versioning

- `0.1.x`: private alpha and productization
- `0.2.x`: closed beta after P0 closure
- `0.5.x`: release candidate after signing, notarization, updater, and privacy controls
- `1.0.0`: first supported commercial macOS release

Do not reuse historical version claims that were not issued under the OpenWhisper identity.
