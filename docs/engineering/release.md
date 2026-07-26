# Signed release runbook

VibeCompose has one feature-complete build. Release tooling does not create an
edition, entitlement, activation state, or feature tier.

## Local quality ladder

```bash
scripts/check.sh
scripts/package_app.sh
scripts/install_app.sh
./scripts/visual_acceptance.sh --install
./scripts/paste_acceptance.sh --install
scripts/check_packaged_app.sh
```

The installed path `/Applications/VibeCompose.app` is authoritative for TCC,
LaunchServices, keyboard, focus, paste, and interaction evidence. Never launch
`dist/VibeCompose.app` as live proof.

## Signed build

`scripts/release_signed.sh prepare` requires Developer ID signing, Hardened
Runtime, notarization and stapling, Gatekeeper assessment, a pinned Sparkle
framework and signed appcast, a signed provider-capability policy, exact
artifact hashes, and an atomic install with rollback. Candidate preflight also
requires a clean canonical Git checkout, canonical credential-free production
URLs, the optimized Swift release configuration, two distinct Ed25519 keys, and
owner-only private key files outside the repository. Local packaging defaults
to debug, while every Developer ID candidate fails unless
`VIBECOMPOSE_BUILD_CONFIGURATION=release`. The signed release gate verifies the Hardened Runtime flag,
Developer ID authority, Team ID, and trusted timestamp for the main app and
each embedded Sparkle executable. `notarytool` must also return two distinct
`Accepted` JSON receipts—one for the App submission and one for the DMG—and the
receipts are restored with the source-bound candidate rather than inferred from
CI logs.

Candidate preparation does not authorize publication. Before uploading any
artifact, `scripts/verify_release_readiness.py --phase public` must pass against
the exact candidate. It requires the version tag, approved brand clearance,
schema-v2 installed-app acceptance bound to the source commit and ZIP hash, the
privacy-bounded four-week Community Pilot aggregate, and the product owner's
matching Beta review. It also requires approved support, private security
reporting, privacy, and legal contact surfaces and verifies that the same URLs
are present in the English and Chinese policies with no private-Alpha-only
release copy. Template, ad-hoc, stale, synthetic, or mismatched evidence is
rejected.

After the exact ZIP, DMG, appcast, and provider policy are published to their
configured credential-free HTTPS locations, run:

```bash
scripts/release_signed.sh finalize
```

Finalize repeats public readiness, verifies the same prepared artifacts
remotely, and creates a checksum-protected evidence archive containing the
gated inputs and their hashes. Private signing keys and production environment
values never enter the repository or app bundle. This release gate does not
enable the remote Community Registry; that remains a separate Go/No-Go.

## Closeout

After acceptance, relaunch the normal installed app and leave its menu bar
process running. Skill Library or Creator changes should leave that window
visible when practical.
