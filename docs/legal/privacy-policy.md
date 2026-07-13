# OpenWhisper Privacy Policy

> Effective for the private alpha: July 13, 2026
>
> Last updated: July 13, 2026
>
> Product status: pre-release macOS alpha

This policy describes the current OpenWhisper macOS application. OpenWhisper does not currently operate its own analytics, account, synchronization, advertising, or transcription server.

## 1. What OpenWhisper Processes

### Audio and transcription requests

When you start dictation, OpenWhisper records a short audio clip on your Mac. On the default route, the clip and transcription instructions are sent to the ChatGPT service using the ChatGPT session you connected in OpenWhisper. If you select the advanced OpenAI-compatible recovery route, the clip is sent to the HTTPS endpoint you configured using your own credential.

The Advanced Settings connection test sends only a generated 0.1-second
silent WAV, the configured model, and your Recovery credential. It does not
read or send your recordings, transcripts, or terminology. Your configured
provider may still charge for that request.

OpenWhisper is an independent project and is not affiliated with, sponsored by, or endorsed by OpenAI. Third-party processing is governed by the terms and privacy policy of the service you choose:

- OpenAI Privacy Policy: `https://openai.com/policies/privacy-policy/`
- OpenAI Terms of Use: `https://openai.com/policies/terms-of-use/`

### Local application data

OpenWhisper may store the following data under `~/Library/Application Support/OpenWhisper/`:

| Data | Default retention |
| --- | --- |
| Final transcript history | 30 days, at most 500 records |
| Raw ASR text | Off unless explicitly enabled |
| Failed recordings for Retry | 24 hours, at most 10 records |
| Successful recordings | Deleted after processing |
| Performance diagnostics | 14 days, at most 1,000 records |
| Local product metrics | Off by default; if enabled, 30 days and at most 5,000 events |
| Settings and terminology | Until changed or deleted |

Known password managers, Keychain Access, and macOS Passwords are excluded from transcript history and failed-audio recovery by default. You can add more sensitive applications.

### Keychain credentials

The ChatGPT session connected in OpenWhisper is stored in macOS Keychain under
`app.openwhisper.mac.ChatGPTSession`. An optional OpenAI-Compatible Recovery
API key is stored separately under
`app.openwhisper.mac.OpenAICompatibleAPIKey`. OpenWhisper does not read that
key from `OPENAI_API_KEY` and does not intentionally write access tokens,
refresh tokens, API keys, cookies, or authorization headers to `config.json`,
transcript history, diagnostics, screenshots, or logs.

## 2. Diagnostics and Support Archives

Performance diagnostics contain timing, byte counts, provider categories, result categories, and error categories. They do not intentionally contain audio, transcript text, clipboard contents, or credentials.

Optional local product metrics are disabled by default. If enabled, they
contain only product version/build, completed Onboarding step, provider
category, audio-duration bucket, processing-latency bucket, delivery category,
and failure category. They do not contain audio, transcript or clipboard text,
app names, bundle identifiers, file paths, account details, or a persistent
user/install identifier. OpenWhisper does not upload them automatically.

When you choose **Settings → Advanced → Export Diagnostics**, OpenWhisper creates a local ZIP for you to review and share manually. The archive contains:

- product, operating-system, permission, authentication-state, and signing-state summaries;
- non-secret configuration flags and retention values;
- redacted latency records;
- opt-in local product metrics with enum and bucket values only;
- whitelisted metadata from up to five recent OpenWhisper crash reports;
- checksums for the included files.

The archive excludes audio, transcripts, clipboard text, account email, terminology, custom endpoint URLs, credentials, raw crash-report bodies, history, Recovery metadata, and `config.json`. It is not uploaded automatically.

## 3. Clipboard and Accessibility

OpenWhisper writes the completed transcript to the macOS pasteboard. If Accessibility permission and a current editable target are both confirmed, it may send `Cmd+V`. Otherwise, the transcript remains in the clipboard for manual paste. OpenWhisper does not intentionally store unrelated clipboard contents.

## 4. Your Controls

You can:

- disable or limit transcript history, failed-audio recovery, diagnostics, and local product metrics;
- disable raw transcript storage;
- add sensitive applications that must not create history or Recovery records;
- delete individual history or Recovery records;
- sign out of ChatGPT;
- remove the OpenAI-Compatible Recovery key without deleting other data;
- use **Delete All Data** to remove local settings, terminology, history, failed recordings, diagnostics, product metrics, Retry files, the saved ChatGPT session, and the Recovery API key.

Deleting local OpenWhisper data does not delete information already sent to or retained by a third-party service. Use that service's account and privacy controls for third-party data.

## 5. Sharing and Sale of Data

OpenWhisper does not currently sell personal information, serve advertising, or upload product analytics to an OpenWhisper-operated server. Data is disclosed only when you direct the app to use a third-party transcription service, manually share a support archive, or when disclosure is required by applicable law.

## 6. Security

OpenWhisper uses separate macOS Keychain items for the connected ChatGPT
session and optional Recovery API key, owner-only local file permissions where
supported, bounded retention, HTTPS endpoint validation, redirect rejection,
and conservative paste behavior. No security measure can guarantee absolute
security. Keep macOS updated and do not share diagnostic archives without
reviewing them.

## 7. Children

OpenWhisper is a productivity tool for users who are permitted to use the connected third-party services. It is not directed to children under 13.

## 8. Changes

Material changes will be dated in this document and summarized in release notes. A public paid release must identify the commercial operator and permanent privacy contact before distribution.

## 9. Contact

Private-alpha participants should use the authorized OpenWhisper GitHub issue tracker. Do not attach audio, transcripts, credentials, raw crash reports, or unrelated personal information. The permanent commercial privacy contact remains a release gate.
