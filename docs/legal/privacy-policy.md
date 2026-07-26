# VibeCompose Privacy Policy

> Effective for the private alpha: July 13, 2026
>
> Last updated: July 14, 2026
>
> Product status: pre-release macOS alpha

This policy describes the current VibeCompose macOS application. VibeCompose does not currently operate its own analytics, account, synchronization, advertising, or transcription server.

## 1. What VibeCompose Processes

### Audio and transcription requests

When you start dictation, VibeCompose records a short audio clip on your Mac. On the default route, the clip and transcription instructions are sent to the ChatGPT service using the ChatGPT session you connected in VibeCompose. If you select the advanced OpenAI-compatible recovery route, the clip is sent to the HTTPS endpoint you configured using your own credential.

When AI Polish or a non-Direct Skill runs through the ChatGPT route, the
request may also include the current transcript, the resolved declarative
Skill prompt, resolved terminology, a Writing Style summary you assigned to
that Skill, and selected text only when you authorized that Skill to read the
selection. VibeCompose does not send the complete Skill Registry, full App
Rules, unrelated installed package files, Writing Style creation source
samples, the whole screen, or an entire document through this path.

The Advanced Settings connection test sends only a generated 0.1-second
silent WAV, the configured model, and your Recovery credential. It does not
read or send your recordings, transcripts, or terminology. Your configured
provider may still charge for that request.

VibeCompose is an independent project and is not affiliated with, sponsored by, or endorsed by OpenAI. Third-party processing is governed by the terms and privacy policy of the service you choose:

- OpenAI Privacy Policy: `https://openai.com/policies/privacy-policy/`
- OpenAI Terms of Use: `https://openai.com/policies/terms-of-use/`

### Local application data

VibeCompose may store the following data under `~/Library/Application Support/VibeCompose/`:

| Data | Default retention |
| --- | --- |
| Final transcript history | 30 days, at most 500 records |
| Raw ASR text | Off unless explicitly enabled |
| Failed recordings for Retry | 24 hours, at most 10 records |
| Successful recordings | Deleted after processing |
| Performance diagnostics | 14 days, at most 1,000 records |
| Local product metrics | Off by default; if enabled, 30 days and at most 5,000 events |
| Settings and personal terminology | Until changed or deleted |
| Custom Writing Styles | Until deleted; creation source samples are cleared and not stored by default |
| Installed declarative Community Skills | Until disabled/uninstalled or Delete All Data |

Known password managers, Keychain Access, and macOS Passwords are excluded from transcript history and failed-audio recovery by default. You can add more sensitive applications.

### Keychain credentials

The ChatGPT session connected in VibeCompose is stored in macOS Keychain under
`app.vibecompose.mac.ChatGPTSession`. An optional OpenAI-Compatible Recovery
API key is stored separately under
`app.vibecompose.mac.OpenAICompatibleAPIKey`. VibeCompose does not read that
key from `OPENAI_API_KEY` and does not intentionally write access tokens,
refresh tokens, API keys, cookies, or authorization headers to `config.json`,
transcript history, diagnostics, screenshots, or logs.

## 2. Diagnostics and Support Archives

Performance diagnostics contain timing, byte counts, provider categories,
result categories, bounded Skill/terminology counts and risk indicators, and
error categories. They do not intentionally contain audio, transcript text,
clipboard contents, credentials, selected text, Writing Style contents,
terminology text, Community Skill prompts/files, or installed package names.

Optional local product metrics are disabled by default. If enabled, they
contain only product version/build, completed Onboarding step, provider
category, audio-duration bucket, processing-latency bucket, delivery category,
and failure category. They do not contain audio, transcript or clipboard text,
app names, bundle identifiers, file paths, account details, or a persistent
user/install identifier. VibeCompose does not upload them automatically.
When metrics are enabled, you may use **Settings → Context & Privacy → Export Product
Metrics** to create an aggregate JSON report for manual review or sharing. The
report contains count maps only and omits individual event timestamps.

When you choose **Settings → Advanced → Export Diagnostics**, VibeCompose creates a local ZIP for you to review and share manually. The archive contains:

- product, operating-system, permission, authentication-state, and signing-state summaries;
- non-secret configuration flags and retention values;
- redacted latency records;
- opt-in local product metrics with enum and bucket values only;
- whitelisted metadata from up to five recent VibeCompose crash reports;
- checksums for the included files.

The archive excludes audio, transcripts, clipboard text, account email,
selected text, terminology text, Writing Style summaries/examples/source
samples, Community Skill prompts/files/package names, custom endpoint URLs,
credentials, raw crash-report bodies, history, Recovery metadata, and
`config.json`. It is not uploaded automatically.

## 3. Clipboard and Accessibility

VibeCompose writes the completed transcript to the macOS pasteboard. If Accessibility permission and a current editable target are both confirmed, it may send `Cmd+V`. Otherwise, the transcript remains in the clipboard for manual paste. VibeCompose does not intentionally store unrelated clipboard contents.

## 4. Your Controls

You can:

- disable or limit transcript history, failed-audio recovery, diagnostics, and local product metrics;
- export aggregate local product metrics for your own review or voluntary sharing;
- disable raw transcript storage;
- add sensitive applications that must not create history or Recovery records;
- revoke per-Skill selected-text access and change or remove Writing Style
  assignments;
- disable Domain Packs and local Community Skills, roll back an installed
  version, or uninstall it;
- delete individual history or Recovery records;
- sign out of ChatGPT;
- remove the OpenAI-Compatible Recovery key without deleting other data;
- use **Delete All Data** to remove local settings, terminology, custom Style
  Capsules, installed Community Skills, history, failed recordings,
  diagnostics, product metrics, Retry files, the saved ChatGPT session, and the
  Recovery API key.

Deleting local VibeCompose data does not delete information already sent to or retained by a third-party service. Use that service's account and privacy controls for third-party data.

## 5. Sharing and Sale of Data

VibeCompose does not currently sell personal information, serve advertising, or upload product analytics to an VibeCompose-operated server. Data is disclosed only when you direct the app to use a third-party transcription service, manually share a support archive, or when disclosure is required by applicable law.

## 6. Security

VibeCompose uses separate macOS Keychain items for the connected ChatGPT
session and optional Recovery API key, and uses owner-only local file
permissions where supported, bounded retention, HTTPS endpoint validation,
redirect rejection, and conservative paste behavior. No security
measure can guarantee absolute security. Keep macOS updated and do not share
diagnostic archives without reviewing them.

## 7. Children

VibeCompose is a productivity tool for users who are permitted to use the connected third-party services. It is not directed to children under 13.

## 8. Changes

Material changes will be dated in this document and summarized in release notes.

## 9. Contact

Private-alpha participants should use the authorized VibeCompose GitHub issue tracker. Do not attach audio, transcripts, credentials, raw crash reports, or unrelated personal information.
