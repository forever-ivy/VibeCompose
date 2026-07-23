# 002 — Button press scale feedback

- **Status**: TODO
- **Commit**: c4f9052
- **Severity**: HIGH
- **Category**: Physicality & origin
- **Estimated scope**: 1 file (VibeWhisperVisualSystem.swift), 3 button styles, ~6 lines

## Problem

`VibeWhisperVisualSystem.swift:509–590` — All three button styles (`VibeWhisperPrimaryButtonStyle`, `VibeWhisperSecondaryButtonStyle`, `VibeWhisperQuietButtonStyle`) handle press state with opacity changes only. No `scaleEffect` is applied on press. Per the audit standard: pressable elements must give tactile feedback via `scale(0.97)` with `transition: transform 160ms ease-out`.

```swift
// VibeWhisperVisualSystem.swift:554–556 — current Primary
.background(
    Color(nsColor: VibeWhisperPalette.brandBlue)
        .opacity(isEnabled ? (configuration.isPressed ? 0.76 : 1) : 0.38),
    // ← no scaleEffect on isPressed
```

```swift
// VibeWhisperVisualSystem.swift:537–538 — current Secondary
.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.68)
// ← no scaleEffect on isPressed
```

The result: pressing any CTA button gives only a mild brightness dip. The interface doesn't confirm the press with physical presence — it feels soft and unresponsive compared to native macOS controls.

## Target

Add `.scaleEffect` driven by `configuration.isPressed` to all three styles, using an `.animation` modifier so SwiftUI drives the spring from the current value (interruptible):

```swift
// Target — Primary, Secondary, Quiet (scale differs slightly)
.scaleEffect(configuration.isPressed ? 0.97 : 1.0)
.animation(.spring(response: 0.2, dampingFraction: 0.85), value: configuration.isPressed)
```

Scale values by style:
- `VibeWhisperPrimaryButtonStyle`: `0.97` (most tactile — it's the main CTA)
- `VibeWhisperSecondaryButtonStyle`: `0.975` (slightly subtler)
- `VibeWhisperQuietButtonStyle`: `0.98` (near-invisible — quiet style should stay quiet)

Keep all existing opacity behavior. Add scale on top, don't replace opacity.

**Reduced-motion**: SwiftUI's `.animation(_:value:)` modifier on macOS 14+ automatically reduces or removes animation when the system "Reduce Motion" setting is on. No extra branching needed for scale — the spring duration collapses. If targeting macOS 13, add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` in the style struct and use `.animation(reduceMotion ? .linear(duration: 0) : .spring(...), value: ...)`.

## Repo conventions to follow

- Spring token already in use: `.spring(response: 0.32, dampingFraction: 0.86)` in `PreferencesWindowController.swift:834`. Use a slightly snappier variant `(response: 0.2, dampingFraction: 0.85)` for press feedback — 0.2 response = 200ms settle, matches the 160ms budget from STANDARDS.md (spring settles before the stated ms, effectively within budget).
- Pattern: all button styles already use `configuration.isPressed` as a branch condition — extend that condition, don't restructure the body.

## Steps

1. **`VibeWhisperPrimaryButtonStyle.makeBody`** (~line 544–563): Add after `.background(...)`:
   ```swift
   .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
   .animation(.spring(response: 0.2, dampingFraction: 0.85), value: configuration.isPressed)
   ```

2. **`VibeWhisperSecondaryButtonStyle.makeBody`** (~line 509–538): Add after the final `.opacity(...)`:
   ```swift
   .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
   .animation(.spring(response: 0.2, dampingFraction: 0.85), value: configuration.isPressed)
   ```

3. **`VibeWhisperQuietButtonStyle.makeBody`** (~line 566–587): Add after the final `.background(...)`:
   ```swift
   .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
   .animation(.spring(response: 0.2, dampingFraction: 0.85), value: configuration.isPressed)
   ```

## Boundaries

- Do NOT touch color, opacity, font, padding, or corner radius values.
- Do NOT touch `VibeWhisperIconWell`, `VibeWhisperStatusChip`, or any other component in the same file.
- Only the three `ButtonStyle` structs are in scope.
- Do NOT add new dependencies.

## Verification

- **Mechanical**: `swift build` must succeed with zero errors.
- **Feel check**:
  - Open Onboarding → click and hold "Continue". The button should compress to ~97% while held, and spring back on release. The motion should feel snappy, not floaty.
  - Click quickly (tap, not hold) — the scale feedback should complete in ~120ms, fast enough to feel like confirmation rather than decoration.
  - Open Settings → click any secondary button — compression is slightly less than primary (975 vs 970).
  - Spam-click a button — each press compresses and releases cleanly without stacking or hanging.
  - Enable System Settings → Accessibility → Display → Reduce Motion. Click a button — scale should be absent or near-zero; opacity feedback still present.
- **Done when**: All three button styles compress on press and spring back on release, with decreasing scale intensity from Primary → Secondary → Quiet.
