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
→ pasted | copied | retryableFailure | terminalFailure
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
  - renders recording, processing, pasted, copied, error, and retryable-error HUD states.
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
  - currently loads the complete audio file into memory before building multipart data.
- `DictationPipeline`
  - sequences ASR, terminology normalization, optional polish, and final normalization.
- `TranscriptionPromptBuilder`
  - creates the fixed direct-output prompt and exact preservation hints.
- `TerminologyNormalizer`
  - applies deterministic terminology alignment.
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
- `ManagedEndpointPolicy`
  - fixes managed transcription and responses endpoints to approved `https://chatgpt.com` paths;
  - rejects credentials, query strings, fragments, non-HTTPS schemes, and unapproved ports;
  - validates user-owned endpoints separately.
- `SecureHTTPClient`
  - uses an ephemeral session and rejects HTTP redirects.

Managed credentials and user-owned API credentials are separate trust domains. The advanced OpenAI-compatible endpoint never receives the managed ChatGPT token.

## 5. Safe Output and Retry

`TextInjector` first writes the final text to the pasteboard, then selects one of:

- `.keyPressPaste` when Accessibility is trusted and a current editable target is confirmed;
- `.clipboardFallback(.accessibilityPermissionRequired)`;
- `.clipboardFallback(.noEditableTarget)`;
- `.clipboardFallback(.retryRequiresManualPaste)`.

The original clipboard is restored only when the pasteboard change count still proves OpenWhisper owns the current contents. Retry output intentionally remains in the clipboard.

Current limitation: `.pasted` means OpenWhisper sent the paste key event after its checks; it does not prove that the destination application accepted and inserted the text. The target-wait loop also still uses a short synchronous sleep on the main actor and must be moved to cancellable async coordination.

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

`StorageCleanupService.deleteAllData()` validates the application-support boundary, refuses symbolic-link deletion, removes the complete local data root, recreates a secure empty directory, signs out of ChatGPT, and saves a fresh default configuration.

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
- advanced recovery configuration.

History and Terminology now use separate native management windows. History supports filtering, details, copy/retry, audio actions, deletion, and automatic refresh. Terminology uses stable entry identifiers and supports search, sorting, editing, enable/disable, deletion, CSV import/export, import conflict preview, and a global Quick Add panel.

Privacy controls currently use the existing explicit Save flow. Remaining productization work includes a native resizable `NavigationSplitView` with immediate persistence plus full keyboard/VoiceOver coverage across Settings and the management windows.

## 9. Benchmarking and Diagnostics

- `LatencyRecorder` rewrites a bounded JSONL sample set using the configured retention policy.
- `scripts/benchmark_stt.sh` runs explicit audio inputs through packaged-app benchmark mode.
- Benchmark output includes cold/warm `auth_ms`, `transcribe_ms`, and `total_ms` p50/p95 summaries.
- Product diagnostics are local-only in the current alpha; no product analytics upload is enabled.

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

Ad-hoc signing is allowed only for local development. Commercial distribution still requires strict environment parsing, a fixed Developer ID/Team ID, Hardened Runtime, notarization and stapling, fail-closed Gatekeeper checks, staged atomic installation with rollback, fixed artifact SHA-256 values, and a signed updater.

## 11. Known Architectural Gaps

The current alpha must not be described as commercially release-ready while these remain:

- complete audio is read into memory before the 25 MB upload limit is evaluated;
- paste success is event-dispatch success, not destination insertion confirmation;
- target waiting blocks the main actor briefly;
- Settings and Onboarding are not yet at the target native product architecture; History, Terminology, and Quick Add still require full keyboard/VoiceOver interaction acceptance;
- HUD Reduce Motion, Increase Contrast, and VoiceOver state announcements are incomplete;
- the advanced recovery API key is still environment-variable based rather than Keychain-backed;
- notarization, updater, crash diagnostics export, and rollback-safe release infrastructure are not complete.
