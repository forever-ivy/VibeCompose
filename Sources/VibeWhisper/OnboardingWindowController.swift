import AppKit
import SwiftUI

struct OnboardingStateStore {
    static let completionKey = "OpenWhisper.Onboarding.CompletedFlowVersion"
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
final class OnboardingWindowController: NSWindowController {
    private let stateStore: OnboardingStateStore

    init(
        authManager: ChatGPTAuthManager,
        hotkeyBinding: HotkeyBinding = .f5,
        initialStep: OnboardingStep = .welcome,
        persistCompletion: Bool = true,
        stateStore: OnboardingStateStore = OnboardingStateStore(),
        onRequestMicrophoneAccess: @escaping @MainActor @Sendable () async -> Result<Void, any Error>,
        onStepCompleted: @escaping (OnboardingStep) -> Void = { _ in },
        onCompleted: @escaping () -> Void
    ) {
        self.stateStore = stateStore
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
        .applyingOpenWhisperBrandTint()
        .applyingAccessibilityDisplayOptionsOverride(
            accessibilityDisplayOptionsOverride
        )
        let hostingController = NSHostingController(rootView: placeholder)
        let window = OnboardingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("Set Up OpenWhisper")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier("OpenWhisper.OnboardingWindow")
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(width: 860, height: 600)
        window.contentMaxSize = NSSize(width: 860, height: 600)
        window.center()
        window.contentViewController = hostingController
        if #available(macOS 26, *) {
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
        }
        accessibilityDisplayOptionsOverride.applyAppearance(to: window)

        super.init(window: window)

        hostingController.rootView =
            OnboardingView(
                authManager: authManager,
                hotkeyBinding: hotkeyBinding,
                initialStep: initialStep,
                onRequestMicrophoneAccess: onRequestMicrophoneAccess,
                onStepCompleted: onStepCompleted,
                onComplete: { [weak self] in
                    guard let self else {
                        return
                    }
                    self.stateStore.markCompleted(if: persistCompletion)
                    self.window?.orderOut(nil)
                    onCompleted()
                }
            )
            .applyingOpenWhisperBrandTint()
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
        window.center()
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func writeSnapshot(to url: URL) throws {
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.displayIfNeeded()
        try ProductSurfaceSnapshot.write(window: window, to: url)
    }
}

private final class OnboardingWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandW = event.type == .keyDown
            && modifiers.contains(.command)
            && event.charactersIgnoringModifiers?.lowercased() == "w"
        if isCommandW {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case connect
    case microphone
    case practice

    var id: Int { rawValue }

    var launchArgumentValue: String {
        switch self {
        case .welcome:
            return "welcome"
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
        case .connect:
            return L10n.text("Connect")
        case .microphone:
            return L10n.text("Microphone")
        case .practice:
            return L10n.text("Paste & Practice")
        }
    }

    var symbol: String {
        switch self {
        case .welcome:
            return "waveform"
        case .connect:
            return "person.crop.circle.badge.checkmark"
        case .microphone:
            return "mic"
        case .practice:
            return "text.cursor"
        }
    }
}

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
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            OpenWhisperStepProgressBar(
                steps: OnboardingStep.allCases.map(\.title),
                currentStep: step.rawValue
            )
            Divider().opacity(0.45)

            ScrollView {
                stepContent
                    .id(step)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : stepForward
                                ? .asymmetric(
                                    insertion: .opacity.combined(with: .offset(x: 28, y: 0)),
                                    removal:   .opacity.combined(with: .offset(x: -16, y: 0))
                                )
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .offset(x: -28, y: 0)),
                                    removal:   .opacity.combined(with: .offset(x: 16, y: 0))
                                )
                    )
                    .padding(.horizontal, 48)
                    .padding(.vertical, 40)
                    .frame(maxWidth: 580, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.15)
                    : OpenWhisperMotion.stepSpring,
                value: step
            )

            navigationBar
        }
        .frame(width: 860, height: 600)
        .background {
            if #available(macOS 26, *) {
                Color.clear
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            authSnapshot = authManager.authSnapshot()
            permissionMonitor.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: OpenWhisperPalette.brandBlue)
                                    .opacity(0.72),
                                Color(nsColor: OpenWhisperPalette.brandBlue),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)
                    .shadow(
                        color: Color(nsColor: OpenWhisperPalette.brandBlue).opacity(0.32),
                        radius: 8,
                        x: 0,
                        y: 3
                    )
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text("Set Up OpenWhisper"))
                    .font(OpenWhisperTypography.title())
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .connect:
            connectStep
        case .microphone:
            microphoneStep
        case .practice:
            practiceStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            stepTitle(
                title: "Speak anywhere on your Mac",
                subtitle: L10n.format(
                    "Press %@ to start, %@ again to finish.",
                    hotkeyBinding.displayName,
                    hotkeyBinding.displayName
                )
            )

            VStack(alignment: .leading, spacing: 0) {
                onboardingFeature(
                    symbol: "keyboard",
                    title: "One global shortcut",
                    detail: L10n.format(
                        "%@ starts and stops every session.",
                        hotkeyBinding.displayName
                    )
                )
                Divider()
                    .padding(.leading, 50)
                    .opacity(0.5)
                onboardingFeature(
                    symbol: "text.badge.checkmark",
                    title: "Technical language stays intact",
                    detail: "Terminology protects product names, commands, and paths."
                )
                Divider()
                    .padding(.leading, 50)
                    .opacity(0.5)
                onboardingFeature(
                    symbol: "doc.on.clipboard",
                    title: "Safe paste or clipboard",
                    detail: "Result goes to the focused field or stays in your clipboard."
                )
            }
            .openWhisperCard(
                padding: OpenWhisperMetrics.space20,
                cornerRadius: OpenWhisperMetrics.radiusXL,
                elevated: true
            )
        }
    }

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle(
                title: "Connect your ChatGPT account",
                subtitle: "OpenWhisper stores its own session in Keychain on this Mac."
            )

            statusPanel(
                symbol: authSnapshot.state == .ready ? "checkmark.circle.fill" : "person.crop.circle",
                title: authSnapshot.state == .ready ? "ChatGPT connected" : "ChatGPT connection required",
                detail: authSnapshot.userEmail ?? authSnapshot.detail,
                ready: authSnapshot.state == .ready
            )

            Button(L10n.text(isConnecting ? "Waiting for Browser" : "Connect in Browser")) {
                connect()
            }
            .buttonStyle(OpenWhisperPrimaryButtonStyle())
            .disabled(isConnecting)

            statusMessage
        }
    }

    private var microphoneStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle(
                title: "Allow microphone access",
                subtitle: "Microphone access is required only while you record a dictation."
            )

            statusPanel(
                symbol: permissionMonitor.snapshot.microphone == .granted
                    ? "checkmark.circle.fill"
                    : "mic.circle",
                title: microphoneStatusTitle,
                detail: microphoneStatusDetail,
                ready: permissionMonitor.snapshot.microphone == .granted
            )

            HStack(spacing: 10) {
                Button(L10n.text("Enable Microphone")) {
                    requestMicrophone()
                }
                .buttonStyle(OpenWhisperPrimaryButtonStyle())
                .disabled(
                    isRequestingMicrophone
                        || permissionMonitor.snapshot.microphone == .granted
                )

                if permissionMonitor.snapshot.microphone == .denied {
                    Button(L10n.text("Open Microphone Settings")) {
                        _ = PermissionSettingsDestination.microphone.open()
                    }
                    .buttonStyle(OpenWhisperSecondaryButtonStyle())
                }
            }

            statusMessage
        }
    }

    private var practiceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle(
                title: "Try your first dictation",
                subtitle: L10n.format(
                    "Click the practice field, press %@, speak, then press %@ again.",
                    hotkeyBinding.displayName,
                    hotkeyBinding.displayName
                )
            )

            statusPanel(
                symbol: permissionMonitor.snapshot.accessibilityTrusted
                    ? "checkmark.circle.fill"
                    : "doc.on.clipboard",
                title: permissionMonitor.snapshot.accessibilityTrusted
                    ? "Automatic paste is ready"
                    : "Clipboard Mode is ready",
                detail: permissionMonitor.snapshot.accessibilityTrusted
                    ? "Text lands directly in the focused field."
                    : "Transcript is copied to clipboard — press ⌘V to paste.",
                ready: true
            )

            if !permissionMonitor.snapshot.accessibilityTrusted {
                Button(L10n.text("Enable Automatic Paste")) {
                    AccessibilityPermission.guideAccess()
                }
                .buttonStyle(OpenWhisperSecondaryButtonStyle())
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $practiceText)
                    .font(OpenWhisperTypography.body())
                    .padding(8)
                    .accessibilityLabel(L10n.text("Dictation practice field"))
            }
            .frame(minHeight: 132)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(
                    cornerRadius: OpenWhisperMetrics.radiusL,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: OpenWhisperMetrics.radiusL,
                    style: .continuous
                )
                .stroke(
                    Color(nsColor: OpenWhisperPalette.hairline),
                    lineWidth: 1
                )
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        }
    }

    private var navigationBar: some View {
        HStack {
            if step != .welcome {
                Button(L10n.text("Back")) {
                    message = nil
                    stepForward = false
                    withAnimation(
                        reduceMotion
                            ? .easeOut(duration: 0.15)
                            : OpenWhisperMotion.stepSpring
                    ) {
                        step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
                    }
                }
                .buttonStyle(OpenWhisperQuietButtonStyle())
            }
            Spacer()
            if step == .practice {
                Button(L10n.text("Finish Setup")) {
                    onStepCompleted(.practice)
                    onComplete()
                }
                    .buttonStyle(OpenWhisperPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(L10n.text("Continue")) {
                    message = nil
                    onStepCompleted(step)
                    stepForward = true
                    withAnimation(
                        reduceMotion
                            ? .easeOut(duration: 0.15)
                            : OpenWhisperMotion.stepSpring
                    ) {
                        step = OnboardingStep(rawValue: step.rawValue + 1) ?? .practice
                    }
                }
                .buttonStyle(OpenWhisperPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
            }
        }
        .modifier(OnboardingNavBarGlassContainer())
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background {
            if #available(macOS 26, *) {
                Rectangle()
                    .fill(.separator.opacity(0.4))
                    .frame(height: 0.5)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                Color.clear
                    .overlay(alignment: .top) {
                        Divider().opacity(0.55)
                    }
            }
        }
    }

    private var canContinue: Bool {
        switch step {
        case .welcome:
            return true
        case .connect:
            return authSnapshot.state == .ready
        case .microphone:
            return permissionMonitor.snapshot.microphone == .granted
        case .practice:
            return true
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
            return L10n.text("Turn on OpenWhisper in System Settings > Privacy & Security > Microphone.")
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let message {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(messageIsError ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepTitle(title: String, subtitle: String) -> some View {
        Text(L10n.text(title))
            .font(OpenWhisperTypography.display())
            .tracking(-0.4)
            .accessibilityHint(L10n.text(subtitle))
    }

    private func onboardingFeature(
        symbol: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            OpenWhisperIconWell(
                systemName: symbol,
                size: 24,
                symbolSize: 12.5,
                tint: Color(nsColor: OpenWhisperPalette.brandBlue),
                fillOpacity: 0.12
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text(title))
                    .font(OpenWhisperTypography.headline())
                    .accessibilityHint(L10n.text(detail))
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusPanel(
        symbol: String,
        title: String,
        detail: String,
        ready: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            OpenWhisperIconWell(
                systemName: symbol,
                size: 36,
                symbolSize: 15,
                tint: ready
                    ? Color(nsColor: OpenWhisperPalette.success)
                    : Color(nsColor: OpenWhisperPalette.amber),
                fillOpacity: 0.14
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text(title))
                    .font(OpenWhisperTypography.headline())
                    .accessibilityHint(L10n.text(detail))
            }
            Spacer()
        }
        .padding(OpenWhisperMetrics.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OpenWhisperMetrics.radiusL, style: .continuous)
                .fill(Color(nsColor: OpenWhisperPalette.elevatedSurface))
        )
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
                        "OpenWhisper still cannot confirm microphone access. Click Refresh Status or reopen the app."
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

/// Wraps navigation bar buttons in GlassEffectContainer on macOS 26 so that
/// the Back and Continue glass buttons share one rendering context and can
/// correctly sample each other. No-op on older systems.
private struct OnboardingNavBarGlassContainer: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}
