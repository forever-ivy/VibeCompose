# OpenWhisper Release Evidence

This directory defines the non-secret evidence required before a commercial
macOS release. It does not contain signing keys, payment credentials, customer
data, or notarization credentials.

## Tracked files

- `commercial-operator.example.json` — required legal, policy, support, and
  checkout fields.
- `beta-metrics.example.json` — quantitative go/no-go thresholds from the
  macOS productization plan.
- `installed-acceptance.example.json` — real installed-app, accessibility,
  compatibility, update, rollback, and uninstall proof.
- `brand-clearance.json` — current product-name clearance decision. A
  `blocked` status intentionally prevents a commercial release.
- `production.env.example` — names of required release variables. It contains
  no secret values.

The approved, non-example files required by the commercial gate are:

```text
release/commercial-operator.json
release/beta-metrics.json
release/installed-acceptance.json
release/brand-clearance.json
```

The first three do not exist until real evidence is available. Do not copy the
templates and mark them approved without performing the described work.

## Commands

Repository/source readiness:

```bash
python3 scripts/verify_productization_readiness.py --stage source
```

Commercial candidate preparation:

```bash
scripts/release_commercial.sh prepare
```

The GitHub Actions `prepare` phase signs and notarizes once, then stores a
source-commit-bound candidate archive plus a separate SHA-256 file. The
candidate deliberately contains the exact App, ZIP, DMG, manifest, appcast,
capability policy, Cask, and prebuild report needed by `finalize`.

After the exact ZIP, DMG, appcast, and capability policy have been published
to the configured public HTTPS host, and installed-app, update/rollback,
legal, brand, and beta evidence has been completed:

```bash
scripts/release_commercial.sh finalize
```

In GitHub Actions, `finalize` also requires the successful `prepare` run ID.
It downloads and verifies that candidate instead of rebuilding on a fresh
runner. The source commit, version, build, architecture, archive checksum,
manifest hashes, and public URLs must all match.

Both commercial commands are fail-closed. They cannot turn missing operator
identity, name clearance, user metrics, Developer ID, notarization, updater
hosting, or manual installed-app proof into a passing release.

The private GitHub repository is not the public update/download host. Set
`OPENWHISPER_RELEASE_BASE_URL`, `OPENWHISPER_SPARKLE_FEED_URL`, and
`OPENWHISPER_CAPABILITY_POLICY_URL` to credential-free public HTTPS URLs.
