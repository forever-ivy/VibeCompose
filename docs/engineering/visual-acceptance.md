# OpenWhisper Visual Acceptance

Use this chain for OpenWhisper HUD or interaction-facing visual work after unit/integration tests pass.

## Required Command

```sh
./scripts/visual_acceptance.sh --install
```

The command packages the current build, installs it to `/Applications/OpenWhisper.app`, and launches one installed-app demo process per HUD state through LaunchServices with `OPENWHISPER_OVERLAY_DEMO=1` and `--overlay-demo-state`.

Each demo process renders its own HUD content to a local temporary PNG path supplied through `--visual-acceptance-output`; the script then copies that artifact into the repository evidence directory. Using a local temporary path avoids removable-volume privacy prompts when the repository is under `/Volumes`. This primary path does not require Screen Recording permission and works in clean CI or Codex environments. If self-rendering does not produce a file, the script falls back to CoreGraphics window discovery plus `screencapture -l`, then runs the screenshot verifier.

## Product management surfaces

History, Terminology, and Quick Add use a separate installed-app acceptance harness:

```bash
OPENWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/product_surface_acceptance.sh --install
```

The harness opens each surface through LaunchServices, writes its snapshot to a local temporary path from inside the installed app, verifies image geometry and visual variation, copies the evidence under `dist/product-surface-acceptance/`, and finally relaunches the normal menu bar app.

The script intentionally stops each transient overlay-demo process between HUD states. That cleanup is not the final user-review state. A successful run must relaunch the normal installed app from `/Applications/OpenWhisper.app`, verify that OpenWhisper is running, and leave it running.

## Evidence

Each run writes a timestamped directory under:

```text
dist/visual-acceptance/<run-id>
```

The directory must contain HUD-window screenshots:

- `01-recording.png`
- `02-processing.png`
- `03-result.png`
- `04-error.png`
- `05-retryable-error.png`
- `verification.txt`
- `summary.md`

## Closeout Rule

For OpenWhisper UI closeouts, report:

- the visual acceptance artifact directory
- whether `verification.txt` passed
- the installed-app live flow used for interaction acceptance
- the observed paste-versus-clipboard result when transcription/injection behavior was touched
- the normal installed OpenWhisper runtime state left for user review

The scripted visual run does not replace Computer Use interaction acceptance. It proves the installed build can render the expected HUD states and retry affordance without relying on full-screen screenshots, foreground browser state, or guessed screen bands. Do not finish a OpenWhisper GUI closeout by quitting or killing the app; if a script performs internal demo cleanup, relaunch `/Applications/OpenWhisper.app` before reporting completion.
