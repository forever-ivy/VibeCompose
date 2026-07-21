# 001 — Onboarding step content transition

- **Status**: TODO
- **Commit**: c4f9052
- **Severity**: HIGH
- **Category**: Missed opportunity / Physicality
- **Estimated scope**: 1 file (OnboardingWindowController.swift), ~10 lines

## Problem

`OnboardingWindowController.swift:508–525` — The `Continue` and `Back` buttons mutate `step` as a bare state assignment with no animation context. The `@ViewBuilder switch step` content area has no `.id()` modifier and no `.transition()`, so SwiftUI replaces the content with a hard cut every time the step changes.

```swift
// OnboardingWindowController.swift:519–525 — current
Button(L10n.text("Continue")) {
    message = nil
    onStepCompleted(step)
    step = OnboardingStep(rawValue: step.rawValue + 1) ?? .practice  // ← bare mutation
}
```

The result: pressing Continue teleports the user to the next step with zero spatial context. There is no indication of direction or progress.

## Target

Wrap both `step` mutations in `withAnimation` using the project's established spring. Add `.id(step)` to force a transition on each step change, and attach an asymmetric transition: forward motion slides right-in / left-out, backward motion reverses.

```swift
// Target — navigationBar Continue action
Button(L10n.text("Continue")) {
    message = nil
    onStepCompleted(step)
    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
        step = OnboardingStep(rawValue: step.rawValue + 1) ?? .practice
    }
}

// Target — navigationBar Back action
Button(L10n.text("Back")) {
    message = nil
    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
        step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
    }
}
```

Add `.id(step)` on the `stepContent` call site and a directional transition driven by a `@State var stepDirection`:

```swift
// In OnboardingView — add state
@State private var stepForward = true

// stepContent in the ScrollView — add .id + .transition
stepContent
    .id(step)
    .transition(stepForward
        ? .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 28, y: 0)),
            removal:   .opacity.combined(with: .offset(x: -16, y: 0))
          )
        : .asymmetric(
            insertion: .opacity.combined(with: .offset(x: -28, y: 0)),
            removal:   .opacity.combined(with: .offset(x: 16, y: 0))
          )
    )
    .padding(.horizontal, 36)
    .padding(.vertical, 32)
    .frame(maxWidth: 560, alignment: .topLeading)
    .frame(maxWidth: .infinity, alignment: .top)
```

Set `stepForward = true` before Continue, `stepForward = false` before Back (must happen before the `withAnimation` block so the transition direction is already set).

**Reduced-motion fallback** — query `@Environment(\.accessibilityReduceMotion)` in `OnboardingView`. If true, use `.opacity` transition only (no offset) and a plain `easeOut(duration: 0.15)` instead of spring.

## Repo conventions to follow

- Spring token: `spring(response: 0.32, dampingFraction: 0.86)` — already used in `PreferencesWindowController.swift:834`
- Transition pattern: `.opacity.combined(with: .scale(scale: 0.995))` in `PreferencesWindowController.swift:1002` — same combinator pattern, just uses offset instead of scale here
- Accessibility: `applyingAccessibilityDisplayOptionsOverride` is applied at the hosting controller level; inside SwiftUI, check `@Environment(\.accessibilityReduceMotion)` directly

## Steps

1. **Add `stepForward` state** to `OnboardingView` (line ~207 in the `@State` block):
   ```swift
   @State private var stepForward = true
   ```

2. **Wrap Continue mutation** — find the Continue button action (~line 519–525) and replace bare `step = ...` with:
   ```swift
   stepForward = true
   withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
       step = OnboardingStep(rawValue: step.rawValue + 1) ?? .practice
   }
   ```

3. **Wrap Back mutation** — find the Back button action (~line 507–511) and replace:
   ```swift
   stepForward = false
   withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
       step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
   }
   ```

4. **Add `.id(step)` and `.transition()`** — locate the `stepContent` call inside the ScrollView (~line 250–255) and add:
   ```swift
   stepContent
       .id(step)
       .transition(stepForward
           ? .asymmetric(
               insertion: .opacity.combined(with: .offset(x: 28, y: 0)),
               removal:   .opacity.combined(with: .offset(x: -16, y: 0))
             )
           : .asymmetric(
               insertion: .opacity.combined(with: .offset(x: -28, y: 0)),
               removal:   .opacity.combined(with: .offset(x: 16, y: 0))
             )
       )
   ```

5. **Add reduced-motion check** — at the top of `OnboardingView.body`, read `@Environment(\.accessibilityReduceMotion) private var reduceMotion`. In step 2 and 3, conditionally use `withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.86))`.

## Boundaries

- Do NOT touch any layout, spacing, or color code.
- Do NOT modify the window controller, window size, or hostingController setup.
- Do NOT add new dependencies.
- Only modify `OnboardingWindowController.swift`.
- If the line numbers have drifted from commit `c4f9052`, match by code context — do not guess.

## Verification

- **Mechanical**: `swift build` from project root must succeed with zero errors.
- **Feel check**:
  - Click Continue — content slides left-out while new content slides in from the right. The transition duration should feel snappy (~0.3s settle), not floaty.
  - Click Back — direction reverses: new content enters from the left.
  - Spam Continue repeatedly — each press interrupts the previous transition cleanly; no stacking or freezing.
  - Enable "Reduce Motion" in System Settings → Accessibility → Display → Reduce Motion. Click Continue — content should fade without any offset movement.
- **Done when**: All 4 step changes (Welcome→Connect, Connect→Mic, Mic→Practice, and all reverses) show directional crossfades, and the reduced-motion path shows opacity-only.
