import Foundation
import Testing

@Test
func visualAcceptanceScriptRunsInstalledOpenWhisperOverlayDemo() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let scriptURL = root.appendingPathComponent("scripts/visual_acceptance.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)

    #expect(script.contains("source \"$ROOT/scripts/lib/load_env.sh\""))
    #expect(script.contains("load_product_env \"$ROOT/product.env\""))
    #expect(script.contains("APP_DIR=\"/Applications/$APP_NAME.app\""))
    #expect(script.contains("--visual-acceptance-output"))
    #expect(script.contains("--args"))
    #expect(script.contains("--overlay-demo-state"))
    #expect(script.contains("--visual-acceptance-reduce-motion"))
    #expect(script.contains("--visual-acceptance-increase-contrast"))
    #expect(script.contains("--visual-acceptance-followup-output"))
    #expect(script.contains("08-processing-reduced-motion.png"))
    #expect(script.contains("09-processing-reduced-motion-followup.png"))
    #expect(script.contains("10-retryable-error-increase-contrast.png"))
    #expect(script.contains("find_visual_acceptance_window.swift"))
    #expect(script.contains("screencapture -x -l"))
    #expect(script.contains("verify_visual_acceptance.swift"))
    #expect(!script.contains("sleep 0.8"))
    #expect(!script.contains("00-before.png"))
    #expect(!script.contains("dist/OpenWhisper.app/Contents/MacOS/OpenWhisper"))
}

@Test
func visualAcceptanceWindowDiscoveryUsesCoreGraphicsWindowList() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let scriptURL = root.appendingPathComponent("scripts/find_visual_acceptance_window.swift")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)

    #expect(script.contains("CGWindowListCopyWindowInfo"))
    #expect(script.contains("kCGWindowOwnerName"))
    #expect(script.contains("kCGWindowNumber"))
    #expect(script.contains("kCGWindowBounds"))
}

@Test
func visualAcceptanceVerifierDocumentsRequiredStates() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let verifierURL = root.appendingPathComponent("scripts/verify_visual_acceptance.swift")
    let verifier = try String(contentsOf: verifierURL, encoding: .utf8)

    for state in [
        "recording",
        "processing",
        "result",
        "paste-sent",
        "copied",
        "error",
        "retryable-error",
    ] {
        #expect(verifier.contains(state))
    }
    #expect(verifier.contains("visible HUD pixels"))
    #expect(verifier.contains("changed HUD-window pixels"))
    #expect(verifier.contains("distinct window size"))
    #expect(verifier.contains("unstablePrimaryGeometry"))
    #expect(verifier.contains("invalidErrorGeometry"))
    #expect(verifier.contains("unstableReducedMotion"))
    #expect(verifier.contains("insufficientAccessibilityDifference"))
    #expect(verifier.contains("reduced-motion-static"))
    #expect(verifier.contains("increase-contrast"))
    #expect(!verifier.contains("expected HUD band"))
}

@Test
func productSurfaceAcceptanceCoversInstalledManagementWindows() throws {
    let root = repositoryRoot()
    let script = try String(
        contentsOf: root.appendingPathComponent("scripts/product_surface_acceptance.sh"),
        encoding: .utf8
    )
    let verifier = try String(
        contentsOf: root.appendingPathComponent("scripts/verify_product_surfaces.swift"),
        encoding: .utf8
    )

    #expect(script.contains("/Applications/$APP_NAME.app"))
    #expect(script.contains(#"capture_surface "history" "history-snapshot-output""#))
    #expect(script.contains(#"capture_surface "terminology" "terminology-snapshot-output""#))
    #expect(script.contains(#"capture_surface "quick-add" "quick-add-snapshot-output""#))
    #expect(script.contains(#""--open-$launch_mode""#))
    #expect(script.contains("verify_product_surfaces.swift"))
    #expect(script.contains("/usr/bin/open \"$APP_DIR\""))
    #expect(verifier.contains("managerGeometryMismatch"))
    #expect(verifier.contains("sampledColorBucketCount"))
}

@Test
func accessibilityVisualAcceptanceCoversEveryPrimaryProductSurface() throws {
    let root = repositoryRoot()
    let script = try String(
        contentsOf: root.appendingPathComponent(
            "scripts/accessibility_visual_acceptance.sh"
        ),
        encoding: .utf8
    )
    let verifier = try String(
        contentsOf: root.appendingPathComponent(
            "scripts/verify_accessibility_visual_acceptance.swift"
        ),
        encoding: .utf8
    )

    #expect(script.contains("/Applications/$APP_NAME.app"))
    #expect(script.contains("--visual-acceptance-increase-contrast"))
    #expect(script.contains("--visual-acceptance-reduce-motion=off"))
    #expect(script.contains(#""--settings-pane=$detail_value""#))
    #expect(script.contains(#""--onboarding-step=$detail_value""#))
    #expect(script.contains("verify_accessibility_visual_acceptance.swift"))
    #expect(script.contains("/usr/bin/open \"$APP_DIR\""))
    for surface in [
        "settings-account",
        "settings-dictation",
        "settings-ai-polish",
        "settings-paste",
        "settings-privacy",
        "settings-advanced",
        "onboarding-welcome",
        "onboarding-connect",
        "onboarding-microphone",
        "onboarding-practice",
        "history",
        "terminology",
        "quick-add",
    ] {
        #expect(script.contains(surface))
        #expect(verifier.contains(surface))
    }
    #expect(verifier.contains("changed pixels"))
    #expect(verifier.contains("local edge contrast"))
    #expect(verifier.contains("luminance spread diagnostic"))
    #expect(verifier.contains("normalizedBackingScale"))
    #expect(verifier.contains("geometryMismatch"))
    #expect(verifier.contains("weakerEdgeContrast"))
    #expect(!verifier.contains("non-decreasing luminance spread"))
}

@Test
func primarySwiftUIWindowsApplyAccessibilityDisplayOptions() throws {
    let root = repositoryRoot()
    for source in [
        "PreferencesWindowController.swift",
        "OnboardingWindowController.swift",
        "HistoryWindowController.swift",
        "TerminologyWindowController.swift",
        "TerminologyQuickAddWindowController.swift",
        "MicrophonePermissionWindowController.swift",
    ] {
        let content = try String(
            contentsOf: root
                .appendingPathComponent("Sources/OpenWhisper")
                .appendingPathComponent(source),
            encoding: .utf8
        )
        #expect(
            content.contains(
                "applyingAccessibilityDisplayOptionsOverride"
            )
        )
        #expect(content.contains("applyAppearance(to: window)"))
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
