import AppKit
import AVFoundation
import SwiftUI

struct OnboardingStateStore {
    static let completionKey = "VibeCompose.Onboarding.CompletedFlowVersion"
    static let currentFlowVersion = 1

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func shouldPresent() -> Bool {
        defaults.integer(forKey: Self.completionKey) < Self.currentFlowVersion
    }

    func markCompleted() {
        defaults.set(Self.currentFlowVersion, forKey: Self.completionKey)
    }

    func markCompleted(if shouldPersist: Bool) {
        guard shouldPersist else {
            return
        }
        markCompleted()
    }
}

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let stateStore: OnboardingStateStore
    /// When true, the wizard cannot be dismissed until Finish Setup succeeds.
    private let blocksUntilCompleted: Bool
    private var didComplete = false
    private let onCompleted: () -> Void

    init(
        authManager: ChatGPTAuthManager,
        hotkeyBinding: HotkeyBinding = .f5,
        initialStep: OnboardingStep = .welcome,
        persistCompletion: Bool = true,
        blocksUntilCompleted: Bool = true,
        stateStore: OnboardingStateStore = OnboardingStateStore(),
        onRequestMicrophoneAccess: @escaping @MainActor @Sendable () async -> Result<Void, any Error>,
        onStepCompleted: @escaping (OnboardingStep) -> Void = { _ in },
        onCompleted: @escaping () -> Void
    ) {
        self.stateStore = stateStore
        self.blocksUntilCompleted = blocksUntilCompleted
        self.onCompleted = onCompleted
        let accessibilityDisplayOptionsOverride =
            AccessibilityDisplayOptionsOverride.currentVisualAcceptance

        let placeholder = OnboardingView(
            authManager: authManager,
            hotkeyBinding: hotkeyBinding,
            initialStep: initialStep,
            onRequestMicrophoneAccess: onRequestMicrophoneAccess,
            onStepCompleted: onStepCompleted,
            onComplete: {}
        )
        .applyingVibeComposeBrandTint()
        .applyingAccessibilityDisplayOptionsOverride(
            accessibilityDisplayOptionsOverride
        )
        // Use a hosting view that accepts first-mouse so every CTA fires on the
        // first press even when another app was key a moment earlier.
        let hostingView = OnboardingHostingView(rootView: placeholder)
        // Mandatory first-run: no close chrome. Snapshot/acceptance may allow close.
        var styleMask: NSWindow.StyleMask = [.titled, .miniaturizable]
        if !blocksUntilCompleted {
            styleMask.insert(.closable)
        }
        let window = OnboardingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.blocksDismissal = blocksUntilCompleted
        window.title = L10n.text("Set Up VibeCompose")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier("VibeCompose.OnboardingWindow")
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(width: 960, height: 640)
        window.contentMaxSize = NSSize(width: 960, height: 640)
        window.contentView = hostingView
        // Onboarding is a solid content wizard, not a floating glass shell.
        // Keep the plate opaque so materials and soft stage washes never sample
        // the desktop wallpaper (which produces grainy/speckle artifacts on
        // macOS 26 Liquid Glass / ultraThinMaterial).
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = false
        // Wizard must accept clicks on first press — never sit behind accessory
        // HUD panels as a non-key titled window.
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        accessibilityDisplayOptionsOverride.applyAppearance(to: window)

        super.init(window: window)
        window.delegate = self
        Self.centerOnActiveScreen(window)

        hostingView.rootView =
            OnboardingView(
                authManager: authManager,
                hotkeyBinding: hotkeyBinding,
                initialStep: initialStep,
                onRequestMicrophoneAccess: onRequestMicrophoneAccess,
                onStepCompleted: onStepCompleted,
                onComplete: { [weak self] in
                    self?.finishSetup(persistCompletion: persistCompletion)
                }
            )
            .applyingVibeComposeBrandTint()
            .applyingAccessibilityDisplayOptionsOverride(
                accessibilityDisplayOptionsOverride
            )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else {
            return
        }
        // Place on the screen under the cursor (or main), true visual center of
        // the visible frame — not NSWindow.center() which only uses the primary
        // display and can leave the wizard half off a secondary monitor.
        Self.centerOnActiveScreen(window)
        // Same activation path as MicrophonePermissionWindowController — first
        // click must reach every CTA (Get Started / Connect / Mic / Finish).
        NSRunningApplication.current.activate(
            options: [.activateAllWindows, .activateIgnoringOtherApps]
        )
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        // Launch races (menu bar / statusBar HUD) can steal key for a tick —
        // re-assert after the run loop so CTAs stay clickable.
        DispatchQueue.main.async { [weak window] in
            guard let window, window.isVisible else { return }
            Self.centerOnActiveScreen(window)
            NSRunningApplication.current.activate(
                options: [.activateAllWindows, .activateIgnoringOtherApps]
            )
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Centers the wizard on the screen that contains the mouse (fallback: main).
    private static func centerOnActiveScreen(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen =
            NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        var frame = window.frame
        // Keep the fixed 960×640 content size; only origin is computed.
        if frame.size.width < 1 || frame.size.height < 1 {
            frame.size = NSSize(width: 960, height: 640)
        }
        frame.origin = NSPoint(
            x: visible.midX - frame.size.width / 2,
            y: visible.midY - frame.size.height / 2
        )
        // Clamp so the full frame stays inside the visible area (menu bar / Dock).
        frame.origin.x = min(
            max(frame.origin.x, visible.minX),
            visible.maxX - frame.size.width
        )
        frame.origin.y = min(
            max(frame.origin.y, visible.minY),
            visible.maxY - frame.size.height
        )
        window.setFrame(frame, display: true)
    }

    func writeSnapshot(to url: URL) throws {
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.displayIfNeeded()
        try ProductSurfaceSnapshot.write(window: window, to: url)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if blocksUntilCompleted, !didComplete {
            // Keep the mandatory wizard up; bounce for feedback.
            NSSound.beep()
            show()
            return false
        }
        return true
    }

    private func finishSetup(persistCompletion: Bool) {
        didComplete = true
        if let onboardingWindow = window as? OnboardingWindow {
            onboardingWindow.blocksDismissal = false
        }
        stateStore.markCompleted(if: persistCompletion)
        window?.orderOut(nil)
        onCompleted()
    }
}

private final class OnboardingWindow: NSWindow {
    /// When true, Cmd-W / close path must not dismiss the wizard.
    var blocksDismissal = false

    /// Titled onboarding must always be able to become key so the solid CTAs
    /// receive the first mouse-down (not only window activation).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandW = event.type == .keyDown
            && modifiers.contains(.command)
            && event.charactersIgnoringModifiers?.lowercased() == "w"
        if isCommandW {
            if blocksDismissal {
                NSSound.beep()
                return true
            }
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Hosting view for the wizard. First mouse-down must reach SwiftUI buttons
/// even when VibeCompose was not the key app (menu-bar launch, HUD steal).
private final class OnboardingHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Never return nil for points inside the plate — nil would pass the
        // click through to windows underneath (statusBar HUD / desktop).
        super.hitTest(point) ?? self
    }
}

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case showcase
    case connect
    case microphone
    case practice

    var id: Int { rawValue }

    var launchArgumentValue: String {
        switch self {
        case .welcome:
            return "welcome"
        case .showcase:
            return "showcase"
        case .connect:
            return "connect"
        case .microphone:
            return "microphone"
        case .practice:
            return "practice"
        }
    }

    static func fromLaunchArgument(_ value: String) -> OnboardingStep? {
        switch value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        {
        case "welcome":
            return .welcome
        case "showcase", "skills", "modes", "features":
            return .showcase
        case "connect", "account":
            return .connect
        case "microphone", "mic":
            return .microphone
        case "practice", "paste", "paste-and-practice":
            return .practice
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .welcome:
            return L10n.text("Welcome")
        case .showcase:
            return L10n.text("Skills")
        case .connect:
            return L10n.text("Connect")
        case .microphone:
            return L10n.text("Microphone")
        case .practice:
            return L10n.text("Practice")
        }
    }

    var symbol: String {
        switch self {
        case .welcome:
            return "waveform"
        case .showcase:
            return "wand.and.stars"
        case .connect:
            return "person.crop.circle.badge.checkmark"
        case .microphone:
            return "mic"
        case .practice:
            return "text.cursor"
        }
    }
}

// MARK: - Root view

private struct OnboardingView: View {
    @State private var step: OnboardingStep
    @State private var authSnapshot: ChatGPTAuthSnapshot
    @StateObject private var permissionMonitor = PermissionStatusMonitor()
    @State private var isConnecting = false
    @State private var isRequestingMicrophone = false
    @State private var message: String?
    @State private var messageIsError = false
    @State private var practiceText = ""
    @State private var stepForward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let authManager: ChatGPTAuthManager
    let hotkeyBinding: HotkeyBinding
    let onRequestMicrophoneAccess:
        @MainActor @Sendable () async -> Result<Void, any Error>
    let onStepCompleted: (OnboardingStep) -> Void
    let onComplete: () -> Void

    init(
        authManager: ChatGPTAuthManager,
        hotkeyBinding: HotkeyBinding = .f5,
        initialStep: OnboardingStep = .welcome,
        onRequestMicrophoneAccess: @escaping @MainActor @Sendable () async -> Result<Void, any Error>,
        onStepCompleted: @escaping (OnboardingStep) -> Void = { _ in },
        onComplete: @escaping () -> Void
    ) {
        self.authManager = authManager
        self.hotkeyBinding = hotkeyBinding
        self.onRequestMicrophoneAccess = onRequestMicrophoneAccess
        self.onStepCompleted = onStepCompleted
        self.onComplete = onComplete
        _step = State(initialValue: initialStep)
        _authSnapshot = State(initialValue: authManager.authSnapshot())
    }

    var body: some View {
        // Typeless-inspired split wizard: light text progress, left copy,
        // right ambient stage. Content stays solid / opaque — no Liquid Glass
        // or ultraThinMaterial (they sample the desktop and grain on macOS 26).
        VStack(spacing: 0) {
            topProgress
            // Quiet hairline — keeps the wizard plate calm above the brand stage.
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
            HStack(spacing: 0) {
                leftColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                rightStage
                    .frame(width: 400)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 960, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(
            reduceMotion
                ? .easeOut(duration: VibeComposeMotion.quickFade)
                : VibeComposeMotion.stepSpring,
            value: step
        )
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            authSnapshot = authManager.authSnapshot()
            permissionMonitor.refresh()
            Task { @MainActor in
                _ = await permissionMonitor.refreshAccessibilityUntilTrusted(
                    maximumRefreshAttempts: 8,
                    refreshDelay: .milliseconds(200)
                )
            }
        }
    }

    private var stepTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        if stepForward {
            return .asymmetric(
                insertion: .opacity
                    .combined(with: .offset(x: 20, y: 0)),
                removal: .opacity
                    .combined(with: .offset(x: -12, y: 0))
            )
        }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .offset(x: -20, y: 0)),
            removal: .opacity
                .combined(with: .offset(x: 12, y: 0))
        )
    }

    // MARK: Top progress (light text trail)

    private var topProgress: some View {
        HStack(spacing: 0) {
            ForEach(Array(OnboardingStep.allCases.enumerated()), id: \.element.id) {
                index,
                item in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.28))
                        .padding(.horizontal, 10)
                }
                HStack(spacing: 5) {
                    if index < step.rawValue {
                        // Completed step — brand check so progress reads as earned.
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(
                                Color(nsColor: VibeComposePalette.brandBlue)
                            )
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text(item.title)
                        .font(
                            .system(
                                size: 12,
                                weight: index == step.rawValue ? .semibold : .regular
                            )
                        )
                        .foregroundStyle(
                            index == step.rawValue
                                ? Color.primary
                                : index < step.rawValue
                                    ? Color.primary.opacity(0.55)
                                    : Color.primary.opacity(0.38)
                        )
                }
                .overlay(alignment: .bottom) {
                    if index == step.rawValue {
                        Capsule(style: .continuous)
                            .fill(Color(nsColor: VibeComposePalette.brandBlue))
                            .frame(height: 2)
                            .offset(y: 10)
                            .transition(.opacity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.format(
                "Step %d of %d",
                step.rawValue + 1,
                OnboardingStep.allCases.count
            )
        )
    }

    // MARK: Left column

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if step != .welcome {
                Button {
                    goBack()
                } label: {
                    Label(L10n.text("Back"), systemImage: "chevron.left")
                        .font(VibeComposeTypography.callout(.medium))
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                        .contentShape(Rectangle())
                        .padding(.vertical, 4)
                        .padding(.trailing, 8)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .keyboardShortcut(.cancelAction)
                .padding(.bottom, VibeComposeMetrics.space20)
            }

            // Animated body stays in its own layer; footer CTAs are siblings
            // outside the transition so hit-testing never rides a moving view.
            stepMainContent
                .id(step)
                .transition(stepTransition)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()

            Spacer(minLength: VibeComposeMetrics.space16)

            statusMessage
                .padding(.bottom, VibeComposeMetrics.space12)

            // Solid brand CTAs — do not wrap in a glass effect container.
            // On macOS 26 that container can swallow hits when children
            // are not glass-effect views (Get Started / Continue become dead).
            primaryActions
        }
        .padding(.leading, 44)
        .padding(.trailing, 36)
        .padding(.top, 28)
        .padding(.bottom, 28)
        .background(Color(nsColor: .windowBackgroundColor))
        // Entire left plate is a solid hit region above the right stage.
        .contentShape(Rectangle())
        .zIndex(20)
    }

    @ViewBuilder
    private var stepMainContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .showcase:
            showcaseStep
        case .connect:
            connectStep
        case .microphone:
            microphoneStep
        case .practice:
            practiceStep
        }
    }

    // MARK: Right ambient stage

    private var rightStage: some View {
        ZStack {
            // Official Codex hero floral still (bundled asset). Solid fills /
            // image only — never materials (desktop sampling on macOS 26).
            OnboardingBrandWallpaper()

            rightStageCard
                .padding(28)
                .transition(stepTransition)
                .id("stage-\(step.rawValue)")
        }
        .clipped()
    }

    @ViewBuilder
    private var rightStageCard: some View {
        switch step {
        case .welcome:
            OnboardingProductDemo(hotkeyName: hotkeyBinding.displayName)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    L10n.format(
                        "Demo: press %@, speak, and text appears in the focused field.",
                        hotkeyBinding.displayName
                    )
                )
        case .showcase:
            OnboardingModeGallery()
        case .connect:
            onboardingInfoCard(
                items: [
                    (
                        "lock.shield",
                        L10n.text("Session stays on this Mac"),
                        L10n.text(
                            "VibeCompose stores its own ChatGPT session in Keychain."
                        )
                    ),
                    (
                        "safari",
                        L10n.text("Sign in once in your browser"),
                        L10n.text(
                            "A browser window opens. VibeCompose never sees your password."
                        )
                    ),
                    (
                        "sparkles",
                        L10n.text("Powers AI Polish Skills"),
                        L10n.text(
                            "Reply, Email, Translate, and other Skills use this connection."
                        )
                    ),
                ]
            )
        case .microphone:
            onboardingInfoCard(
                items: [
                    (
                        "mic.fill",
                        L10n.text("Used only while recording"),
                        L10n.text(
                            "Microphone access is required only while you record a dictation."
                        )
                    ),
                    (
                        "trash",
                        L10n.text("Recording is deleted after processing"),
                        L10n.text(
                            "Audio is removed after transcription finishes."
                        )
                    ),
                    (
                        "lock.fill",
                        L10n.text("You stay in control"),
                        L10n.text(
                            "Revoke access any time in System Settings."
                        )
                    ),
                ]
            )
        case .practice:
            practiceStageCard
        }
    }

    private var practiceStageCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(nsColor: VibeComposePalette.brandBlue))
                Text(L10n.text("Practice field"))
                    .font(VibeComposeTypography.caption(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    L10n.format(
                        "Press %@ to dictate",
                        hotkeyBinding.displayName
                    )
                )
                .font(VibeComposeTypography.micro(.medium))
                .foregroundStyle(Color(nsColor: VibeComposePalette.brandBlue))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.45)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $practiceText)
                    .font(VibeComposeTypography.body())
                    .padding(14)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel(L10n.text("Dictation practice field"))

                if practiceText.isEmpty {
                    Text(L10n.text("Your words appear here…"))
                        .font(VibeComposeTypography.body())
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 220, maxHeight: .infinity)
        }
        .background(
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusXL,
                style: .continuous
            )
            .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusXL,
                style: .continuous
            )
            .stroke(
                Color(nsColor: VibeComposePalette.atmosphereIndigo).opacity(0.14),
                lineWidth: 1
            )
        )
        .shadow(
            color: Color(nsColor: VibeComposePalette.atmosphereIndigo).opacity(0.12),
            radius: 24,
            x: 0,
            y: 12
        )
    }

    private func onboardingInfoCard(
        items: [(String, String, String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.0)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            Color(nsColor: VibeComposePalette.brandBlue)
                        )
                        .frame(width: 20, height: 20)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.1)
                            .font(VibeComposeTypography.headline())
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.2)
                            .font(VibeComposeTypography.callout())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusXL,
                style: .continuous
            )
            .fill(Color(nsColor: .textBackgroundColor).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusXL,
                style: .continuous
            )
            .stroke(
                Color(nsColor: VibeComposePalette.atmosphereIndigo).opacity(0.14),
                lineWidth: 1
            )
        )
        .shadow(
            color: Color(nsColor: VibeComposePalette.atmosphereIndigo).opacity(0.12),
            radius: 28,
            x: 0,
            y: 14
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Primary footer actions

    private var primaryActions: some View {
        HStack(spacing: VibeComposeMetrics.space12) {
            Spacer(minLength: 0)
            if step == .practice {
                Button(L10n.text("Finish Setup")) {
                    onStepCompleted(.practice)
                    onComplete()
                }
                .buttonStyle(VibeComposeOnboardingCTAButtonStyle())
                .keyboardShortcut(.defaultAction)
            } else if step == .connect {
                if authSnapshot.state == .ready {
                    // Connected: Continue is the single primary action;
                    // reconnect stays secondary so hierarchy is clear.
                    Button(
                        L10n.text(
                            isConnecting
                                ? "Waiting for Browser"
                                : "Connect in Browser"
                        )
                    ) {
                        connect()
                    }
                    .buttonStyle(VibeComposeOnboardingSecondaryButtonStyle())
                    .disabled(isConnecting)

                    Button(L10n.text("Continue")) {
                        goForward()
                    }
                    .buttonStyle(VibeComposeOnboardingCTAButtonStyle())
                    .keyboardShortcut(.defaultAction)
                } else {
                    // Allow leaving Connect without auth so setup is not a hard
                    // gate; Skills that need ChatGPT still prompt later.
                    Button(L10n.text("Skip for now")) {
                        goForward()
                    }
                    .buttonStyle(VibeComposeOnboardingSecondaryButtonStyle())
                    .disabled(isConnecting)

                    Button(
                        L10n.text(
                            isConnecting
                                ? "Waiting for Browser"
                                : "Connect in Browser"
                        )
                    ) {
                        connect()
                    }
                    .buttonStyle(VibeComposeOnboardingCTAButtonStyle())
                    .disabled(isConnecting)
                    .keyboardShortcut(.defaultAction)
                }
            } else if step == .microphone {
                Button(L10n.text("Enable Microphone")) {
                    requestMicrophone()
                }
                .buttonStyle(VibeComposeOnboardingCTAButtonStyle())
                .disabled(
                    isRequestingMicrophone
                        || permissionMonitor.snapshot.microphone == .granted
                )

                if permissionMonitor.snapshot.microphone == .denied {
                    Button(L10n.text("Open Microphone Settings")) {
                        _ = PermissionSettingsDestination.microphone.open()
                    }
                    .buttonStyle(VibeComposeOnboardingSecondaryButtonStyle())
                }

                if permissionMonitor.snapshot.microphone == .granted {
                    Button(L10n.text("Continue")) {
                        goForward()
                    }
                    .buttonStyle(VibeComposeOnboardingCTAButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            } else if step == .showcase {
                Button(L10n.text("Continue")) {
                    goForward()
                }
                .buttonStyle(VibeComposeOnboardingCTAButtonStyle())
                .keyboardShortcut(.defaultAction)
            } else {
                Button(L10n.text("Get Started")) {
                    goForward()
                }
                .buttonStyle(VibeComposeOnboardingCTAButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        // Fixed footer height so layout does not jump; solid hit plate.
        .frame(minHeight: 48, alignment: .center)
        .contentShape(Rectangle())
        // Keep the footer above any animated step content so CTA hit targets
        // never sit under a transitioning sibling layer.
        .zIndex(10)
    }

    private func goBack() {
        message = nil
        stepForward = false
        withAnimation(
            reduceMotion
                ? .easeOut(duration: VibeComposeMotion.quickFade)
                : VibeComposeMotion.stepSpring
        ) {
            step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
        }
    }

    private func goForward() {
        message = nil
        onStepCompleted(step)
        stepForward = true
        withAnimation(
            reduceMotion
                ? .easeOut(duration: VibeComposeMotion.quickFade)
                : VibeComposeMotion.stepSpring
        ) {
            step = OnboardingStep(rawValue: step.rawValue + 1) ?? .practice
        }
    }

    // MARK: Welcome

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: VibeComposeMetrics.space28) {
            stepTitle(
                title: "Speak anywhere on your Mac",
                subtitle: L10n.format(
                    "Press %@ to start, %@ again to finish.",
                    hotkeyBinding.displayName,
                    hotkeyBinding.displayName
                )
            )

            VStack(alignment: .leading, spacing: VibeComposeMetrics.space12) {
                permissionRow(
                    title: L10n.format(
                        "%@ starts and stops every session.",
                        hotkeyBinding.displayName
                    ),
                    isReady: true
                )
                permissionRow(
                    title: L10n.text(
                        "Terminology protects product names, commands, and paths."
                    ),
                    isReady: true
                )
                permissionRow(
                    title: L10n.text(
                        "Result goes to the focused field or stays in your clipboard."
                    ),
                    isReady: true
                )
            }
        }
    }

    // MARK: Skills showcase

    private var showcaseStep: some View {
        VStack(alignment: .leading, spacing: VibeComposeMetrics.space24) {
            stepTitle(
                title: "One voice, many results",
                subtitle: L10n.text(
                    "Skills reshape what you say to fit the moment — a clean note, a reply, an email, a task, a code prompt, a translation."
                )
            )

            VStack(alignment: .leading, spacing: VibeComposeMetrics.space12) {
                permissionRow(
                    title: L10n.text("Same hotkey, the right shape every time"),
                    detail: L10n.text(
                        "You always speak the same way. The active Skill decides how the text comes out."
                    ),
                    isReady: true
                )
                permissionRow(
                    title: L10n.text("Switches automatically per app"),
                    detail: L10n.text(
                        "Set a default Skill and per-app rules later in Settings."
                    ),
                    isReady: true
                )
            }
        }
    }

    // MARK: Connect

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: VibeComposeMetrics.space24) {
            stepTitle(
                title: "Connect your ChatGPT account",
                subtitle: L10n.text(
                    "VibeCompose stores its own session in Keychain on this Mac."
                )
            )

            permissionRow(
                title: authSnapshot.state == .ready
                    ? (
                        authSnapshot.userEmail.map {
                            L10n.format("Connected as %@", $0)
                        } ?? L10n.text("ChatGPT connected")
                    )
                    : L10n.text("ChatGPT connection required"),
                isReady: authSnapshot.state == .ready
            )

            Text(
                L10n.text(
                    "Default route uses your ChatGPT account. VibeCompose is independent from OpenAI; availability may change."
                )
            )
            .font(VibeComposeTypography.caption())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Microphone

    private var microphoneStep: some View {
        VStack(alignment: .leading, spacing: VibeComposeMetrics.space24) {
            stepTitle(
                title: "Allow microphone access",
                subtitle: L10n.text(
                    "Microphone access is required only while you record a dictation."
                )
            )

            permissionRow(
                title: microphoneStatusTitle,
                detail: microphoneStatusDetail,
                isReady: permissionMonitor.snapshot.microphone == .granted
            )

            // Match Preferences repair surface: explicit refresh when status is
            // still undetermined after a prompt (copy references this control).
            if permissionMonitor.snapshot.microphone != .granted {
                Button(L10n.text("Refresh Status")) {
                    permissionMonitor.refresh()
                }
                .buttonStyle(VibeComposeOnboardingSecondaryButtonStyle())
            }
        }
    }

    // MARK: Practice

    private var practiceStep: some View {
        VStack(alignment: .leading, spacing: VibeComposeMetrics.space24) {
            stepTitle(
                title: "Try your first dictation",
                subtitle: L10n.format(
                    "Click the practice field, press %@, speak, then press %@ again.",
                    hotkeyBinding.displayName,
                    hotkeyBinding.displayName
                )
            )

            permissionRow(
                title: permissionMonitor.snapshot.accessibilityTrusted
                    ? L10n.text("Automatic paste is ready")
                    : L10n.text("Clipboard Mode is ready"),
                detail: permissionMonitor.snapshot.accessibilityTrusted
                    ? L10n.text("Text lands directly in the focused field.")
                    : L10n.text(
                        "Transcript is copied to clipboard — press ⌘V to paste."
                    ),
                isReady: true
            )

            if !permissionMonitor.snapshot.accessibilityTrusted {
                Button(L10n.text("Enable Automatic Paste")) {
                    AccessibilityPermission.guideAccess()
                    Task { @MainActor in
                        _ = await permissionMonitor
                            .refreshAccessibilityUntilTrusted()
                    }
                }
                .buttonStyle(VibeComposeOnboardingSecondaryButtonStyle())
            }
        }
    }

    private var microphoneStatusTitle: String {
        switch permissionMonitor.snapshot.microphone {
        case .granted:
            return L10n.text("Microphone is ready")
        case .undetermined:
            return L10n.text("Microphone has not been requested")
        case .denied:
            return L10n.text("Microphone access is off")
        }
    }

    private var microphoneStatusDetail: String {
        switch permissionMonitor.snapshot.microphone {
        case .granted:
            return L10n.format(
                "You can record with %@.",
                hotkeyBinding.displayName
            )
        case .undetermined:
            return L10n.text("Click Enable Microphone to show the macOS permission prompt.")
        case .denied:
            return L10n.text("Turn on VibeCompose in System Settings > Privacy & Security > Microphone.")
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let message {
            Text(message)
                .font(VibeComposeTypography.caption())
                .foregroundStyle(messageIsError ? Color(nsColor: VibeComposePalette.error) : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Building blocks

    private func stepTitle(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: VibeComposeMetrics.space10) {
            Text(L10n.text(title))
                .font(.system(size: 32, weight: .bold, design: .default))
                .tracking(-0.7)
                .fixedSize(horizontal: false, vertical: true)
            // Subtitle may already be L10n.format(...) — display as-is.
            Text(subtitle)
                .font(VibeComposeTypography.body())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Soft pill row used for permissions / promises — Typeless-inspired.
    private func permissionRow(
        title: String,
        detail: String? = nil,
        isReady: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(VibeComposeTypography.body(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(VibeComposeTypography.callout())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Image(
                systemName: isReady
                    ? "checkmark.circle.fill"
                    : "circle"
            )
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(
                isReady
                    ? Color(nsColor: VibeComposePalette.brandBlue)
                    : Color.primary.opacity(0.22)
            )
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .fill(
                isReady
                    ? Color(nsColor: VibeComposePalette.brandBlue)
                        .opacity(0.055)
                    : Color.primary.opacity(0.04)
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .stroke(
                isReady
                    ? Color(nsColor: VibeComposePalette.brandBlue)
                        .opacity(0.10)
                    : Color.clear,
                lineWidth: 1
            )
        )
        .accessibilityElement(children: .combine)
    }

    private func connect() {
        isConnecting = true
        message = nil
        Task {
            do {
                _ = try await authManager.connectViaDefaultBrowser()
                await MainActor.run {
                    authSnapshot = authManager.authSnapshot()
                    isConnecting = false
                    message = L10n.text("ChatGPT connected. Continue to microphone access.")
                    messageIsError = false
                }
            } catch {
                await MainActor.run {
                    authSnapshot = authManager.authSnapshot()
                    isConnecting = false
                    message = error.localizedDescription
                    messageIsError = true
                }
            }
        }
    }

    private func requestMicrophone() {
        isRequestingMicrophone = true
        message = nil
        Task { @MainActor in
            let result = await permissionMonitor.requestMicrophoneAccess(
                using: onRequestMicrophoneAccess
            )
            isRequestingMicrophone = false
            switch result {
            case .success:
                switch permissionMonitor.snapshot.microphone {
                case .granted:
                    message = L10n.text("Microphone access is ready.")
                    messageIsError = false
                case .undetermined:
                    message = L10n.text(
                        "VibeCompose still cannot confirm microphone access. Click Refresh Status or reopen the app."
                    )
                    messageIsError = true
                case .denied:
                    message = microphoneStatusDetail
                    messageIsError = true
                }
            case .failure(let error):
                message = error.localizedDescription
                messageIsError = true
            }
        }
    }
}

// MARK: - Atmosphere wallpaper (right stage)

/// Right-stage ambient wallpaper: official Codex hero floral loop
/// (`floral_a.mp4` from openai.com/codex), muted + seamless loop.
/// Reduce Motion falls back to a still frame. No materials / glass.
private struct OnboardingBrandWallpaper: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                basePlate

                floralBackdrop(size: geo.size)

                // Soft center veil so the floating stage card stays legible.
                RadialGradient(
                    colors: [
                        Color.white.opacity(isDark ? 0.06 : 0.26),
                        Color.white.opacity(isDark ? 0.02 : 0.09),
                        Color.clear,
                    ],
                    center: UnitPoint(x: 0.48, y: 0.46),
                    startRadius: s * 0.04,
                    endRadius: s * 0.52
                )

                // Edge vignette — frames the stage and softens crop edges.
                RadialGradient(
                    colors: [
                        Color.clear,
                        Color(nsColor: VibeComposePalette.atmosphereDeep)
                            .opacity(isDark ? 0.30 : 0.11),
                    ],
                    center: .center,
                    startRadius: s * 0.36,
                    endRadius: s * 0.98
                )

                // Cool wash so brand-blue UI still rhymes with the floral field.
                LinearGradient(
                    colors: [
                        Color(nsColor: VibeComposePalette.atmosphereSky)
                            .opacity(isDark ? 0.10 : 0.05),
                        Color.clear,
                        Color(nsColor: VibeComposePalette.atmosphereLavender)
                            .opacity(isDark ? 0.12 : 0.07),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func floralBackdrop(size: CGSize) -> some View {
        let videoURL = Self.resourceURL(
            name: "OnboardingCodexWallpaper",
            ext: "mp4"
        )
        let stillImage = Self.loadStillImage()

        if !reduceMotion, let videoURL {
            OnboardingLoopingVideoView(url: videoURL)
                .frame(width: size.width, height: size.height)
                .opacity(isDark ? 0.90 : 1.0)
                .saturation(isDark ? 0.92 : 1.04)
                .brightness(isDark ? -0.05 : 0.0)
                .clipped()
                // Still underneath for first-frame before player is ready.
                .background {
                    if let stillImage {
                        Image(nsImage: stillImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size.width, height: size.height)
                            .clipped()
                    }
                }
        } else if let stillImage {
            Image(nsImage: stillImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .opacity(isDark ? 0.88 : 1.0)
                .clipped()
        } else {
            continuumFallback(size: min(size.width, size.height))
        }
    }

    private var basePlate: some View {
        Group {
            if isDark {
                Color(
                    nsColor: NSColor(
                        srgbRed: 0.06,
                        green: 0.06,
                        blue: 0.12,
                        alpha: 1
                    )
                )
            } else {
                Color(nsColor: VibeComposePalette.atmospherePlate)
            }
        }
    }

    @ViewBuilder
    private func continuumFallback(size s: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: VibeComposePalette.atmosphereSky).opacity(0.70),
                    Color(nsColor: VibeComposePalette.atmospherePeriwinkle)
                        .opacity(0.65),
                    Color(nsColor: VibeComposePalette.atmosphereIndigo)
                        .opacity(0.60),
                    Color(nsColor: VibeComposePalette.atmosphereLavender)
                        .opacity(0.55),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 28)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(nsColor: VibeComposePalette.atmosphereSky)
                                .opacity(0.65),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: s * 0.55
                    )
                )
                .frame(width: s * 1.2, height: s * 1.2)
                .blur(radius: 60)
                .offset(x: s * 0.2, y: -s * 0.25)
        }
    }

    private static func loadStillImage() -> NSImage? {
        if let url = resourceURL(name: "OnboardingCodexWallpaper", ext: "png"),
           let image = NSImage(contentsOf: url)
        {
            return image
        }
        return nil
    }

    private static func resourceURL(name: String, ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        let dev = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/VibeCompose/Resources/\(name).\(ext)"
            )
        if FileManager.default.fileExists(atPath: dev.path) {
            return dev
        }
        return nil
    }
}

// MARK: - Looping muted floral video (Codex hero)

/// AppKit-backed looping muted video for the onboarding stage.
/// Uses `AVPlayerLayer` (no AVKit chrome), seamless loop via end-time seek.
private struct OnboardingLoopingVideoView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> OnboardingLoopingVideoNSView {
        let view = OnboardingLoopingVideoNSView(frame: .zero)
        view.configure(url: url)
        return view
    }

    func updateNSView(_ nsView: OnboardingLoopingVideoNSView, context: Context) {
        nsView.configure(url: url)
    }

    static func dismantleNSView(
        _ nsView: OnboardingLoopingVideoNSView,
        coordinator: ()
    ) {
        nsView.tearDown()
    }
}

@MainActor
private final class OnboardingLoopingVideoNSView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var configuredURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func configure(url: URL) {
        guard configuredURL != url else {
            player?.play()
            return
        }
        tearDown()
        configuredURL = url

        let template = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        // AVPlayerLooper inserts seamless copies of the template.
        looper = AVPlayerLooper(player: queue, templateItem: template)
        player = queue
        playerLayer.player = queue
        queue.play()
    }

    func tearDown() {
        looper?.disableLooping()
        looper = nil
        player?.pause()
        player?.removeAllItems()
        player = nil
        playerLayer.player = nil
        configuredURL = nil
    }
}

// MARK: - Product demo theater (welcome)

/// Looping, pure-SwiftUI product theater: press hotkey → listen → text appears.
/// No video assets; reads as a live miniature of the real HUD + paste flow.
private struct OnboardingProductDemo: View {
    let hotkeyName: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .idle
    @State private var typedText = ""
    @State private var keyPressed = false
    @State private var pulse = false

    private enum Phase: Int, CaseIterable {
        case idle
        case press
        case listening
        case writing
        case done
    }

    private let sampleLine = "Ship the release notes by Friday."

    var body: some View {
        VStack(spacing: VibeComposeMetrics.space12) {
            HStack(spacing: VibeComposeMetrics.space8) {
                Label(
                    L10n.text("See it in action"),
                    systemImage: "play.circle.fill"
                )
                .font(VibeComposeTypography.caption(.semibold))
                .foregroundStyle(Color(nsColor: VibeComposePalette.brandBlue))
                Spacer()
                Text(phaseCaption)
                    .font(VibeComposeTypography.micro(.medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(
                        .easeOut(duration: VibeComposeMotion.quickFade),
                        value: phase
                    )
            }

            ZStack {
                // Solid stage plate + soft logo-spectrum wash. Must stay opaque
                // so the miniature never samples the desktop (grain / noise).
                RoundedRectangle(
                    cornerRadius: VibeComposeMetrics.radiusXL,
                    style: .continuous
                )
                .fill(Color(nsColor: .textBackgroundColor))
                RoundedRectangle(
                    cornerRadius: VibeComposeMetrics.radiusXL,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: VibeComposePalette.atmosphereSky)
                                .opacity(0.16),
                            Color(nsColor: VibeComposePalette.atmospherePeriwinkle)
                                .opacity(0.10),
                            Color(nsColor: VibeComposePalette.atmosphereLavender)
                                .opacity(0.08),
                            Color.clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                VStack(spacing: VibeComposeMetrics.space16) {
                    demoHUD
                        .opacity(
                            phase == .listening
                                || phase == .writing
                                || phase == .done
                                ? 1
                                : 0.40
                        )
                        .scaleEffect(phase == .listening ? 1.03 : 1.0)
                        .animation(
                            VibeComposeMotion.panelSpring,
                            value: phase
                        )

                    mockField
                    keycap
                }
                .padding(.horizontal, VibeComposeMetrics.space20)
                .padding(.vertical, VibeComposeMetrics.space20)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 220)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: VibeComposeMetrics.radiusXL,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: VibeComposeMetrics.radiusXL,
                    style: .continuous
                )
                .stroke(
                    Color(nsColor: VibeComposePalette.atmosphereIndigo)
                        .opacity(0.14),
                    lineWidth: 1
                )
            )
            .shadow(
                color: Color(nsColor: VibeComposePalette.atmosphereIndigo)
                    .opacity(0.14),
                radius: 28,
                x: 0,
                y: 14
            )
        }
        .onAppear { startLoop() }
        .onChange(of: reduceMotion) { reduced in
            if reduced {
                phase = .done
                typedText = sampleLine
                keyPressed = false
            } else {
                startLoop()
            }
        }
    }

    private var phaseCaption: String {
        switch phase {
        case .idle:
            return L10n.format("Ready · %@", hotkeyName)
        case .press:
            return L10n.format("Press %@", hotkeyName)
        case .listening:
            return L10n.text("Listening…")
        case .writing:
            return L10n.text("Delivering text…")
        case .done:
            return L10n.text("Pasted into the focused field")
        }
    }

    private var demoHUD: some View {
        HStack(spacing: 10) {
            Image(systemName: phase == .listening ? "waveform" : "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    phase == .listening
                        ? Color(nsColor: VibeComposePalette.hudRecordingAccent)
                        : Color(nsColor: VibeComposePalette.success)
                )
                .opacity(phase == .listening && !reduceMotion ? (pulse ? 1 : 0.55) : 1)

            OnboardingDemoWaveform(active: phase == .listening && !reduceMotion)
                .frame(width: 72, height: 18)

            Text(
                phase == .listening
                    ? L10n.text("Listening")
                    : (phase == .writing || phase == .done)
                        ? L10n.text("Ready")
                        : L10n.text("Idle")
            )
            .font(VibeComposeTypography.caption(.semibold))
            .foregroundStyle(Color(nsColor: VibeComposePalette.hudText))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        // Solid miniature of the real HUD — never `.ultraThinMaterial` /
        // Liquid Glass inside the wizard stage. Materials sample whatever sits
        // behind the window and read as grainy noise over desktop wallpaper.
        .background(
            Capsule(style: .continuous)
                .fill(Color(nsColor: VibeComposePalette.elevatedSurface))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(
                    phase == .listening
                        ? Color(nsColor: VibeComposePalette.hudRecordingAccent)
                            .opacity(0.28)
                        : Color(nsColor: VibeComposePalette.brandBlue)
                            .opacity(0.12),
                    lineWidth: 1
                )
        )
        .shadow(
            color: Color(nsColor: VibeComposePalette.brandBlue).opacity(0.10),
            radius: 12,
            x: 0,
            y: 4
        )
    }

    private var mockField: some View {
        HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(nsColor: VibeComposePalette.brandBlue).opacity(phase == .writing || phase == .done ? 0 : 0.85))
                .frame(width: 2, height: 14)
                .opacity(phase == .idle || phase == .press || phase == .listening ? (pulse ? 1 : 0.15) : 0)

            Text(typedText.isEmpty ? " " : typedText)
                .font(VibeComposeTypography.body(.medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    phase == .done
                        ? Color(nsColor: VibeComposePalette.success).opacity(0.45)
                        : Color(nsColor: VibeComposePalette.hairline),
                    lineWidth: 1
                )
        )
        .frame(maxWidth: 420)
    }

    private var keycap: some View {
        HStack(spacing: 8) {
            Text(hotkeyName)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: VibeComposePalette.elevatedSurface))
                        .shadow(
                            color: Color.black.opacity(keyPressed ? 0.04 : 0.12),
                            radius: keyPressed ? 1 : 3,
                            x: 0,
                            y: keyPressed ? 0 : 2
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .offset(y: keyPressed ? 1.5 : 0)

            Text(
                phase == .press
                    ? L10n.text("to start")
                    : phase == .listening
                        ? L10n.text("again to finish")
                        : L10n.format("%@ · anywhere", hotkeyName)
            )
            .font(VibeComposeTypography.caption())
            .foregroundStyle(.secondary)
        }
        .animation(VibeComposeMotion.pressSpring, value: keyPressed)
    }

    private func startLoop() {
        guard !reduceMotion else {
            phase = .done
            typedText = sampleLine
            return
        }
        phase = .idle
        typedText = ""
        keyPressed = false
        pulse = true
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            pulse = true
        }
        runCycle()
    }

    private func runCycle() {
        // idle → press
        schedule(after: 0.7) {
            phase = .press
            keyPressed = true
        }
        schedule(after: 1.05) {
            keyPressed = false
            phase = .listening
            typedText = ""
        }
        // listening → writing
        schedule(after: 2.6) {
            keyPressed = true
        }
        schedule(after: 2.9) {
            keyPressed = false
            phase = .writing
            typeSample()
        }
        // done hold, then restart
        schedule(after: 5.4) {
            phase = .done
        }
        schedule(after: 6.6) {
            withAnimation(.easeOut(duration: 0.25)) {
                typedText = ""
                phase = .idle
            }
            runCycle()
        }
    }

    private func typeSample() {
        typedText = ""
        let characters = Array(sampleLine)
        for (index, character) in characters.enumerated() {
            schedule(after: Double(index) * 0.035) {
                typedText.append(character)
            }
        }
    }

    private func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard !reduceMotion else { return }
            withAnimation(VibeComposeMotion.standardSpring) {
                work()
            }
        }
    }
}

// MARK: - Skills gallery (showcase stage)

/// Auto-advancing gallery that turns one spoken line into each Skill's real
/// output shape (Direct / Reply / Email / Code Prompt /
/// Translate). Tied to the actual `DictationMode` set so titles never drift
/// from the shipped feature. Solid / opaque — no materials in the wizard.
private struct OnboardingModeGallery: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var generation = 0

    private struct ModeSample: Identifiable {
        let mode: DictationMode
        let symbol: String
        let spoken: String
        let result: String
        var id: String { mode.rawValue }
    }

    /// Real Skills, each paired with an honest before/after that matches its
    /// shipped caption. Titles/symbols come from `DictationMode` so the gallery
    /// stays truthful to the product.
    private var samples: [ModeSample] {
        [
            ModeSample(
                mode: .direct,
                symbol: "text.aligncenter",
                spoken: L10n.text("um so we should uh ship the release notes by friday i think"),
                result: L10n.text("We should ship the release notes by Friday.")
            ),
            ModeSample(
                mode: .reply,
                symbol: "bubble.left.and.bubble.right.fill",
                spoken: L10n.text("tell her thanks for the update and yes tuesday works for the review"),
                result: L10n.text("Thanks for the update — Tuesday works for the review.")
            ),
            ModeSample(
                mode: .email,
                symbol: "envelope.fill",
                spoken: L10n.text("let the team know the demo moved to 3pm thursday and to bring their laptops"),
                result: L10n.text("Hi team,\n\nThe demo has moved to 3:00 PM on Thursday. Please bring your laptops.\n\nThanks")
            ),
            ModeSample(
                mode: .codePrompt,
                symbol: "chevron.left.forwardslash.chevron.right",
                spoken: L10n.text("write a react hook that debounces a value by 300 milliseconds"),
                result: L10n.text("Implement useDebounce(value, delay = 300):\n• return debounced value\n• reset the timer on change\n• clear the timer on unmount")
            ),
            ModeSample(
                mode: .translate,
                symbol: "character.book.closed.fill",
                spoken: L10n.text("我们周五发布新版本"),
                result: L10n.text("We are releasing the new version on Friday.")
            ),
        ]
    }

    var body: some View {
        VStack(spacing: VibeComposeMetrics.space12) {
            galleryHeader

            ZStack {
                stagePlate
                card(for: samples[safe: index] ?? samples[0])
                    .id(generation * 100 + index)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(
                                    with: .offset(x: 18, y: 0)
                                ),
                                removal: .opacity.combined(
                                    with: .offset(x: -14, y: 0)
                                )
                            )
                    )
                    .padding(.horizontal, VibeComposeMetrics.space18)
                    .padding(.vertical, VibeComposeMetrics.space18)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 236)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: VibeComposeMetrics.radiusXL,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: VibeComposeMetrics.radiusXL,
                    style: .continuous
                )
                .stroke(
                    Color(nsColor: VibeComposePalette.atmosphereIndigo)
                        .opacity(0.14),
                    lineWidth: 1
                )
            )
            .shadow(
                color: Color(nsColor: VibeComposePalette.atmosphereIndigo)
                    .opacity(0.14),
                radius: 28,
                x: 0,
                y: 14
            )

            modeDots
        }
        .onAppear { startCycle() }
        .onChange(of: reduceMotion) { _ in startCycle() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            L10n.format(
                "Skill example: %@",
                (samples[safe: index] ?? samples[0]).mode.title
            )
        )
    }

    private var galleryHeader: some View {
        HStack(spacing: VibeComposeMetrics.space8) {
            Label(
                L10n.text("Skills gallery"),
                systemImage: "wand.and.stars"
            )
            .font(VibeComposeTypography.caption(.semibold))
            .foregroundStyle(Color(nsColor: VibeComposePalette.brandBlue))
            Spacer()
            Text(
                L10n.format(
                    "%d of %d",
                    index + 1,
                    samples.count
                )
            )
            .font(VibeComposeTypography.micro(.medium))
            .foregroundStyle(.secondary)
            .contentTransition(.opacity)
        }
    }

    private var stagePlate: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusXL,
                style: .continuous
            )
            .fill(Color(nsColor: .textBackgroundColor))
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusXL,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [
                        Color(nsColor: VibeComposePalette.atmosphereSky)
                            .opacity(0.16),
                        Color(nsColor: VibeComposePalette.atmospherePeriwinkle)
                            .opacity(0.10),
                        Color(nsColor: VibeComposePalette.atmosphereLavender)
                            .opacity(0.08),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private func card(for sample: ModeSample) -> some View {
        VStack(alignment: .leading, spacing: VibeComposeMetrics.space12) {
            // Skill chip — real mode title, so copy never drifts from product.
            HStack(spacing: 7) {
                Image(systemName: sample.symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(sample.mode.title)
                    .font(VibeComposeTypography.caption(.semibold))
            }
            .foregroundStyle(Color(nsColor: VibeComposePalette.brandBlue))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        Color(nsColor: VibeComposePalette.brandBlue)
                            .opacity(0.10)
                    )
            )

            // Spoken input.
            VStack(alignment: .leading, spacing: 4) {
                Label(L10n.text("You say"), systemImage: "mic.fill")
                    .font(VibeComposeTypography.micro(.semibold))
                    .foregroundStyle(.secondary)
                Text("“\(sample.spoken)”")
                    .font(VibeComposeTypography.callout())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(
                        Color(nsColor: VibeComposePalette.brandBlue)
                            .opacity(0.7)
                    )
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
            }

            // Produced result.
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    L10n.text("VibeCompose writes"),
                    systemImage: "sparkles"
                )
                .font(VibeComposeTypography.micro(.semibold))
                .foregroundStyle(Color(nsColor: VibeComposePalette.brandBlue))
                Text(sample.result)
                    .font(VibeComposeTypography.body(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var modeDots: some View {
        HStack(spacing: 7) {
            ForEach(Array(samples.enumerated()), id: \.element.id) { i, _ in
                Capsule(style: .continuous)
                    .fill(
                        i == index
                            ? Color(nsColor: VibeComposePalette.brandBlue)
                            : Color.primary.opacity(0.16)
                    )
                    .frame(width: i == index ? 18 : 6, height: 6)
                    .contentShape(Rectangle())
                    .onTapGesture { select(i) }
            }
        }
        .animation(VibeComposeMotion.snappySpring, value: index)
        .accessibilityHidden(true)
    }

    // MARK: Cycle

    private func startCycle() {
        generation += 1
        index = 0
        guard !reduceMotion else { return }
        scheduleAdvance(from: generation)
    }

    /// Tapping a dot jumps immediately and rebases the timer so the manual
    /// pick is not yanked away a fraction of a second later.
    private func select(_ target: Int) {
        generation += 1
        withAnimation(VibeComposeMotion.stepSpring) {
            index = target
        }
        guard !reduceMotion else { return }
        scheduleAdvance(from: generation)
    }

    private func scheduleAdvance(from token: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.1) {
            guard token == generation, !reduceMotion else { return }
            withAnimation(VibeComposeMotion.stepSpring) {
                index = (index + 1) % samples.count
            }
            scheduleAdvance(from: token)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct OnboardingDemoWaveform: View {
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: active ? 1.0 / 24.0 : 1.0, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<7, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(Color(nsColor: VibeComposePalette.hudRecordingAccent))
                        .frame(width: 3, height: barHeight(index: index, t: t))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func barHeight(index: Int, t: TimeInterval) -> CGFloat {
        guard active else { return 5 }
        let phase = t * 5.2 + Double(index) * 0.7
        let wave = (sin(phase) + 1) * 0.5
        return 5 + CGFloat(wave) * 12
    }
}

// MARK: - Side illustration for permission steps

private struct OnboardingStepIllustration: View {
    let systemImage: String
    let caption: String
    let accent: Color

    var body: some View {
        VStack(spacing: VibeComposeMetrics.space12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                accent.opacity(0.22),
                                accent.opacity(0.06),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 48
                        )
                    )
                    .frame(width: 96, height: 96)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.18),
                                accent.opacity(0.06),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)
                Image(systemName: systemImage)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(accent)
                    .symbolRenderingMode(.hierarchical)
            }
            Text(caption)
                .font(VibeComposeTypography.caption())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 148)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(VibeComposeMetrics.space18)
        .frame(width: 176)
        .background(
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusXL,
                style: .continuous
            )
            .fill(
                Color(nsColor: VibeComposePalette.elevatedSurface)
                    .opacity(0.78)
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusXL,
                style: .continuous
            )
            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .shadow(
            color: Color.black.opacity(0.04),
            radius: 10,
            x: 0,
            y: 3
        )
        .accessibilityHidden(true)
    }
}

