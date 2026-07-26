# VibeCompose Upstream Incident and Recovery Playbook

> Operational baseline: July 13, 2026

## Purpose

VibeCompose's default account route depends on upstream ChatGPT behavior that is not a documented public API. This playbook prevents an upstream incident from becoming repeated credential transmission, silent data loss, or misleading product claims.

## Detection Categories

| Signal | Classification | Default action |
| --- | --- | --- |
| 401 or non-Cloudflare 403 | authentication change | refresh once, then require reconnect |
| Cloudflare 403 | upstream challenge | bounded automatic attempts, preserve failed audio, expose Retry |
| 404 or incompatible schema | upstream contract change | stop treating the capability as healthy; require app update or recovery route |
| 429 | capacity/rate limit | stop dense retry; communicate retry timing when available |
| network/5xx | transient outage | bounded retry only; preserve recoverable work |
| repeated cross-user wrong result or credential concern | security incident | disable affected release path and issue a security update |

## User Recovery

1. Do not repeatedly press Retry during a broad outage.
2. Keep the failed recording only when the user has enabled failed-audio recovery.
3. Reconnect ChatGPT after an authentication failure.
4. Use clipboard-only output when automatic paste cannot be proven safe.
5. Advanced users may save their own API key in Keychain, configure an HTTPS
   OpenAI-compatible endpoint/model, run the synthetic-silence connection
   test, acknowledge possible provider charges, and switch transcription ASR
   to that route.
6. Switch back to the ChatGPT account route when the incident ends.
7. Delete the Recovery key, failed audio, or all local data when recovery is
   no longer needed.

## Operator Response

1. Confirm the failure with a non-sensitive test account and the installed build.
2. Classify whether the incident affects authentication, transcription, AI Polish, or paste.
3. Stop release promotion and update public status/release notes.
4. Avoid increasing retry counts as an outage workaround.
5. Publish a higher-revision signed capability policy that disables only the
   affected managed capability.
6. Verify the policy signature, build range, expiry, and installed-app block
   before changing public status.
7. Prepare a signed app hotfix when the upstream contract or client behavior
   also needs code changes.
8. Verify the hotfix against the installed-app workflow and rollback path.
9. Publish recovery steps and whether any local data needs user action.
10. Complete a post-incident review without storing user audio or transcripts.

## Kill-Switch Status

The app now implements a remotely signed capability kill-switch foundation for
managed transcription and ChatGPT AI Polish. A policy:

- is fetched only from the credential-free HTTPS URL pinned in the signed app;
- is verified with the separate Ed25519 public key pinned in the app;
- can only disable a named managed capability, never redirect requests or
  supply credentials;
- is checked before reading recording audio, resolving a managed token, or
  sending transcript text;
- has a maximum 31-day lifetime, an explicit build range, and a monotonic revision
  that rejects rollback/replay;
- is cached owner-only, and an invalid or older response cannot replace a
  previously accepted active disable.

The private alpha intentionally omits the production URL/key. A signed public
build requires a separate production signing key, permanent HTTPS policy host,
initial signed policy, and installed-app incident drill.

Generate and verify a policy without placing the private key in the repository:

```bash
VIBECOMPOSE_CAPABILITY_PRIVATE_KEY_FILE=/secure/vibecompose-capability.key \
scripts/generate_provider_capability_policy.swift \
  --revision 1 \
  --incident-id OW-INC-2026-001 \
  --expires-at 2026-07-14T12:00:00Z \
  --disable managedTranscription

scripts/verify_provider_capability_policy.swift \
  --policy dist/provider-capabilities.json \
  --public-key BASE64_PUBLIC_KEY \
  --build 1
```

## Communication Rules

- Never describe the default route as a stable public API or guaranteed SLA.
- Never ask users to send access tokens, cookies, API keys, raw audio, or full transcripts.
- State exact affected versions and dates.
- Distinguish upstream failure from expired VibeCompose session and local permission failure.
- Keep recovery instructions available in English and Simplified Chinese before public beta.
