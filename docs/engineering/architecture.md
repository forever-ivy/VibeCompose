# OpenWhisper macOS Architecture

## 1. Product Scope

OpenWhisper is a native AppKit + SwiftUI menu bar application for one global dictation workflow:

```text
focus an editable target
→ F5 starts recording
→ F5 stops recording
→ transcribe
→ normalize terminology
→ optionally polish
→ re-check the current target
→ paste when proven safe, otherwise copy
```

The current product line is macOS-only. The installed application at `/Applications/OpenWhisper.app` is the authoritative runtime for permission and interaction verification; `dist/OpenWhisper.app` is packaging output only.

## 2. Trust-Boundary Rules

The implementation follows four fail-safe rules:

1. A previously active application can be reactivated, but old launch context is never proof that the current focused control is editable.
2. A managed ChatGPT token can only be attached to the built-in approved HTTPS origins and paths.
3. Recovery metadata cannot choose an arbitrary file path.
4. An asynchronous result may mutate UI, storage, retry state, or paste state only while its dictation session is still current.

When OpenWhisper cannot prove a safe insertion target, the transcript remains in the clipboard. HUD Retry and saved Recovery Retry are copy-only by default.

## 3. Runtime State and Session Ownership

`AppCoordinator` is the current orchestration boundary. It owns:

- hotkey transitions;
- microphone permission and recording;
- the active `sessionID`;
- transcription and optional polish tasks;
- HUD state;
- history, diagnostics, and recovery writes;
- pending Retry state and expiry;
- final text insertion.

The effective session flow is:

```text
idle
→ starting(sessionID)
→ recording(sessionID)
→ processing(sessionID)
→ insertedAndVerified | pasteDispatchedClipboardRetained | copiedToClipboard
  | retryableFailure | terminalFailure
→ idle
```

Every recording/processing branch checks `activeSessionID` before a late result can update the current session. Cancellation clears the current ID and associated tasks. `AudioRecorder` also owns a monotonic deadline task and invokes the coordinator when the configured recording limit is reached.

The long-term target remains a dedicated `DictationSession` model rather than coordinator-owned state fields.

## 4. Runtime Components

### App and interaction

- `AppDelegate`
  - creates the application coordinator and menu bar lifecycle.
- `AppCoordinator`
  - orchestrates recording, transcription, retry, insertion, storage, and setup state.
- `StatusMenuController`
  - exposes status, Settings, History/Recovery entry points, and Quit.
- `HotkeyMonitor`
  - registers the global `F5` shortcut.
- `OverlayController`
  - renders recording, processing, verified-insert, paste-sent, copied, error, and retryable-error HUD states;
  - uses a presentation generation so stale auto-hide tasks and animation completions cannot hide a newer state.
- `PreferencesWindowController`
  - hosts the current workflow-sidebar Settings surface, including Privacy & Data.

### Audio and transcription

- `AudioRecorder`
  - records mono PCM WAV clips;
  - enforces `maxDurationSeconds` while recording;
  - deletes cancelled temporary recordings.
- `ChatGPTTranscriber`
  - executes the managed ChatGPT or user-owned OpenAI-compatible transcription route;
  - records timing and response-category metrics;
  - opens source audio with `O_NOFOLLOW`, validates regular-file metadata and the 25 MB limit before reading content, then re-checks device/inode/size;
  - builds a private `0600` multipart file in 64 KB chunks and uploads it with `URLSession.upload(fromFile:)`;
  - removes multipart files after success, HTTP failure, transport failure, or cancellation.
- `DictationPipeline`
  - sequences ASR, terminology normalization, optional polish, and final normalization;
  - asks `TextPolishDecisionEngine` whether Auto mode should run before
    resolving or sending a second rewrite request.
- `TextPolishDecisionEngine`
  - skips short, low-complexity Direct dictation;
  - runs for explicit correction, structure, email, translation, long-form,
    or future Voice Mode intent;
  - emits a bounded reason such as `skip_short_direct`,
    `run_self_correction`, or `run_long_dictation` without retaining text.
- `TranscriptionPromptBuilder`
  - creates the fixed direct-output prompt and exact preservation hints.
- `TerminologyNormalizer`
  - applies deterministic terminology alignment plus explicit simplified/traditional/preserve language and automatic/full-width/half-width/preserve punctuation preferences.
- `TechnicalLiteralTokenizer`
  - protects URLs, email addresses, paths, filenames, versions, addresses/identifiers, command flags, environment variables, and code spans;
  - uses private-use tokens for local normalization and explicit model-safe tokens for AI Polish;
  - requires each model-safe token to survive exactly once before restoring original literals.
- `OpenAICompatibleTextPolisher`
  - performs the optional post-ASR rewrite through the managed ChatGPT responses route and fails open to usable ASR.

### Authentication and network

- `ChatGPTAuthManager`
  - stores the current ChatGPT session generation;
  - coalesces concurrent refreshes into one flight;
  - invalidates in-flight work on sign-out;
  - commits a late result only when its generation and original refresh token still match.
- `BrowserAuthBridge`
  - runs the default-browser OAuth + PKCE flow;
  - validates callback method, path, state, and duplicate query parameters;
  - applies timeout/cancellation cleanup to the local listener.
- `ChatGPTSessionStore`
  - persists the managed session in macOS Keychain under `app.openwhisper.mac.ChatGPTSession`.
- `KeychainOpenAICompatibleCredentialStore`
  - persists the user-owned Recovery API key in a separate generic-password
    item under `app.openwhisper.mac.OpenAICompatibleAPIKey`;
  - trims and bounds the credential, uses
    `AfterFirstUnlockThisDeviceOnly`, and never writes the key or an
    environment-variable name into `config.json`.
- `OpenAICompatibleConnectionTester`
  - validates the user-owned HTTPS endpoint and model;
  - sends only a generated 0.1-second silent WAV with the Keychain credential;
  - never reads user audio or transcript text and redacts credentials from
    provider error messages.
- `ManagedEndpointPolicy`
  - fixes managed transcription and responses endpoints to approved `https://chatgpt.com` paths;
  - rejects credentials, query strings, fragments, non-HTTPS schemes, and unapproved ports;
  - validates user-owned endpoints separately.
- `SecureHTTPClient`
  - uses an ephemeral session and rejects HTTP redirects.

Managed credentials and user-owned API credentials are separate trust domains.
The advanced OpenAI-compatible endpoint never receives the managed ChatGPT
token. The shell environment is not a Recovery credential source.

### Signed provider capability policy

`ProviderCapabilityPolicyController` is a separate safety boundary for broad
upstream or security incidents:

- production configuration is a paired credential-free HTTPS policy URL and a
  separate 32-byte Ed25519 public key embedded in the signed app;
- the signed envelope contains base64 payload bytes plus their signature, so
  verification does not depend on JSON re-serialization;
- policies can only disable `managedTranscription` or `chatGPTTextPolish`;
- managed transcription checks the policy before reading audio or resolving a
  token, and AI Polish checks before resolving a token or sending text;
- policies expire after at most 31 days, may target a build range, and use a
  monotonic revision; older or conflicting revisions cannot replace an active
  cached policy;
- the accepted envelope is cached as `0600` under Application Support;
- refresh sends no account, audio, transcript, clipboard, terminology, or
  endpoint data.

Private-alpha packages omit this production configuration. Developer ID
packaging and the commercial release gate require the URL, public key, and a
matching locally verified signed policy before release.

## 5. Safe Output and Retry

`TextInjector` first writes the final text to the pasteboard, then selects one of:

- `.keyPressPaste` when Accessibility is trusted and a current editable target is confirmed;
- `.clipboardFallback(.accessibilityPermissionRequired)`;
- `.clipboardFallback(.noEditableTarget)`;
- `.clipboardFallback(.retryRequiresManualPaste)`.

Immediately before dispatch, OpenWhisper captures the same focused AX target and, when the destination exposes both `AXValue` and `AXSelectedTextRange`, a bounded before snapshot. After `Cmd+V`, it polls that same target for up to 500 ms and compares the observed value against the exact UTF-16 replacement implied by the original selection.

Delivery outcomes are intentionally distinct:

- `.insertedAndVerified`: the same AX target exposed the expected text transition;
- `.pasteDispatchedClipboardRetained`: `Cmd+V` was sent, but AX verification was unavailable or inconclusive, so the transcript remains in the clipboard;
- `.copiedToClipboard(...)`: no paste event was sent.

The original clipboard is restored only after `.insertedAndVerified` and only when the pasteboard change count still proves OpenWhisper owns the current contents. Retry output and unverified paste output intentionally remain in the clipboard.

Paste-target waiting is implemented by `AsyncPasteTargetWaiter` with `ContinuousClock` and cancellation-aware `Task.sleep`. Focus checks and application activation briefly execute on MainActor, while the wait itself no longer blocks it. Cancelling the active dictation session also cancels pending insertion and prevents a late outcome from updating HUD or history.

The remaining acceptance boundary is application coverage: targets that expose a stable value/range transition can reach the verified state, while browser composers, Terminal-style controls, and some custom editors may legitimately remain in the “Paste sent” state. Installed-app Notes/TextEdit/Terminal and third-party editor matrices remain release evidence rather than assumptions.

## 6. Storage and Privacy

The application support root is:

```text
~/Library/Application Support/OpenWhisper/
```

Current defaults:

| Store | Contents | Default retention |
| --- | --- | --- |
| `config.json` | user configuration and privacy preferences | until reset/delete |
| `transcription-history.jsonl` | final text, target metadata, outcome; raw ASR only when enabled | 30 days, 500 records |
| `Recovery/recovery-history.jsonl` | failed-dictation metadata | 24 hours, 10 records |
| `Recovery/Audio/*.wav` | failed recordings only | same as Recovery metadata |
| `latency.jsonl` | timing, byte counts, provider labels, result/error categories | 14 days, 1,000 records |
| `Retry/` | transient in-memory Retry copy | expires and is removed on startup if orphaned |

Privacy behavior:

- successful recordings are deleted after processing and are not copied into Recovery;
- raw ASR history is disabled by default;
- known password managers, Keychain, and Passwords are excluded from transcript/recovery persistence;
- users can add extra sensitive bundle identifiers in configuration;
- diagnostics do not include audio, transcript text, clipboard content, tokens, or complete provider response bodies;
- storage directories use `0700` and data files use `0600` where supported;
- bounded JSONL tail reads avoid synchronously loading an unlimited history file;
- startup pruning enforces time and count limits.

The system temporary directory is also treated as owned-but-transient storage. Startup cleanup removes only strict UUID-shaped `openwhisper-<UUID>.wav` and `openwhisper-upload-<UUID>.multipart` artifacts, ignores lookalikes/directories, and unlinks a matching symlink without following its target. Normal application termination calls coordinator shutdown to cancel active work and synchronously remove owned processing audio.

`AppCoordinator.deleteAllUserData()` deletes both Keychain trust domains,
then `StorageCleanupService.deleteAllData()` validates the
application-support boundary, refuses symbolic-link deletion, removes the
complete local data root, recreates a secure empty directory, and saves a
fresh default configuration.

## 7. Recovery Containment

Recovery records persist an opaque UUID. The derived filename is always `<UUID>.wav`; legacy `audioFileName` values are ignored.

Before Copy or Retry, `RecoveryStore` verifies:

- the Recovery root and JSONL index are not symbolic links;
- the audio directory is a real directory and not a symbolic link;
- the derived file is directly contained in that directory;
- the target is a regular non-symlink file;
- the resolved path remains inside the resolved recovery directory;
- the file is below the upload limit;
- the first 12 bytes contain a RIFF/WAVE header.

Startup pruning removes unreferenced audio, drops records whose audio no longer passes containment checks, and tightens retained legacy audio to `0600`. Corrupt or malicious metadata therefore cannot select an arbitrary user-readable file or redirect cleanup into another directory.

## 8. Settings and Product Surfaces

The current Settings window exposes:

- account and permission state;
- dictation and text polish;
- history/recovery entry points;
- terminology entry points;
- paste behavior;
- Privacy & Data;
- Advanced Recovery endpoint/model editing, Keychain API-key save/remove,
  synthetic-silence connection testing, explicit paid-API confirmation, and
  one-click return to the ChatGPT account route.

Advanced Recovery changes dictation ASR only. AI Polish remains on the
ChatGPT-authenticated Responses route and continues to require a usable
ChatGPT session.

History and Terminology now use separate native management windows. History supports filtering, details, copy/retry, audio actions, deletion, and automatic refresh. Terminology uses stable entry identifiers and supports search, sorting, editing, enable/disable, deletion, CSV import/export, import conflict preview, and a global Quick Add panel.

Settings uses a native resizable `NavigationSplitView` and immediately
persists configuration changes. Remaining productization work is full
keyboard/VoiceOver/high-contrast acceptance across Settings and the
management windows.

## 9. Benchmarking and Diagnostics

- `LatencyRecorder` rewrites a bounded JSONL sample set using the configured
  retention policy and records only the bounded AI Polish decision reason,
  not the transcript used to make that decision.
- `ProductMetricsRecorder` is a separate, opt-in, local-only JSONL store.
  It records app launch, completed Onboarding steps, dictation/Retry
  start/success/failure, user-discarded sessions, provider category,
  delivery/failure enums, and duration/latency buckets. It has no user/install
  identifier, app name, bundle identifier, path, account field, or content
  field.
- Product metrics default off, use owner-only permissions and bounded
  retention, reject symbolic-link storage, and are never uploaded
  automatically.
- `ProductMetricsExporter` reduces local rows to version/build, event,
  Onboarding, provider, duration/latency, delivery, and failure count maps. The
  owner-only JSON report contains no individual event timestamps and is
  created only after the user chooses an export destination.
- `scripts/benchmark_stt.sh` runs explicit audio inputs through packaged-app benchmark mode.
- Benchmark output includes cold/warm `auth_ms`, `transcribe_ms`, and `total_ms` p50/p95 summaries.
- Product diagnostics and optional product metrics are local-only in the current alpha; no product analytics upload is enabled.
- `SupportDiagnosticsExporter` creates an owner-only local ZIP containing a non-secret runtime/configuration summary, redacted latency rows, enum/bucket-only product metrics, whitelisted metadata from up to five crash reports, and per-file SHA-256 values.
- Support exports exclude audio, transcripts, clipboard text, account email, credentials, terminology, custom endpoint values, raw crash bodies, history, Recovery metadata, and `config.json`; they are never uploaded automatically.

## 10. Packaging and Verification

Sources of truth:

- `product.env` — shell-facing product identity;
- `Sources/OpenWhisper/ProductIdentity.swift` — runtime identity;
- `version.env` — version/build;
- `/Applications/OpenWhisper.app` — installed runtime.

Canonical commands:

```bash
OPENWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/check.sh
OPENWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/package_app.sh
./scripts/install_app.sh
./scripts/check_packaged_app.sh
```

HUD visual acceptance launches the installed app once per required state and asks the app to self-render its panel into PNG. CoreGraphics window capture remains a fallback, so automated visual evidence does not depend on granting the shell Screen Recording access.

Settings, Onboarding, History, Terminology, and Quick Add self-capture launches
enable `SnapshotPrivacyMode` before loading runtime state. The capture process
uses `AppConfig()` defaults, an empty in-memory ChatGPT session store, an empty
in-memory OpenAI-Compatible credential store, and empty history/recovery/
terminology collections. It also disables persistence, permission requests,
support export, update mutations, and normal hotkey/runtime startup so
acceptance artifacts cannot contain the user's account email, custom endpoint,
transcripts, recovery metadata, or terminology.

The same privacy boundary applies to
`--accessibility-audit-output`. `AccessibilityAudit` enables AppKit's enhanced
accessibility interface for the transient process, walks the SwiftUI virtual
accessibility tree, and records only roles, control names, identifiers, action
names, and standard subroles. The installed-app harness covers all six Settings
panes, all four Onboarding steps, History, Terminology, and Quick Add and fails
when an actionable control has neither an explicit/associated name nor a
standard AppKit subrole description. Values and user content are not exported.

`--interaction-acceptance` extends the same privacy boundary to long-lived
installed-app sessions used by official Computer Use. It presents default
configuration, empty in-memory credentials and empty records, suppresses
configuration/data writes, and does not persist Onboarding completion.
`scripts/interaction_acceptance.sh` launches one requested product surface and
restores the normal installed menu bar runtime after acceptance.

Ad-hoc signing is allowed only for local development. Commercial distribution still requires strict environment parsing, a fixed Developer ID/Team ID, Hardened Runtime, notarization and stapling, fail-closed Gatekeeper checks, staged atomic installation with rollback, fixed artifact SHA-256 values, and a signed updater.

Release metadata and distribution guards currently include:

- exact ZIP/DMG byte counts, HTTPS download URLs, and SHA-256 values in `dist/release-manifest.json`;
- a Homebrew Cask that uses an impossible all-zero checksum until the release preparation script records the exact notarized ZIP hash;
- installer validation of bundle ID, version, build, architecture, signature, and—when release enforcement is enabled—the expected Developer ID Team ID;
- a dependency-license manifest that exactly covers `Package.resolved`,
  verifies source URL/revision/version and vendored license SHA-256, ships
  notices inside the App, and is rechecked by package and commercial release
  gates;
- a commercial release gate that requires Developer ID, stapling, Gatekeeper success, manifest/Cask consistency, and signed-updater `SUFeedURL`/`SUPublicEDKey` configuration.
- a separate signed provider capability policy gate requiring
  `OWCapabilityPolicyURL`, `OWCapabilityPublicEDKey`, and a verified,
  non-expired policy covering the release build.

Sparkle 2.9.4 is pinned, embedded, signed with the app, and exposed through the status menu and Advanced Settings. Packaging accepts only paired HTTPS feed and Ed25519 public-key configuration, and release tooling can generate a signed channel appcast without storing the private key in the repository. The commercial release gate intentionally remains closed until production hosting/keys, a real signed appcast, Developer ID notarization, and installed update/rollback proof exist.

## 11. Known Architectural Gaps

The current alpha must not be described as commercially release-ready while these remain:

- insertion-verified, paste-dispatched, and clipboard results are separate,
  but the trusted installed-app Notes/TextEdit/Terminal focus matrix remains
  incomplete;
- Settings now uses `NavigationSplitView` with immediate persistence, and the
  HUD implementation respects Reduce Motion, strengthens Increase Contrast,
  and posts state announcements; trusted installed-app keyboard/VoiceOver and
  high-contrast interaction evidence is still incomplete across Settings,
  Onboarding, History, Terminology, Quick Add, and HUD;
- a real Developer ID/notarized artifact and installed Sparkle update/rollback proof are not complete;
- permanent capability-policy hosting, a separate production Ed25519 key, and
  an installed incident disable/restore drill are not complete;
- clean-TCC microphone/accessibility ordering and the full installed-app F5/ESC/inline-close/Retry/paste-or-copy matrix still require trusted native GUI evidence.
