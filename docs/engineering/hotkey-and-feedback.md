# VibeCompose Hotkey and Feedback Architecture

## Scope

This document describes the implemented Phase 1 interaction foundation for the
AI-native input-layer plan:

- one configurable global dictation shortcut, default `F5`;
- atomic registration, persistence, rollback, and startup fallback;
- dynamic shortcut copy across runtime product surfaces;
- Refined HUD, AI Activity Glow, and Hidden feedback modes;
- installed-app visual and accessibility acceptance.

The shortcut still has one invariant: the same binding starts and stops a
dictation. `Esc` remains reserved for cancellation, and Quick Add continues to
use `⌃⌥Space`.

## Hotkey Data and Validation

`HotkeyBinding` stores:

```text
keyCode: UInt32
modifiers: UInt32
```

Only Carbon Command, Shift, Option, and Control bits survive normalization.
Unmodified function keys are allowed. Letters, numbers, punctuation, and
navigation keys require Control, Option, or Command. VibeCompose rejects:

- `Esc`;
- the fixed Quick Add binding;
- unstable key codes;
- common macOS and editing combinations;
- bindings Carbon reports as already occupied.

Legacy `hotkeyKeyCode` configuration decodes into `dictationHotkey`. Invalid or
damaged values fall back to `F5`, and the next encode writes only the new model.

## Atomic Registration

`HotkeyRegistrationService` owns the active `HotkeyMonitor`.

Changing a binding follows this order:

1. normalize and validate the candidate;
2. register a candidate monitor while the old monitor remains alive;
3. persist the complete configuration atomically;
4. replace the active monitor only after persistence succeeds.

If registration or persistence fails, the previous monitor and saved binding
remain active. At startup, an unavailable custom binding falls back to `F5`.
If `F5` is also unavailable, menu-based start/stop remains available and
Settings explains how to choose another binding.

While the native shortcut recorder has keyboard focus, VibeCompose suspends the
current global monitor so the existing shortcut cannot accidentally trigger a
dictation. It restores the same binding before testing a captured candidate.

## Dynamic Product Copy

The active binding is injected into:

- Onboarding welcome, microphone, and practice steps;
- Settings headings, permission guidance, and Dictation controls;
- History empty state;
- menu start/stop action;
- ready and recording status;
- Refined HUD recording copy;
- VoiceOver announcements.

`Restore F5` is intentionally literal because it names the reset action rather
than the current runtime shortcut.

## Shared Feedback State

`FeedbackSurfaceController` is the presentation router. `AppCoordinator`
continues to emit one semantic state:

```text
recording(level, elapsed)
processing
inserted
paste sent
copied
error
retryable error
hidden
```

The router sends that state to one of three presentations:

### Refined HUD

- default mode;
- compact graphite capsule at the top center of the active display;
- stable recording, processing, and completion geometry;
- timer and inline cancel control for recording;
- inline cancel during processing;
- explicit Inserted, Paste Sent, Copied, Error, and Retry states;
- ordinary errors remain visible for at least five seconds.

### AI Activity Glow

- nonactivating and mouse-transparent;
- freezes the active display or focused-window target when the session starts;
- combines a restrained core stroke, ambient shadow, and fixed multi-stop energy gradient,
  not a screen capture or blurred overlay;
- recording uses a slow blue/ice/cyan breath; stopping keeps the same panel
  continuously visible and crossfades into a distinct indigo/blue/cyan
  processing state with three animated ambient layers and a `0.95 s` half-cycle;
- success has a green pulse, clipboard fallback an amber pulse, and error a
  red double pulse;
- completion and error states retain compact text when configured, so Copied
  and Inserted are not distinguished by color alone;
- system Reduce Motion or `alwaysReduceMotion` disables continuous breathing.

### Hidden

- creates no visible feedback surface;
- keeps menu state, optional sounds, optional completion notifications, error
  notifications, VoiceOver announcements, and `Esc` cancellation;
- exposes Retry through the menu when retry audio is available.

## Settings

Settings → Appearance & Feedback persists:

- visual mode;
- intensity;
- AI Activity Glow frame target;
- explanatory status text;
- feedback sounds;
- completion notifications;
- always-reduce-motion override.

The page can preview Recording, Processing, Copied, and Error without reading
audio, history, credentials, or user text.

## Acceptance

Automated prechecks:

```bash
./scripts/check.sh
```

Installed Refined HUD and all-mode feedback acceptance:

```bash
./scripts/visual_acceptance.sh --install
```

The second command:

1. packages and installs `/Applications/VibeCompose.app`;
2. captures the complete Refined HUD state matrix;
3. runs Refined HUD, AI Activity Glow, and Hidden mode assertions;
4. verifies explicit Reduce Motion behavior;
5. relaunches the normal installed app and leaves it running.

Native Computer Use remains required for the real custom-binding restart path,
keyboard focus, external keyboard behavior, full-screen/Spaces/Stage Manager,
VoiceOver speech, and live `Esc`/inline-close/Retry interaction.
