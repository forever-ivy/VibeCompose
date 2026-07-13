# OpenWhisper Runbook

## Repo Scope

- Owner/escalation: the OpenWhisper product owner for product behavior, installed app state, and release copy.
- This repo owns the native macOS dictation app `OpenWhisper`, packaged output under `dist/`, and the installed app path `/Applications/OpenWhisper.app`.
- The live app path is authoritative for permission and interaction verification; `dist/OpenWhisper.app` is packaging output only.

## Canonical Commands

- Local harness: `scripts/build_and_run.sh`
- Test/check harness: `scripts/check.sh`
- Package app: `scripts/package_app.sh`
- Install packaged app: `scripts/install_app.sh`
- Visual acceptance: `./scripts/visual_acceptance.sh --install`
- Installed TextEdit paste precheck: `./scripts/paste_acceptance.sh --install`
- Installed app smoke: `scripts/check_packaged_app.sh`

## Routine Operations

| Trigger | Command | Expected Result | Failure Recovery |
| --- | --- | --- | --- |
| Implement app behavior fix | `scripts/check.sh` | Unit/integration checks pass | Fix the first failing test; keep paste/permission regressions covered |
| Ship usable local build | `scripts/package_app.sh` then `scripts/install_app.sh` | Fresh `dist/OpenWhisper.app` is installed to `/Applications/OpenWhisper.app` | Rebuild and reinstall; never launch directly from `dist` for live verification |
| Run visual acceptance | `./scripts/visual_acceptance.sh --install` | Installed app launches through LaunchServices in overlay demo mode and captures recording/processing/verified-insert/paste-sent/copied/error/retryable-error evidence | Inspect generated artifact directory, fix the HUD/state mismatch, and rerun |
| Verify installed TextEdit insertion | `./scripts/paste_acceptance.sh --install` | Installed app launches an isolated TextEdit process, records `inserted_verified`, observes the marker, and restores the previous clipboard only after verification | If Accessibility is false, re-add the newly signed `/Applications/OpenWhisper.app`; do not treat an old signing identity's TCC row as proof |
| Verify first-run permissions | Reset TCC for installed app path, then launch `/Applications/OpenWhisper.app` | System permission prompt fires from `not determined` state | Do not let setup preflights request permissions before the first-run path is observed |

## Troubleshooting

| Trigger | Command | Expected Result | Failure Recovery |
| --- | --- | --- | --- |
| Output pastes into the wrong place | Inspect focused editable target and run the installed app path | Text sends paste only to the same focused editable target; verified insertion, unverified paste dispatch, and clipboard-only fallback remain distinct | Keep paste behavior conservative and debug AX target/value/range verification before changing STT cleanup |
| HUD or hotkey interaction changed | Use official Computer Use on the installed app | The configured shortcut (default `F5`) starts/stops, `ESC` cancels, inline close cancels, retry/re-entry works, and all three feedback modes preserve the same state semantics | Fix source, rebuild, reinstall, and rerun the full interaction branch |
| Permission flow regresses | Clean TCC state and installed app launch | Accessibility/Microphone prompts appear in the expected order | Add or update automated ordering tests, then repeat installed-app proof |

## Verification

- Verification ladder: unit tests, integration tests, then real installed-app user-flow testing. The first two are prechecks only.
- For native GUI work, use official Computer Use whenever clicks, hotkeys, focus, timing, modal state, permissions, or multi-step interaction are touched.
- OpenWhisper Computer Use acceptance should cover: focus a real editable target, start and stop with the configured shortcut (including default `F5` and one custom binding), cancel with `ESC`, cancel with inline close in Refined HUD, retry after cancel/error, switch Refined HUD / Blue Signal Frame / Hidden, and observe paste-versus-clipboard result.
- For closeouts, report the installed-app user flow exercised, the live verification path, the exact outcome observed, and the live OpenWhisper state left for review.
- After build, install, scripted visual acceptance, or interaction acceptance, relaunch `/Applications/OpenWhisper.app` as the normal installed app and leave it running. General ship closeouts should leave the menu bar app running; Settings or Terminologies work should leave that window visible when practical.

## Release/Deploy

- "Ship it" means run the canonical harness, build, install to `/Applications/OpenWhisper.app`, validate installed behavior, and keep release-facing docs current.
- After any fix reaches test/acceptance green, reinstall the freshly built app, launch `/Applications/OpenWhisper.app`, verify OpenWhisper is still running, and leave it running before reporting completion.
- Launch copy should describe the real public path: browser-based ChatGPT connection, `F5` to record, transcription, and paste-versus-clipboard fallback.

## Guardrails

- Preserve the single-trigger workflow: the configured shortcut starts recording and the same shortcut stops recording; new and reset configurations default to `F5`.
- Do not run `OpenWhisper.app` directly from `dist`.
- Do not end an OpenWhisper closeout with `pkill -x OpenWhisper`, quit, or close. `scripts/install_app.sh` may stop the old app before replacing `/Applications/OpenWhisper.app`, and visual demo scripts may stop transient overlay-demo processes, but final closeout must restore the normal installed runtime.
- Keep `.notDetermined` permission paths as their own regression surface.
- Keep the private ChatGPT backend dependency explicit in docs and UX; do not describe it as a stable public API.
- Keep `OpenAI-Compatible` positioned as advanced recovery, not the default public story.

## Known State

- `dist/OpenWhisper.app` is build output only.
- `/Applications/OpenWhisper.app` is the app path for launch, permission, LaunchAgent, and user-flow proof.

## Browser Automation Constraint
- Follow the global `~/.codex/AGENTS.md` official browser/GUI policy: Browser plugin for unauthenticated local/public rendering, Chrome plugin for signed-in/default-profile browser state, and Computer Use only for native desktop boundaries.
- Keep only repo-specific verification surfaces here; do not copy the full global policy block into this runbook.
