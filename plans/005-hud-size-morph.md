# 005 — HUD pill size morph on state change

- **Status**: TODO
- **Commit**: c4f9052
- **Severity**: MEDIUM
- **Category**: Missed opportunity / Physicality
- **Estimated scope**: 1 file (OverlayController.swift), 1 helper method, ~10 lines

## Problem

`OverlayController.swift:344` — `apply(state:)` calls `positionPanel(size:)` which calls `panel.setFrame(_:display:)` with no animation. The HUD pill snaps between two distinct sizes:

- Normal pill: `284 × 44 pt` (recording / processing / success)
- Error pill: `320 × 56 pt` (error / retryable error)

```swift
// OverlayController.swift:774–785 — current positionPanel
private func positionPanel(size: NSSize) {
    let screen = activeScreen() ?? NSScreen.main
    let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    panel.setFrame(                         // ← instant snap
        Self.panelFrame(
            for: size,
            in: visibleFrame,
            topInset: style.topInset
        ),
        display: false
    )
}
```

When a transcription error occurs, the pill jolts wider and taller in a single frame. The error message teleports into existence. This is jarring at a moment when the user is already reacting to a failure.

## Target

Replace the direct `setFrame` call with an animated `setFrame` via `NSAnimationContext` when the panel is already visible. Use `easeOut` at 0.22s — fast enough to not feel slow, smooth enough to register as intentional:

```swift
// Target — new animateToFrame helper
private func animateToFrame(_ newFrame: NSRect) {
    guard panel.isVisible else {
        panel.setFrame(newFrame, display: false)
        return
    }
    guard !resolvedAccessibilityDisplayOptions().reduceMotion else {
        panel.setFrame(newFrame, display: false)
        return
    }
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.22
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        panel.animator().setFrame(newFrame, display: true)
    }
}
```

Replace the `panel.setFrame(...)` call in `positionPanel(size:)` with `animateToFrame(...)`:

```swift
// Target — positionPanel
private func positionPanel(size: NSSize) {
    let screen = activeScreen() ?? NSScreen.main
    let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let newFrame = Self.panelFrame(
        for: size,
        in: visibleFrame,
        topInset: style.topInset
    )
    animateToFrame(newFrame)
}
```

## Repo conventions to follow

- `NSAnimationContext` pattern: `OverlayController.swift:472–476` (appear) and `500–504` (dismiss) — exact same structure.
- Easing: `CAMediaTimingFunction(name: .easeOut)` — already used for the appear path.
- Reduced motion guard: `resolvedAccessibilityDisplayOptions().reduceMotion` — already used in `present()` at line 466 and `scheduleHide` at line 495.

## Steps

1. **Add `animateToFrame(_:)` private method** to `OverlayController` — insert it after `positionPanel(size:)` (~line 786):
   ```swift
   private func animateToFrame(_ newFrame: NSRect) {
       guard panel.isVisible else {
           panel.setFrame(newFrame, display: false)
           return
       }
       guard !resolvedAccessibilityDisplayOptions().reduceMotion else {
           panel.setFrame(newFrame, display: false)
           return
       }
       NSAnimationContext.runAnimationGroup { context in
           context.duration = 0.22
           context.timingFunction = CAMediaTimingFunction(name: .easeOut)
           panel.animator().setFrame(newFrame, display: true)
       }
   }
   ```

2. **Update `positionPanel(size:)`** (~line 774–785): Replace `panel.setFrame(Self.panelFrame(...), display: false)` with:
   ```swift
   let newFrame = Self.panelFrame(for: size, in: visibleFrame, topInset: style.topInset)
   animateToFrame(newFrame)
   ```

## Boundaries

- Do NOT modify `panelFrame(for:in:topInset:)` — it stays a pure pure function.
- Do NOT animate the initial `present()` call's frame setup — only size *changes* while the panel is already visible should animate.
- Do NOT change any size values in `OverlayStylePreset.dictationHUD`.

## Verification

- **Mechanical**: `swift build` must succeed with zero errors.
- **Feel check**:
  - Trigger a dictation and simulate an error (or use debug mode to force `.error` state). The pill should smoothly widen and deepen from `284×44` to `320×56` over ~0.22s, staying centered horizontally throughout.
  - Trigger success after an error — pill should contract back smoothly.
  - Enable Reduce Motion → trigger error. Pill should snap to the larger size with no animation.
  - Position should remain centered on screen at all times during the size change.
- **Done when**: State transitions between normal and error pill sizes animate smoothly at ~0.22s easeOut, with instant fallback under reduced motion.
