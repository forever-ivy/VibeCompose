# Contributing to OpenWhisper

## Development Flow

1. Run `./scripts/check.sh` before submitting changes.
2. Use `./scripts/build_and_run.sh` to validate the installed app path.
3. Keep `product.env` as the source of truth for product identity.
4. Keep `version.env` as the source of truth for release version metadata.
5. Update documentation when changing permissions, provider behavior, storage, packaging, startup, release assets, or public claims.

## Engineering Standards

- Keep the app macOS-native and keyboard-first.
- Preserve the single-trigger `F5` start/stop workflow.
- Paste only when a current editable target is verified; otherwise preserve the transcript in the clipboard.
- Treat tokens, audio, transcripts, and recovery files as sensitive data.
- Never send managed credentials to user-configurable endpoints.
- Keep undocumented upstream dependencies explicit in product copy and error handling.
- Do not add a second product identity, legacy brand alias, or compatibility path without an approved migration requirement.

## Verification

Minimum verification for product changes:

```bash
swift build --package-path .
swift test --package-path .
OPENWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/check.sh
```

For packaging or install changes:

```bash
OPENWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/package_app.sh
./scripts/install_app.sh
./scripts/check_packaged_app.sh
```

Native interaction changes require installed-app verification through `/Applications/OpenWhisper.app` and the Computer Use flow described in `AGENTS.md`.
