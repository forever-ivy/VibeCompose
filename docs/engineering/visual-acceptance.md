# VibeWhisper Visual Acceptance

Use this chain for VibeWhisper HUD or interaction-facing visual work after unit/integration tests pass.

## Required Command

```sh
./scripts/visual_acceptance.sh --install
```

The command packages the current build, installs it to `/Applications/VibeWhisper.app`, and launches one installed-app demo process per HUD state through LaunchServices with `--overlay-demo-state`.

After the Refined HUD image matrix passes, the same command runs
`scripts/feedback_mode_acceptance.sh`. That installed-app harness verifies
Refined HUD, AI Activity Glow, and Hidden through explicit
`--visual-feedback-mode` launches, records machine-readable visibility and
Escape-cancellation state, captures AI Activity Glow evidence, and proves that
Reduce Motion disables the continuous AI Activity Glow scan.

Each demo process renders its own HUD content to a local temporary PNG path supplied through `--visual-acceptance-output`; the script then copies that artifact into the repository evidence directory. Using a local temporary path avoids removable-volume privacy prompts when the repository is under `/Volumes`. This primary path does not require Screen Recording permission and works in clean CI or Codex environments. If self-rendering does not produce a file, the script falls back to CoreGraphics window discovery plus `screencapture -l`, then runs the screenshot verifier.

The harness explicitly forces Reduce Motion and Increase Contrast off for the
baseline states so the result does not depend on the current user's system
settings. It then launches two deterministic accessibility profiles:

- Reduce Motion writes processing snapshots at two different times. The first
  must visibly differ from the animated baseline and the pair must remain
  pixel-stable.
- Increase Contrast writes a retryable-error snapshot. It must visibly differ
  from the baseline while preserving the exact window geometry.

Normal app launches continue to read live
`NSWorkspace.accessibilityDisplayShouldReduceMotion` and
`accessibilityDisplayShouldIncreaseContrast`; the override arguments exist
only to make installed-app acceptance deterministic.

## Product management surfaces

The minimum-size bilingual Settings matrix is captured with:

```bash
./scripts/settings_bilingual_acceptance.sh --install
```

It records General, Appearance & Feedback, AI Polish, and Terminology &
Context at `900 × 625` in Simplified Chinese and English. The snapshot-only
language argument runs under privacy isolation; the user-facing language
switch remains exclusively in Settings → General.

History, Terminology, Quick Add, the searchable Skill Switcher, and the
Community Skills Library use a separate installed-app acceptance harness:

```bash
VIBEWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/product_surface_acceptance.sh --install
```

The harness opens each surface through LaunchServices, writes its snapshot to a
local temporary path from inside the installed app, verifies image geometry and
visual variation, copies the evidence under
`dist/product-surface-acceptance/`, including the Switcher plus both Discover
and Created Library sections, and finally relaunches the normal menu bar app. CoreGraphics captures
that are technically valid but visually uniform
(including intermittent all-black frames) are rejected. The app then falls
back to deterministic content-view rendering, which must also pass the
non-uniform-image guard before evidence is accepted.

## Accessibility structure precheck

Run the installed-app SwiftUI accessibility audit with:

```bash
VIBEWHISPER_ALLOW_ADHOC_SIGNING=1 ./scripts/accessibility_acceptance.sh --install
```

It covers General, Account, Dictation, Appearance & Feedback, AI Polish,
Terminology & Context, Privacy, Advanced, all four Onboarding steps, History,
Terminology, Quick Add, Skill Switcher, and Skill Library Discover/Created. Each transient
process uses default configuration and empty in-memory user data, enables AppKit's
enhanced accessibility tree, and fails if the surface has no actionable
controls or an actionable element has no usable accessible name.

The generated JSON is structural evidence only. It does not prove Tab order,
keyboard activation, VoiceOver speech output, focus timing, system permission
dialogs, or high-contrast appearance; those remain official Computer Use
interaction requirements.

All automated HUD, product-surface, accessibility, permission, and paste
acceptance launch modes are classified as privacy-isolated before account
managers are created. They therefore use default configuration and in-memory
credentials instead of reading the user's Keychain. This both protects user
state and prevents acceptance startup from blocking in
`SecItemCopyMatching`.

## Installed permission surface precheck

When macOS shows Microphone and Accessibility as enabled but VibeWhisper appears
stale, run:

```bash
VIBEWHISPER_ALLOW_ADHOC_SIGNING=1 \
  ./scripts/permission_surface_acceptance.sh --install
```

The harness launches `/Applications/VibeWhisper.app` through LaunchServices,
opens Settings → Account in privacy-isolated snapshot mode, and uses Vision OCR
to require both the Microphone and Accessibility cards to render as
`Granted`/`已授权`. The process reads live TCC state but does not load the user's
account credentials, configuration, History, Recovery, or terminology data.
It also does not read local Writing Styles or installed Community Skills.
Evidence is written under `dist/permission-surface-acceptance/<run-id>/`, and
the normal installed menu bar app is relaunched and left running.

This closes the deterministic installed-surface check only. It does not replace
clean-TCC prompt ordering, changing permissions in System Settings, or
VoiceOver/keyboard interaction acceptance.

Launch a privacy-isolated installed surface for those interaction checks with:

```bash
VIBEWHISPER_ALLOW_ADHOC_SIGNING=1 \
  ./scripts/interaction_acceptance.sh --install settings account
```

Replace `settings account` with another supported Settings pane, Onboarding
step, History, Terminology, or Quick Add. The process uses default presentation
data and does not persist changes or Onboarding completion. When the Computer
Use pass is complete, restore the normal installed runtime with:

```bash
./scripts/interaction_acceptance.sh --restore
```

The script intentionally stops each transient overlay-demo process between HUD states. That cleanup is not the final user-review state. A successful run must relaunch the normal installed app from `/Applications/VibeWhisper.app`, verify that VibeWhisper is running, and leave it running.

## Evidence

Each run writes a timestamped directory under:

```text
dist/visual-acceptance/<run-id>
```

The directory must contain HUD-window screenshots:

- `01-recording.png`
- `02-processing.png`
- `03-result.png`
- `04-paste-sent.png`
- `05-copied.png`
- `06-error.png`
- `07-retryable-error.png`
- `08-processing-reduced-motion.png`
- `09-processing-reduced-motion-followup.png`
- `10-retryable-error-increase-contrast.png`
- `verification.txt`
- `summary.md`

## Closeout Rule

For VibeWhisper UI closeouts, report:

- the visual acceptance artifact directory
- whether `verification.txt` passed
- the installed-app live flow used for interaction acceptance
- the observed paste-versus-clipboard result when transcription/injection behavior was touched
- the normal installed VibeWhisper runtime state left for user review

The scripted visual run does not replace Computer Use interaction acceptance. It proves the installed build can render the expected HUD states and retry affordance without relying on full-screen screenshots, foreground browser state, or guessed screen bands. Do not finish a VibeWhisper GUI closeout by quitting or killing the app; if a script performs internal demo cleanup, relaunch `/Applications/VibeWhisper.app` before reporting completion.
