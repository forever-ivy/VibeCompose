# OpenWhisper Upstream Incident and Recovery Playbook

> Operational baseline: July 13, 2026

## Purpose

OpenWhisper's default account route depends on upstream ChatGPT behavior that is not a documented public API. This playbook prevents an upstream incident from becoming repeated credential transmission, silent data loss, or misleading product claims.

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
5. Advanced users may switch transcription to their own HTTPS OpenAI-compatible endpoint.
6. Delete failed audio or all local data when recovery is no longer needed.

## Operator Response

1. Confirm the failure with a non-sensitive test account and the installed build.
2. Classify whether the incident affects authentication, transcription, AI Polish, or paste.
3. Stop release promotion and update public status/release notes.
4. Avoid increasing retry counts as an outage workaround.
5. Prepare a hotfix that disables or repairs the affected capability.
6. Verify the hotfix against the installed-app workflow and rollback path.
7. Publish recovery steps and whether any local data needs user action.
8. Complete a post-incident review without storing user audio or transcripts.

## Kill-Switch Status

The alpha currently has bounded retries, session invalidation, local feature controls, preserved failed audio, and an advanced user-owned recovery route. It does **not** yet have a remotely signed capability kill switch. Until a signed updater and signed update manifest are operating, disabling a broken managed route requires a new signed app release. This remains a commercial release blocker.

## Communication Rules

- Never describe the default route as a stable public API or guaranteed SLA.
- Never ask users to send access tokens, cookies, API keys, raw audio, or full transcripts.
- State exact affected versions and dates.
- Distinguish upstream failure from expired OpenWhisper session and local permission failure.
- Keep recovery instructions available in English and Simplified Chinese before public beta.
