# OpenWhisper Support Policy

> Private-alpha baseline: July 13, 2026

## Supported Alpha Environment

- Apple silicon Mac;
- macOS 13 or later;
- `/Applications/OpenWhisper.app`;
- the current private-alpha version;
- default ChatGPT account route or the documented OpenAI-compatible recovery route.

Intel builds, virtual machines, modified bundles, unsigned redistributions, beta macOS releases, and managed enterprise environments are best-effort until explicitly added to the compatibility matrix.

## Support Channel

Authorized private-alpha testers should use the repository issue tracker. Public commercial support must move to a permanent support address and published service scope before payment is accepted.

Security vulnerabilities should follow the repository `SECURITY.md` process rather than a public bug report.

## What to Include

1. OpenWhisper version and macOS version.
2. Whether the app is installed at `/Applications/OpenWhisper.app`.
3. Microphone and Accessibility status.
4. Default ChatGPT route or advanced recovery route.
5. Exact reproduction steps and the smallest non-sensitive error.
6. A redacted support archive generated from **Settings → Advanced → Export Diagnostics**, when requested.

Never attach access tokens, refresh tokens, cookies, API keys, raw crash reports, audio, transcripts, unrelated screenshots, or private document content.

## Priority Targets

These are private-alpha response targets, not a paid SLA:

| Priority | Example | Initial response target |
| --- | --- | --- |
| P0 | credential exposure, destructive data loss, repeatable wrong-target paste | 2 business days |
| P1 | app cannot complete dictation, install/update blocker | 3 business days |
| P2 | degraded workflow, compatibility issue | 5 business days |
| P3 | feature request, cosmetic issue | backlog review |

## Support Boundaries

OpenWhisper support covers the OpenWhisper app, its documented installation flow, and reproducible product behavior. It does not guarantee:

- ChatGPT or third-party account access;
- recovery of deleted third-party data;
- third-party endpoint uptime, pricing, rate limits, or policy decisions;
- troubleshooting of unrelated macOS, network, MDM, or account-security issues;
- transcription accuracy for every language, accent, microphone, or domain.

## Lifecycle

Private alpha builds may require upgrading to the latest build before support continues. Commercial release support, minimum supported versions, security-update windows, and end-of-life periods must be published before 1.0.
