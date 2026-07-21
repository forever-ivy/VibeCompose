# 004 — Skill Switcher panel entrance animation

- **Status**: TODO
- **Commit**: c4f9052
- **Severity**: MEDIUM
- **Category**: Physicality & origin / Missed opportunity
- **Estimated scope**: 1 file (SkillSwitcherWindowController.swift), ~15 lines

## Problem

`SkillSwitcherWindowController.swift:50–52` — The `show()` method calls `window.orderFrontRegardless()` with no entrance animation. The panel appears fully-rendered in a single frame with no spatial context.

```swift
// SkillSwitcherWindowController.swift:50–52 — current
func show() {
    guard let window else { return }
    centerOnActiveScreen()
    window.orderFrontRegardless()           // ← instant appearance
    NSApp.activate(ignoringOtherApps: true)
}
```

The panel is a dark glass floating surface (`.hudWindow` material, `NSPanel` with `.borderless`). A tool-palette of this kind should enter with a subtle scale from `0.96 → 1.0` paired with `opacity 0 → 1`, scaled from the top-center (where it appears relative to the menu bar trigger above). This tells the user spatially where the panel came from.

## Target

Use the same `NSAnimationContext` + `alphaValue` pattern already established in `OverlayController.swift` for the HUD pill, combined with a SwiftUI entrance `scaleEffect` driven by an `@State var appeared` bool inside `SkillSwitcherView`.

**AppKit layer (window alpha):**
```swift
// SkillSwitcherWindowController.swift — target show()
func show() {
    guard let window else { return }
    centerOnActiveScreen()
    window.alphaValue = 0
    window.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.22
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        window.animator().alphaValue = 1
    }
}
```

**SwiftUI layer (scale from top-center):**
Add `@State private var appeared = false` to `SkillSwitcherView`. On `.onAppear`, animate to `appeared = true`. Apply:
```swift
// SkillSwitcherView root container — add these modifiers
.scaleEffect(appeared ? 1.0 : 0.96, anchor: .top)
.animation(.spring(response: 0.28, dampingFraction: 0.88), value: appeared)
.onAppear {
    appeared = true
}
```

`anchor: .top` makes the panel grow from its top edge toward the bottom — correctly implying it dropped from the menu bar above.

**Dismiss**: The existing `window.orderOut(nil)` is fine — a snap dismiss on a floating tool palette is appropriate (the user explicitly chose to dismiss it). No exit animation needed.

**Reduced-motion**: Gate the scale in `SkillSwitcherView` with `@Environment(\.accessibilityReduceMotion)`:
```swift
.scaleEffect(appeared ? 1.0 : (reduceMotion ? 1.0 : 0.96), anchor: .top)
```
The alpha animation in the window controller is already skipped naturally if the window appears at alpha 1 when reduce-motion preference disables AppKit animations — but for clarity, wrap with the same check the overlay controller uses (`resolvedAccessibilityDisplayOptions().reduceMotion`).

## Repo conventions to follow

- Appear/disappear alpha pattern: `OverlayController.swift:462–480` — exact same `NSAnimationContext` + `alphaValue` approach.
- Spring token: `spring(response: 0.32, dampingFraction: 0.86)` in `PreferencesWindowController.swift:834`. Use slightly snappier `(response: 0.28, dampingFraction: 0.88)` — tool palettes should feel lighter than settings page transitions.
- `@State var appeared` SwiftUI pattern for entrance: common pattern in the codebase — consistent with how overlays use state to trigger presentation.

## Steps

1. **`SkillSwitcherWindowController.show()`** (~line 47–52): Add `window.alphaValue = 0` before `orderFrontRegardless()`, then add the `NSAnimationContext` block after `NSApp.activate(...)`.

2. **`SkillSwitcherView`** — Add `@State private var appeared = false` to the view's state block.

3. **Root container of `SkillSwitcherView`** — locate the outermost `VStack` or container that wraps the full panel content. Add:
   ```swift
   .scaleEffect(appeared ? 1.0 : 0.96, anchor: .top)
   .animation(.spring(response: 0.28, dampingFraction: 0.88), value: appeared)
   .onAppear { appeared = true }
   ```

4. **Add reduced-motion guard**: In `SkillSwitcherView`, add `@Environment(\.accessibilityReduceMotion) private var reduceMotion`. Change the scale line to:
   ```swift
   .scaleEffect(appeared ? 1.0 : (reduceMotion ? 1.0 : 0.96), anchor: .top)
   ```

## Boundaries

- Do NOT add an exit/dismiss animation.
- Do NOT modify the panel size, position logic, or `centerOnActiveScreen()`.
- Do NOT touch keyboard handling (`performKeyEquivalent`, ESC handler).
- Do NOT touch skill row logic, selection state, or any non-presentation code.

## Verification

- **Mechanical**: `swift build` must succeed with zero errors.
- **Feel check**:
  - Open the Skill Switcher via the menu bar or hotkey. The panel should appear to drop from the top edge — growing from ~96% to 100% of its size over ~0.28s, simultaneously fading from invisible.
  - The entrance should feel like a tool dropping into position, not a window spawning from nowhere.
  - Trigger the switcher multiple times rapidly — each appearance should start fresh (no residual scale state from a previous open).
  - Enable Reduce Motion → open switcher. Panel should appear with alpha fade only, no scale movement.
- **Done when**: Panel entrance has a visible but brief scale-from-top animation on every open.
