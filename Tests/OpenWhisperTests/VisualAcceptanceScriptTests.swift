import Foundation
import Testing

@Test
func windowActivationAcceptanceUsesTheInstalledAppAndNativeMinimize()
    throws
{
    let root = repositoryRoot()
    let script = try String(
        contentsOf: root.appendingPathComponent(
            "scripts/window_activation_acceptance.sh"
        ),
        encoding: .utf8
    )
    let verifier = try String(
        contentsOf: root.appendingPathComponent(
            "scripts/verify_window_activation.swift"
        ),
        encoding: .utf8
    )

    #expect(script.contains("/Applications/$APP_NAME.app"))
    #expect(script.contains("--open-settings"))
    #expect(script.contains("verify_window_activation.swift"))
    #expect(verifier.contains("kAXMinimizeButtonAttribute"))
    #expect(verifier.contains("kAXMinimizedAttribute"))
    #expect(verifier.contains("activationPolicy == .regular"))
    #expect(verifier.contains("initialPolicy == .regular"))
    #expect(verifier.contains("runningApplication.icon != nil"))
}

@Test
func feedbackModeAcceptanceCoversAllThreeInstalledSurfaces()
    throws
{
    let root = URL(
        fileURLWithPath:
            FileManager.default
                .currentDirectoryPath
    )
    let source = try String(
        contentsOf:
            root.appendingPathComponent(
                "scripts/feedback_mode_acceptance.sh"
            ),
        encoding: .utf8
    )

    #expect(
        source.contains(
            "/Applications/$APP_NAME.app"
        )
    )
    #expect(
        source.contains(
            "--feedback-surface-debug-output"
        )
    )
    #expect(source.contains("refined-hud"))
    #expect(source.contains("ai-activity-glow"))
    #expect(source.contains("\"hidden\""))
    #expect(
        source.contains(
            "aiActivityGlowAnimationIsActive"
        )
    )
}

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
    #expect(script.contains("--preview-demo"))
    #expect(script.contains("--preview-snapshot-output"))
    #expect(script.contains("11-diff-preview.png"))
    #expect(script.contains("--visual-acceptance-followup-output"))
    #expect(script.contains("08-processing-reduced-motion.png"))
    #expect(script.contains("09-processing-reduced-motion-followup.png"))
    #expect(script.contains("10-retryable-error-increase-contrast.png"))
    #expect(script.contains("find_visual_acceptance_window.swift"))
    #expect(script.contains("screencapture -x -l"))
    #expect(script.contains("verify_visual_acceptance.swift"))
    #expect(
        script.contains(
            "feedback_mode_acceptance.sh"
        )
    )
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
    #expect(!verifier.contains("invalidErrorGeometry"))
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
    #expect(script.contains(#"capture_surface "skill-library" "skill-library-snapshot-output""#))
    #expect(script.contains(#"capture_surface "skill-switcher" "skill-switcher-snapshot-output""#))
    #expect(script.contains("skill-library-section"))
    #expect(script.contains("04-skill-library-installed.png"))
    #expect(script.contains(#""--open-$launch_mode""#))
    #expect(script.contains("verify_product_surfaces.swift"))
    #expect(script.contains("/usr/bin/open \"$APP_DIR\""))
    #expect(verifier.contains("managerGeometryMismatch"))
    #expect(verifier.contains("skill-library-discover"))
    #expect(verifier.contains("skill-library-installed"))
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
        "settings-general",
        "settings-account",
        "settings-dictation",
        "settings-appearance",
        "settings-ai-polish",
        "settings-context",
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
    #expect(verifier.contains("compositedForVisualAcceptance"))
    #expect(!verifier.contains("non-decreasing luminance spread"))
}

@Test
func permissionSurfaceAcceptanceChecksInstalledLivePermissionCards() throws {
    let root = repositoryRoot()
    let script = try String(
        contentsOf: root.appendingPathComponent(
            "scripts/permission_surface_acceptance.sh"
        ),
        encoding: .utf8
    )
    let verifier = try String(
        contentsOf: root.appendingPathComponent(
            "scripts/verify_permission_surface.swift"
        ),
        encoding: .utf8
    )

    #expect(script.contains("/Applications/$APP_NAME.app"))
    #expect(script.contains("--settings-pane=account"))
    #expect(script.contains("--settings-snapshot-output"))
    #expect(script.contains("verify_permission_surface.swift"))
    #expect(script.contains("/usr/bin/open \"$APP_DIR\""))
    #expect(!script.contains("dist/OpenWhisper.app/Contents/MacOS/OpenWhisper"))

    #expect(verifier.contains("VNRecognizeTextRequest"))
    #expect(verifier.contains("\"Microphone\", \"麦克风\""))
    #expect(verifier.contains("\"Accessibility\", \"辅助功能\""))
    #expect(verifier.contains("\"Granted\", \"已授权\""))
    #expect(verifier.contains("containsCJKSequence"))
    #expect(verifier.contains("grantedStatusCount >= 2"))
}

@Test
func bilingualSettingsAcceptanceUsesInstalledMinimumSizeSnapshots() throws {
    let script = try String(
        contentsOf: repositoryRoot().appendingPathComponent(
            "scripts/settings_bilingual_acceptance.sh"
        ),
        encoding: .utf8
    )
    #expect(script.contains("/Applications/$APP_NAME.app"))
    #expect(script.contains("sizes=(900x620 980x680 1180x760)"))
    #expect(script.contains("\"--settings-snapshot-size=$size\""))
    #expect(script.contains("--settings-snapshot-language=$language"))
    #expect(script.contains("panes=(general dictation context appearance advanced)"))
    #expect(script.contains("/usr/bin/open \"$APP_DIR\""))
    #expect(!script.contains("dist/OpenWhisper.app/Contents/MacOS"))
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
        "SkillLibraryWindowController.swift",
        "SkillSwitcherWindowController.swift",
        "PreviewRuntime.swift",
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
        if source == "PreferencesWindowController.swift" {
            #expect(
                !content.contains(
                    "applyingOpenWhisperBrandTint"
                )
            )
        } else {
            #expect(
                content.contains(
                    "applyingOpenWhisperBrandTint"
                )
            )
        }
        #expect(content.contains("applyAppearance(to: window)"))
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
