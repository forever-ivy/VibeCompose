# OpenWhisper Updater Decision

> Decision date: July 13, 2026
>
> Status: Sparkle 2.9.4 integrated in the private alpha; production feed and signing key not yet configured
>
> Commercial release gate: blocked until the implementation and installed update/rollback proof are complete

## Decision

OpenWhisper will use Sparkle 2 for direct-distribution updates rather than implementing a custom downloader, signature format, privileged installer, or update UI.

Reasons:

- Sparkle provides a mature macOS update lifecycle and appcast format;
- update payloads can be verified with an EdDSA public key pinned in the app;
- the framework supports background checks, user-visible release notes, staged installation, relaunch, and rollback-oriented failure handling;
- using an established updater reduces the amount of security-critical custom code maintained by OpenWhisper.

The selected version must be pinned exactly in `Package.resolved` or the final Xcode project. Release signing keys must never be stored in the repository.

## Required Integration

1. **Implemented:** pin Sparkle 2.9.4 in `Package.swift` and `Package.resolved`.
2. **Implemented:** embed Sparkle.framework and its helper services inside `OpenWhisper.app`, add the app Frameworks rpath, and sign nested code before signing the app.
3. **Implemented as fail-closed configuration:** packaging accepts `OPENWHISPER_SPARKLE_FEED_URL` and `OPENWHISPER_SPARKLE_PUBLIC_ED_KEY` together and writes `SUFeedURL` and `SUPublicEDKey` into the signed `Info.plist`; Developer ID packaging rejects missing configuration.
4. Store the EdDSA private key outside the repository and CI logs.
5. **Implemented as release tooling:** `scripts/generate_sparkle_appcast.sh` generates a signed channel appcast from the exact release ZIP using a protected private-key file or a named Keychain account. Real production signing evidence is still required.
6. **Implemented:** expose Check for Updates in the menu and Settings, with automatic-check preference control and an explicit unavailable state in unconfigured alpha builds.
7. Keep alpha, beta, and stable appcasts separate.
8. Reject a feed or archive whose signature, bundle ID, Team ID, version, architecture, or minimum macOS requirement is invalid.
9. Test update from the previous supported build, interrupted download, invalid signature, malformed appcast, downgrade attempt, failed relaunch, and rollback.
10. Archive the notarized artifact, appcast, signatures, symbols, release metadata, and checksums.

## Current Repository Guards

- `scripts/generate_release_metadata.sh` creates a machine-readable manifest for the ZIP and DMG with exact SHA-256 values and byte counts.
- `scripts/update_homebrew_cask.sh` replaces the fail-closed Cask checksum only from that manifest.
- `scripts/package_app.sh` embeds and signs the pinned Sparkle framework and rejects partial or unsafe updater configuration.
- Ad-hoc local builds add `com.apple.security.cs.disable-library-validation` because ad-hoc code has no shared Team ID; the Developer ID release gate explicitly rejects that local-only entitlement.
- `scripts/check_packaged_app.sh` verifies the embedded framework version, runtime link/rpath, and paired HTTPS feed/public-key configuration.
- `scripts/verify_release_gate.sh` requires Developer ID, the expected Team ID, stapling, Gatekeeper success, manifest/Cask consistency, the pinned Sparkle framework, `SUFeedURL`, `SUPublicEDKey`, and a matching signed appcast.
- Private-alpha builds intentionally omit production feed/key values. The commercial release gate therefore remains fail-closed until permanent update hosting and signing-key material are supplied.

## Key Management

- Generate the EdDSA key on a secured maintainer machine.
- Store the private key in a dedicated secrets manager or release keychain.
- Restrict CI access to protected release environments.
- Pin only the public key in the app.
- Document key rotation before the first public build. Rotation must be authorized by an already trusted release or a separately authenticated recovery process.

## Rollback and Minimum Versions

The appcast must support:

- a minimum safe version for mandatory security updates;
- channel-specific version ordering;
- prevention of silent downgrade to an older build;
- retention of the previous working app until the new app passes signature and launch verification;
- a documented manual recovery download when automatic update fails.

The existing local installer already stages a candidate, validates bundle identity/version/build/architecture/signature, preserves the previous app, and restores it when replacement verification fails. Sparkle acceptance must prove equivalent or stronger behavior.
