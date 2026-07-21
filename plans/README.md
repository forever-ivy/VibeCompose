# Animation Plans

Plans written by `improve-animations` audit — commit `c4f9052`.

## Status

| # | Title | Severity | Status | Depends on |
|---|---|---|---|---|
| 001 | Onboarding step content transition | HIGH | TODO | — |
| 002 | Button press scale feedback | HIGH | TODO | — |
| 003 | HUD pill dismiss: ease-in → ease-out | MEDIUM | TODO | — |
| 004 | Skill Switcher panel entrance animation | MEDIUM | TODO | — |
| 005 | HUD pill size morph on state change | MEDIUM | TODO | — |

## Recommended execution order

1. **003** — one-line change, zero risk, immediate feel improvement on every dictation
2. **002** — touches only `OpenWhisperVisualSystem.swift`, isolated, high daily visibility
3. **001** — most complex, requires `stepForward` state + transition wiring; do after 002 so you have a feel baseline
4. **004** — depends on understanding the SkillSwitcher panel structure; do after 001
5. **005** — AppKit `NSAnimationContext` frame animation; verify no layout side-effects last

## Audit findings summary (all 8 categories)

| # | Severity | Category | Finding |
|---|---|---|---|
| 1 | HIGH | Missed opportunity | Onboarding step content has no transition — bare `step =` mutation |
| 2 | HIGH | Physicality | All 3 button styles: opacity-only press, no `scaleEffect` |
| 3 | MEDIUM | Easing | HUD dismiss uses `CAMediaTimingFunction(.easeIn)` — starts slow |
| 4 | MEDIUM | Physicality | SkillSwitcher `show()` calls `orderFrontRegardless()` with no entrance |
| 5 | MEDIUM | Missed opportunity | HUD pill snaps between 284×44 and 320×56 on error state |
| 6 | LOW | Cohesion | No `OpenWhisperMotion` token system — spring/duration values duplicated across 5+ files |
| 7 | MEDIUM | Accessibility | SwiftUI `.animation()` transitions in `PreferencesWindowController` don't gate on `@Environment(\.accessibilityReduceMotion)` |
| 8 | MEDIUM | Missed opportunity | Onboarding step indicator icon/color change has no symbol transition |

## What was deliberately not planned

- **Dictation hotkey trigger**: keyboard-initiated, 100+/day — no animation, ever
- **Status bar icon**: system menu bar, no independent animation appropriate  
- **History list entries**: high-frequency information-dense list, animation hinders reading
- **Waveform bars**: already correctly animated via Timer + smoothed interpolation
- **Settings page transition**: already correct — `.opacity.combined(with: .scale(0.995))` at 0.18s easeOut
- **Settings sidebar spring**: already correct — `spring(response: 0.32, dampingFraction: 0.86)`
