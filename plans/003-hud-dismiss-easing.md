# 003 — HUD pill dismiss: replace ease-in with ease-out

- **Status**: TODO
- **Commit**: c4f9052
- **Severity**: MEDIUM
- **Category**: Easing & duration
- **Estimated scope**: 1 file (OverlayController.swift), 1 function, 2 lines

## Problem

`OverlayController.swift:500–504` — The `scheduleHide` function fades the HUD pill out using `CAMediaTimingFunction(name: .easeIn)`. Per the audit standard, `ease-in` on UI is always a finding: it starts slow, delaying the moment the user perceives the dismissal has begun, making the pill appear to linger longer than it actually does.

```swift
// OverlayController.swift:500–504 — current
NSAnimationContext.runAnimationGroup({ context in
    context.duration = 0.2
    context.timingFunction = CAMediaTimingFunction(name: .easeIn)  // ← finding
    panel.animator().alphaValue = 0
```

The appear animation correctly uses `.easeOut` (line 474), making the pill snap in immediately. The dismiss should match in responsiveness: start fading immediately, decelerate at the end.

## Target

Replace `CAMediaTimingFunction(name: .easeIn)` with `CAMediaTimingFunction(name: .easeOut)` in the dismiss path only.

```swift
// Target
NSAnimationContext.runAnimationGroup({ context in
    context.duration = 0.2
    context.timingFunction = CAMediaTimingFunction(name: .easeOut)  // ← fix
    panel.animator().alphaValue = 0
```

Duration stays at 0.2s — correct for a small utility panel.

## Repo conventions to follow

- Appear animation already uses `.easeOut` at 0.18s (`OverlayController.swift:473–474`) — this fix makes dismiss symmetric in curve, asymmetric only in duration (0.18 appear, 0.2 dismiss is fine — slightly longer dismiss is perceptually appropriate).

## Steps

1. In `OverlayController.swift`, locate `scheduleHide` function (~line 484). Find the `NSAnimationContext.runAnimationGroup` block (~line 500–504).
2. Change `CAMediaTimingFunction(name: .easeIn)` → `CAMediaTimingFunction(name: .easeOut)`.

That is the entire change — one token swap, one line.

## Boundaries

- Do NOT touch the appear path (`present()` function, line ~463–480).
- Do NOT touch the reduced-motion path (`self.hide()` direct call at line ~495–498).
- Do NOT touch duration values.

## Verification

- **Mechanical**: `swift build` must succeed with zero errors.
- **Feel check**:
  - Trigger a successful dictation (or use the debug snapshot to show `.success` state). Watch the pill auto-dismiss after ~0.9s. With the fix, the fade should start immediately and slow to a gentle end — it disappears quickly rather than lingering.
  - Compare: the old `ease-in` begins barely visible for ~80ms before accelerating. The new `ease-out` starts fading at full speed from frame one.
- **Done when**: The HUD dismiss starts fading immediately on the first rendered frame, matching the responsiveness of the appear.
