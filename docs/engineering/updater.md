# OpenWhisper Updater Decision

> Decision date: July 13, 2026
>
> Status: Sparkle 2.9.4 and fail-closed publication verification integrated;
> production feed, signing key, hosting, and installed update/rollback evidence
> not yet configured
>
> Signed release gate: blocked until the implementation and installed update/rollback proof are complete

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
11. Publish from the exact prepared candidate. Finalization must restore the
    source-commit-bound candidate from the earlier prepare run rather than
    rebuilding or regenerating the update archive.

## Current Repository Guards

- `scripts/generate_release_metadata.sh` creates a machine-readable manifest
  for the ZIP and DMG with exact SHA-256 values, byte counts, and public HTTPS
  URLs. A Developer ID release requires an explicit public artifact base URL;
  the private GitHub repository is not treated as the production feed.
- `scripts/update_homebrew_cask.sh` replaces both the fail-closed Cask URL and
  checksum only from that manifest.
- `scripts/package_app.sh` embeds and signs the pinned Sparkle framework and rejects partial or unsafe updater configuration.
- Local packages default to Swift's debug configuration; the signed release
  entry point pins `OPENWHISPER_BUILD_CONFIGURATION=release`, and Developer ID
  packaging rejects any other configuration.
- Ad-hoc local builds add `com.apple.security.cs.disable-library-validation` because ad-hoc code has no shared Team ID; the Developer ID release gate explicitly rejects that local-only entitlement.
- `scripts/check_packaged_app.sh` verifies the embedded framework version, runtime link/rpath, and paired HTTPS feed/public-key configuration.
- `scripts/verify_release_gate.sh` requires Developer ID, the expected Team ID,
  trusted timestamp and Hardened Runtime flag on the App and every embedded
  Sparkle executable, stapling, Gatekeeper success, manifest/Cask consistency,
  the pinned Sparkle framework, `SUFeedURL`, `SUPublicEDKey`, and a matching
  signed appcast.
- `scripts/verify_release_readiness.py` separates candidate configuration from
  public authorization. Its public phase binds the exact source/tag and ZIP
  hash to installed-app acceptance, brand clearance, the privacy-bounded
  Community Pilot aggregate, and the matching product-owner review.
- `scripts/verify_remote_release_assets.sh` downloads the published ZIP, DMG,
  appcast, and provider policy without redirects, verifies artifact hashes,
  requires the remote appcast/policy to be byte-identical to the locally gated
  files, and verifies their signatures.
- `scripts/archive_release_candidate.sh` and
  `scripts/restore_release_candidate.sh` preserve executable modes and the
  exact signed App across separate `prepare` and `finalize` Actions runs. The
  archive is checked against a separate SHA-256 and the exact source commit,
  version, build, architecture, manifest, and artifact hashes.
- App and DMG notarization results are retained as separate JSON receipts. The
  signed release gate and candidate restorer require `Accepted` plus two valid,
  distinct Apple submission IDs in addition to stapler/Gatekeeper success.
- The signed-release workflow exposes the Sparkle private key only during
  `prepare`; `finalize` verifies published assets without receiving that
  private key.
- Private-alpha builds intentionally omit production feed/key values. The signed release gate therefore remains fail-closed until permanent update hosting and signing-key material are supplied.

## Key Management

- Generate the EdDSA key on a secured maintainer machine.
- Store the private key in a dedicated secrets manager or release keychain.
- Restrict CI access to protected release environments.
- Pin only the public key in the app.
- Keep Sparkle and provider-capability signing keys distinct.
- Never place private keys under the repository tree; the candidate-readiness
  gate and `.gitignore` reserve common release secret paths.
- Document key rotation before the first public build. Rotation must be authorized by an already trusted release or a separately authenticated recovery process.

## Rollback and Minimum Versions

The appcast must support:

- a minimum safe version for mandatory security updates;
- channel-specific version ordering;
- prevention of silent downgrade to an older build;
- retention of the previous working app until the new app passes signature and launch verification;
- a documented manual recovery download when automatic update fails.

The existing local installer already stages a candidate, validates bundle identity/version/build/architecture/signature, preserves the previous app, and restores it when replacement verification fails. Sparkle acceptance must prove equivalent or stronger behavior.
