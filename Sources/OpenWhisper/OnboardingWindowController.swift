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
            initialStep: initialStep,
            onRequestMicrophoneAccess: onRequestMicrophoneAccess,
            onStepCompleted: onStepCompleted,
            onComplete: {}
        )
        .applyingAccessibilityDisplayOptionsOverride(
            accessibilityDisplayOptionsOverride
        )
        let hostingController = NSHostingController(rootView: placeholder)
        let window = OnboardingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("Set Up OpenWhisper")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier("OpenWhisper.OnboardingWindow")
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(width: 760, height: 540)
        window.contentMaxSize = NSSize(width: 760, height: 540)
        window.center()
        window.contentViewController = hostingController
        accessibilityDisplayOptionsOverride.applyAppearance(to: window)

        super.init(window: window)

        hostingController.rootView =
            OnboardingView(
                authManager: authManager,
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
            .applyingAccessibilityDisplayOptionsOverride(
                accessibilityDisplayOptionsOverride
            )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

    let authManager: ChatGPTAuthManager
    let onRequestMicrophoneAccess:
        @MainActor @Sendable () async -> Result<Void, any Error>
    let onStepCompleted: (OnboardingStep) -> Void
    let onComplete: () -> Void

    init(
        authManager: ChatGPTAuthManager,
        initialStep: OnboardingStep = .welcome,
        onRequestMicrophoneAccess: @escaping @MainActor @Sendable () async -> Result<Void, any Error>,
        onStepCompleted: @escaping (OnboardingStep) -> Void = { _ in },
        onComplete: @escaping () -> Void
    ) {
        self.authManager = authManager
        self.onRequestMicrophoneAccess = onRequestMicrophoneAccess
        self.onStepCompleted = onStepCompleted
        self.onComplete = onComplete
        _step = State(initialValue: initialStep)
        _authSnapshot = State(initialValue: authManager.authSnapshot())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HStack(spacing: 0) {
                stepList
                Divider()

                VStack(spacing: 0) {
                    ScrollView {
                        stepContent
                            .padding(28)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    Divider()
                    navigationBar
                }
            }
        }
        .frame(width: 760, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            authSnapshot = authManager.authSnapshot()
            permissionMonitor.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("Set Up OpenWhisper"))
                    .font(.system(size: 19, weight: .semibold))
                Text(L10n.text("Four short steps to your first F5 dictation."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(L10n.format("Step %ld of 4", step.rawValue + 1))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(OnboardingStep.allCases) { candidate in
                HStack(spacing: 9) {
                    Image(systemName: candidate.rawValue < step.rawValue ? "checkmark.circle.fill" : candidate.symbol)
                        .frame(width: 18)
                        .foregroundStyle(
                            candidate.rawValue <= step.rawValue ? Color.accentColor : Color.secondary
                        )
                    Text(candidate.title)
                        .font(.system(size: 12, weight: candidate == step ? .semibold : .regular))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(candidate == step ? Color.accentColor.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .accessibilityAddTraits(candidate == step ? [.isSelected] : [])
            }
            Spacer()
            Text(
                L10n.text(
                    "Microphone is required. Accessibility is optional and only enables automatic paste."
                )
            )
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 190)
        .background(Color(nsColor: .controlBackgroundColor))
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
        VStack(alignment: .leading, spacing: 20) {
            stepTitle(
                title: "Speak anywhere on your Mac",
                subtitle: "Focus a text field, press F5 to start, press F5 again to transcribe."
            )

            onboardingFeature(
                symbol: "keyboard",
                title: "One global shortcut",
                detail: "F5 starts and stops every dictation—no mode switch or floating editor."
            )
            onboardingFeature(
                symbol: "text.badge.checkmark",
                title: "Technical language stays intact",
                detail: "Terminology and deterministic corrections protect product names, commands, and paths."
            )
            onboardingFeature(
                symbol: "doc.on.clipboard",
                title: "Safe paste or clipboard",
                detail: "OpenWhisper sends paste only to a verified editable target. If insertion cannot be confirmed, your result stays in the clipboard."
            )

            Text(
                L10n.text(
                    "The default route uses your ChatGPT account through a private, undocumented backend. OpenWhisper is independent from OpenAI, and upstream availability or limits may change."
                )
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
            .buttonStyle(.borderedProminent)
            .disabled(isConnecting)

            Text(
                L10n.text(
                    "A browser window opens for sign-in. OpenWhisper never asks for your ChatGPT password."
                )
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

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
                .buttonStyle(.borderedProminent)
                .disabled(
                    isRequestingMicrophone
                        || permissionMonitor.snapshot.microphone == .granted
                )

                if permissionMonitor.snapshot.microphone == .denied {
                    Button(L10n.text("Open Microphone Settings")) {
                        _ = PermissionSettingsDestination.microphone.open()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text(
                L10n.text(
                    "OpenWhisper requests permission only after you click Enable Microphone. Successful recordings are deleted after processing."
                )
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            statusMessage
        }
    }

    private var practiceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle(
                title: "Try your first dictation",
                subtitle: "Click the practice field, press F5, speak, then press F5 again."
            )

            statusPanel(
                symbol: permissionMonitor.snapshot.accessibilityTrusted
                    ? "checkmark.circle.fill"
                    : "doc.on.clipboard",
                title: permissionMonitor.snapshot.accessibilityTrusted
                    ? "Automatic paste is ready"
                    : "Clipboard Mode is ready",
                detail: permissionMonitor.snapshot.accessibilityTrusted
                    ? "OpenWhisper can send paste to the focused editable field and verify insertion when the app exposes text through Accessibility."
                    : "Accessibility is optional. Without it, the transcript remains in your clipboard for Command-V.",
                ready: true
            )

            if !permissionMonitor.snapshot.accessibilityTrusted {
                Button(L10n.text("Enable Automatic Paste")) {
                    AccessibilityPermission.guideAccess()
                }
                .buttonStyle(.bordered)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $practiceText)
                    .font(.system(size: 13))
                    .padding(6)
                    .accessibilityLabel(L10n.text("Dictation practice field"))
                if practiceText.isEmpty {
                    Text(L10n.text("Your first transcript will appear here—or remain in the clipboard."))
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 125)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
    }

    private var navigationBar: some View {
        HStack {
            if step != .welcome {
                Button(L10n.text("Back")) {
                    message = nil
                    step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
                }
            }
            Spacer()
            if step == .practice {
                Button(L10n.text("Finish Setup")) {
                    onStepCompleted(.practice)
                    onComplete()
                }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(L10n.text("Continue")) {
                    message = nil
                    onStepCompleted(step)
                    step = OnboardingStep(rawValue: step.rawValue + 1) ?? .practice
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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
            return L10n.text("You can record with F5.")
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
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text(title))
                .font(.system(size: 25, weight: .semibold))
            Text(L10n.text(subtitle))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func onboardingFeature(
        symbol: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text(title))
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.text(detail))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusPanel(
        symbol: String,
        title: String,
        detail: String,
        ready: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(ready ? .green : .orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text(title))
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.text(detail))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
