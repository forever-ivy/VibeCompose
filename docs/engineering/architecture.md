# OpenWhisper Architecture

## Overview

`OpenWhisper` is a native macOS menu bar app with a narrow workflow:

1. User presses `F5`
2. App starts recording and shows a compact HUD
3. User presses `F5` again
4. App validates OpenWhisper-managed ChatGPT session availability
5. Audio is sent to the ChatGPT backend transcription path
6. Result text is normalized, optionally polished, normalized again, then pasted or copied

The V1 architecture deliberately optimizes for a single-app workflow where OpenWhisper signs into ChatGPT directly and keeps its own local session.

## Runtime Components

- `AppCoordinator`
  - owns hotkey, recording, transcription, setup-state refresh, and insertion
- `HotkeyMonitor`
  - registers the global `F5` shortcut
- `AudioRecorder`
  - records mono WAV clips for short dictation
- `ChatGPTAuthManager`
  - owns OpenWhisper-managed ChatGPT session state, refresh, sign-out, and local token access
- `ChatGPTSessionStore`
  - persists OpenWhisper-owned session material in macOS Keychain
- `ChatGPTTranscriber`
  - calls the private ChatGPT backend transcription route with `Authorization: Bearer <token>`
  - measures `auth_ms` and `transcribe_ms`
  - applies a fixed prompt where supported
- `RuntimePreflight`
  - checks OpenWhisper-managed ChatGPT login state, token availability, and any advanced recovery misconfiguration
- `TranscriptionPromptBuilder`
  - builds the fixed “directly usable text” prompt and optional hidden hint terms
- `TerminologyNormalizer`
  - applies deterministic terminology alignment before and after optional text polish
- `TerminologyTextImporter`
  - imports plain text or CSV terminology dictionaries into OpenWhisper-owned entries
- `OpenAICompatibleTextPolisher`
  - runs the optional post-ASR rewrite pass through OpenWhisper-managed ChatGPT Auth
  - calls the configured ChatGPT backend Responses endpoint with a ChatGPT access token
- `LatencyRecorder`
  - appends per-dictation JSONL metrics under `~/Library/Application Support/OpenWhisper/latency.jsonl`
- `TextInjector`
  - pastes only when an editable target exists; otherwise leaves text in the clipboard
- `DictationPipeline`
  - orchestrates transcription, deterministic normalization, optional text polish, and final normalization through testable seams
- `OverlayController`
  - renders the floating HUD
- `PreferencesWindowController`
  - shows the workflow-sidebar Settings surface for account, dictation, AI polish, terminology, paste, and advanced recovery settings

## Provider Strategy

Two transcription routes exist:

- `chatGPTManagedAuth`
  - default V1 route
  - recommended for launch
  - uses a OpenWhisper-managed ChatGPT session
  - does not require an API key in the normal flow
- `openAICompatible`
  - advanced recovery route
  - not part of default onboarding
  - requires user-provided endpoint, model, and API key env var

Text polish is separate from ASR. It can use:

- OpenWhisper-managed ChatGPT Auth
- the configured ChatGPT backend Responses endpoint and model
- no separate text-polish provider API key
- a fail-open fallback that must never block usable ASR output

## Output Strategy

`OpenWhisper` treats ASR and text polish as separate stages so long dictation can be rewritten without changing the paste/injection layer.

Behavior:

- OpenAI-compatible recovery sends a fixed prompt through the official transcriptions API
- the ChatGPT account route tries the same prompt and retries without it if the private route rejects the field
- optional manual text or CSV imports become OpenWhisper-owned canonical terminology entries
- imported terminology is aligned by a deterministic local normalizer before and after optional text polish
- optional text polish removes filler words, prefers later corrections, and uses plan-like structure for long agent-facing dictation
- hidden `transcription.hintTerms` remain exact-only preservation hints
- if text polish has no available provider or fails, OpenWhisper falls back to the deterministic normalized transcript

## Benchmarking

- `scripts/benchmark_stt.sh` runs the packaged app in headless benchmark mode
- benchmark mode prints per-file `cold` and `warm` summaries with `auth_ms`, `transcribe_ms`, and `total_ms` p50/p95 values
- benchmark input audio files are supplied explicitly through the script arguments

## Visual Acceptance

- `scripts/visual_acceptance.sh --install` packages, installs, and launches `/Applications/OpenWhisper.app` in overlay demo mode through LaunchServices
- overlay demo mode is enabled with `OPENWHISPER_OVERLAY_DEMO=1` or the `--overlay-demo` launch argument
- the script launches one installed-app demo process per state, discovers the OpenWhisper HUD window with CoreGraphics, and captures that window with `screencapture -l`
- `scripts/verify_visual_acceptance.swift` verifies that each HUD-window screenshot has visible content and that adjacent states are visually distinct
- generated evidence is stored under `dist/visual-acceptance/<run-id>`

## Packaging

- `product.env` is the shell-facing source of truth for product identity
- `Sources/OpenWhisper/ProductIdentity.swift` is the runtime identity source of truth
- `version.env` is the single source of truth for version metadata
- `scripts/package_app.sh` builds `dist/OpenWhisper.app`
- `scripts/install_app.sh` installs the packaged app to `/Applications/OpenWhisper.app`
- `scripts/package_app.sh` also creates `dist/OpenWhisper-<version>-macos-<arch>.zip`
- `scripts/package_app.sh` also creates `dist/OpenWhisper-<version>-macos-<arch>.dmg`
- `scripts/install_launch_agent.sh` installs `app.openwhisper.mac`
- Homebrew Cask metadata is stored under `packaging/homebrew/Casks/openwhisper.rb`
