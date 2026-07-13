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

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
