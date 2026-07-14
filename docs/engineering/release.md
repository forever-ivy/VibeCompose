# OpenWhisper macOS Release Process

## Release Status

OpenWhisper `0.1.0` is a private alpha baseline. Repository/source readiness
is implemented and passes, but a production or paid release remains
fail-closed until every commercial gate below has real evidence.

Current external blockers:

- no Developer ID Application certificate or fixed production Team ID;
- no notarization/stapling evidence from a release identity;
- no public production artifact host, Sparkle feed, or capability-policy host;
- no production Sparkle, capability-policy, or license key set;
- no approved commercial operator, checkout, permanent legal/privacy/support
  contacts, or 30–50 person beta report;
- no complete clean-TCC, keyboard, VoiceOver, compatibility, update, rollback,
  and uninstall evidence from `/Applications/OpenWhisper.app`;
- the current working name is blocked by the same-category conflict recorded
  in `docs/product/brand-clearance-2026-07-14.md`.

## Sources of Truth

- Product identity: `product.env`
- Runtime identity: `Sources/OpenWhisper/ProductIdentity.swift`
- Version/build: `version.env`
- Release evidence schemas and status: `release/`
- Dependency license manifest:
  `Sources/OpenWhisper/Resources/Legal/third-party-licenses.json`
- Installed app: `/Applications/OpenWhisper.app`
- Packaged output: `dist/OpenWhisper.app`

`dist/OpenWhisper.app` is build output only. Permission, interaction, and
shipping proof must use the installed application.

## Local Alpha Verification

```bash
swift build --package-path .
swift test --package-path .
OPENWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/check.sh
python3 ./scripts/verify_productization_readiness.py --stage source
OPENWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/package_app.sh
./scripts/install_app.sh
./scripts/check_packaged_app.sh
```

Then verify the installed app:

1. Launch `/Applications/OpenWhisper.app` through LaunchServices.
2. Confirm English and Simplified Chinese UI.
3. Confirm Microphone and Accessibility states refresh correctly.
4. Focus a real editable target.
5. Start and stop with the configured shortcut, including default `F5`.
6. Cancel with `ESC` and the inline close control.
7. Verify confirmed insertion, paste-sent, and clipboard-only fallback.
8. Verify retry/re-entry after a recoverable failure.
9. Leave the normal installed menu bar app running.

## Alpha Artifact Contract

For version `0.1.0` on Apple silicon:

```text
dist/OpenWhisper.app
dist/OpenWhisper-0.1.0-macos-arm64.zip
dist/OpenWhisper-0.1.0-macos-arm64.dmg
dist/release-manifest.json
dist/SHA256SUMS
```

Ad-hoc alpha artifacts are not public release artifacts and cannot satisfy the
commercial release gate.

## Required Commercial Gates

### Security and privacy

- All P0/P1 release blockers are closed.
- Managed credentials can reach only approved HTTPS origins and paths.
- Recovery paths cannot escape the recovery directory.
- Sign-out invalidates late refresh operations.
- Successful audio is deleted by default.
- History, Recovery, diagnostics, and metrics have bounded retention.
- Delete All Data removes every documented local data class.
- No unverifiable target receives an automatic paste command.

### Distribution integrity

- Stable Developer ID Application certificate and expected Team ID.
- Hardened Runtime without the local-only library-validation exception.
- App and DMG notarized, stapled, and accepted by Gatekeeper.
- ZIP and DMG hashes and byte counts match the release manifest.
- Homebrew Cask URL and SHA-256 match the manifest.
- Sparkle feed and archive signatures match the key pinned in the App.
- Provider Capability Policy matches its independent key and build window.
- License verification uses a third distinct public key.
- Every resolved dependency has an exact, integrity-checked license notice.
- Update, interrupted download, invalid signature, downgrade, failed relaunch,
  rollback, and uninstall are proved on installed builds.

### Product, operator, and brand

- Four-step onboarding completes from clean TCC state.
- Installed keyboard, focus, VoiceOver, Reduce Motion, Increase Contrast,
  multi-display, full-screen, Spaces, and Stage Manager matrices pass.
- `release/commercial-operator.json` is approved with real public policy,
  support, security, checkout, and merchant fields.
- `release/beta-metrics.json` contains a current approved aggregate report at
  or above the documented thresholds.
- `release/installed-acceptance.json` contains current non-placeholder evidence
  hashes for interaction, accessibility, compatibility, and update/rollback.
- `release/brand-clearance.json` is approved after real clearance, with every
  check true and no unresolved conflict.

Copying the tracked templates and changing only `status` to `approved` is
explicitly rejected.

## Implemented Fail-Closed Foundations

- `scripts/verify_productization_readiness.py` separates source,
  commercial-prebuild, and commercial-final readiness. It validates operator,
  brand, beta, installed-app, release environment, key isolation, Git/tag,
  artifact, and Cask evidence without writing secret values to reports.
- `scripts/generate_release_metadata.sh` records exact ZIP/DMG hashes, byte
  counts, public HTTPS URLs, version, build, architecture, bundle ID, and
  minimum macOS. Developer ID packaging requires an explicit public
  `OPENWHISPER_RELEASE_BASE_URL`.
- `scripts/update_homebrew_cask.sh` writes both the exact ZIP URL and SHA-256.
  The tracked unreleased Cask retains an impossible all-zero hash.
- `scripts/package_app.sh` signs nested Sparkle components, supports a
  dedicated notary keychain, submits App and DMG, staples both, and verifies
  Gatekeeper.
- `scripts/verify_release_gate.sh` verifies Developer ID, Team ID, hardened
  runtime, notarization, stapling, Gatekeeper, dependency licenses,
  manifest/Cask agreement, pinned Sparkle 2.9.4, feed/key configuration,
  signed appcast, capability policy, and license key.
- `scripts/verify_remote_release_assets.sh` downloads without redirects,
  checks ZIP/DMG hashes, requires the published appcast and capability policy
  to be byte-identical to the gated files, and verifies both signatures.
- `scripts/archive_release_candidate.sh` and
  `scripts/restore_release_candidate.sh` move the exact notarized candidate
  across separate Actions runs. They bind the archive to the source commit,
  repository, product identity, version, build, architecture, manifest,
  artifact hashes, fixed archive root, extraction limits, and a separate
  SHA-256.
- `.github/workflows/release.yml` pins Checkout, Upload Artifact, and Download
  Artifact by commit. Signing/notary/private Sparkle and capability keys are
  exposed only during `prepare`; `finalize` receives the prepared candidate
  and public verification configuration, not private signing material.

The private GitHub repository and its draft release are review surfaces, not
the public Sparkle/download host.

## Commercial Release Flow

### 1. Configure real evidence and protected material

Use `release/production.env.example` only as a variable-name reference. Do not
place private keys, P12 files, P8 files, passwords, or production credentials
inside the repository.

Required public URLs must be credential-free HTTPS:

```text
OPENWHISPER_RELEASE_BASE_URL
OPENWHISPER_SPARKLE_FEED_URL
OPENWHISPER_CAPABILITY_POLICY_URL
```

### 2. Prepare once

```bash
./scripts/release_commercial.sh prepare
```

Prepare runs commercial prebuild readiness, the full check harness, Developer
ID packaging, notarization, appcast and capability-policy generation, Cask
generation, the commercial release gate, and installation.

In GitHub Actions, the successful prepare run also stores:

```text
OpenWhisper-<version>-commercial-candidate.zip
OpenWhisper-<version>-commercial-candidate.sha256
```

### 3. Publish the exact candidate assets

Publish the exact prepared ZIP, DMG, appcast, and provider policy to their
configured URLs. Do not rebuild, resign, regenerate, or edit them after this
point.

Complete real installed-app, update/rollback, legal/operator, brand, and beta
evidence. Create `v<version>` on the exact candidate source commit.

### 4. Finalize without rebuilding

```bash
./scripts/release_commercial.sh finalize
```

In GitHub Actions, dispatch `finalize` from the same commit/tag and provide the
numeric successful `prepare` run ID. Finalize downloads and verifies that
candidate instead of building on a fresh runner.

Finalization fails on any source, archive, manifest, public URL, signature,
policy, Cask, tag, or evidence mismatch. On success it produces a release
evidence archive and creates or refreshes a private draft GitHub release. It
refuses to overwrite an already published GitHub release.

## Versioning

- `0.1.x`: private alpha and productization
- `0.2.x`: closed beta after P0 closure
- `0.5.x`: release candidate after signing, notarization, updater, and
  installed acceptance
- `1.0.0`: first supported commercial macOS release

Do not reuse historical version claims issued under another identity.
