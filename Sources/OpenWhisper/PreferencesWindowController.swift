import AppKit
import AVFoundation
import ApplicationServices
import OpenWhisperLicensing
import SwiftUI
import UniformTypeIdentifiers

enum PreferencesSnapshotError: LocalizedError {
    case missingContentView
    case bitmapUnavailable
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .missingContentView:
            return "The OpenWhisper Settings window has no content view to capture."
        case .bitmapUnavailable:
            return "The OpenWhisper Settings window could not create a bitmap snapshot."
        case .pngEncodingFailed:
            return "The OpenWhisper Settings window could not encode its snapshot as PNG."
        }
    }
}

@MainActor
final class PreferencesWindowController: NSWindowController {
    init(
        config: AppConfig,
        authManager: ChatGPTAuthManager,
        onSave: @escaping (AppConfig) -> Result<Void, any Error>,
        onImportTerminologyDictionary: @escaping (AppConfig, URL) -> Result<AppConfig, any Error>,
        onLoadRecentHistory: @escaping () -> [TranscriptionHistoryRecord],
        onLoadRecoveryHistory: @escaping () -> [RecoveryRecord],
        onResolveRecoveryAudioURL: @escaping (RecoveryRecord) -> Result<URL, any Error>,
        onRetryRecoveryRecord: @escaping (RecoveryRecord) -> Void,
        onRequestMicrophoneAccess: @escaping @MainActor @Sendable () async -> Result<Void, any Error>,
        onOpenConfigFolder: @escaping () -> Void,
        onExportSupportDiagnostics: @escaping (URL) -> Result<URL, any Error>,
        onExportProductMetrics: @escaping (URL) -> Result<URL, any Error>,
        providerCapabilityPolicy: any ProviderCapabilityChecking,
        recoveryCredentialStore: any OpenAICompatibleCredentialPersisting,
        licenseManager: any CommercialLicenseManaging,
        textPolishUsageDirectoryURL: URL? = ProductIdentity
            .applicationSupportURL(
                homeDirectoryURL: FileManager.default.homeDirectoryForCurrentUser
            ),
        softwareUpdateSnapshot: SoftwareUpdateSnapshot,
        onCheckForUpdates: @escaping () -> Result<Void, SoftwareUpdateError>,
        onSetAutomaticallyChecksForUpdates: @escaping (Bool) -> Result<SoftwareUpdateSnapshot, SoftwareUpdateError>,
        onDeleteAllData: @escaping () -> Result<AppConfig, any Error>,
        onOpenOnboarding: @escaping () -> Void,
        onHotkeyCaptureChanged:
            @escaping (Bool) -> Void = { _ in },
        onPreviewVisualFeedback:
            @escaping (
                VisualFeedbackPreview,
                VisualFeedbackConfig
            ) -> Void = { _, _ in },
        focusPane: SettingsPane? = nil
    ) {
        let view = PreferencesView(
            initialConfig: config,
            authManager: authManager,
            onSave: onSave,
            onImportTerminologyDictionary: onImportTerminologyDictionary,
            onLoadRecentHistory: onLoadRecentHistory,
            onLoadRecoveryHistory: onLoadRecoveryHistory,
            onResolveRecoveryAudioURL: onResolveRecoveryAudioURL,
            onRetryRecoveryRecord: onRetryRecoveryRecord,
            onRequestMicrophoneAccess: onRequestMicrophoneAccess,
            onOpenConfigFolder: onOpenConfigFolder,
            onExportSupportDiagnostics: onExportSupportDiagnostics,
            onExportProductMetrics: onExportProductMetrics,
            providerCapabilityPolicy: providerCapabilityPolicy,
            recoveryCredentialStore: recoveryCredentialStore,
            licenseManager: licenseManager,
            textPolishUsageDirectoryURL: textPolishUsageDirectoryURL,
            softwareUpdateSnapshot: softwareUpdateSnapshot,
            onCheckForUpdates: onCheckForUpdates,
            onSetAutomaticallyChecksForUpdates: onSetAutomaticallyChecksForUpdates,
            onDeleteAllData: onDeleteAllData,
            onOpenOnboarding: onOpenOnboarding,
            onHotkeyCaptureChanged:
                onHotkeyCaptureChanged,
            onPreviewVisualFeedback:
                onPreviewVisualFeedback,
            focusPane: focusPane
        )
        .applyingAccessibilityDisplayOptionsOverride(
            .currentVisualAcceptance
        )
        let hostingController = NSHostingController(rootView: view)

        let window = CommandClosingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 625),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = ProductIdentity.name
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier("OpenWhisper.SettingsWindow")
        window.minSize = NSSize(width: 820, height: 560)
        window.tabbingMode = .disallowed
        let restoredFrame = window.setFrameUsingName(SettingsWindowStateStore.frameAutosaveName)
        window.setFrameAutosaveName(SettingsWindowStateStore.frameAutosaveName)
        if !restoredFrame {
            window.center()
        }
        window.contentViewController = hostingController
        AccessibilityDisplayOptionsOverride.currentVisualAcceptance
            .applyAppearance(to: window)

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func writeSnapshot(to url: URL) throws {
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.displayIfNeeded()
        try ProductSurfaceSnapshot.write(window: window, to: url)
    }

    func resizeForSnapshot(_ size: SettingsSnapshotSize) {
        window?.setContentSize(
            NSSize(width: CGFloat(size.width), height: CGFloat(size.height))
        )
        window?.center()
    }
}

private final class CommandClosingWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let isCommandW = event.type == .keyDown
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
            && event.charactersIgnoringModifiers?.lowercased() == "w"

        if isCommandW {
            close()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}

private enum SettingsSaveStatus: Equatable {
    case saved
    case failed(String)
}

private extension SettingsPane {
    var icon: String {
        switch self {
        case .account:
            return "person.crop.circle"
        case .dictation:
            return "mic"
        case .appearance:
            return "sparkles"
        case .polish:
            return "wand.and.stars"
        case .paste:
            return "doc.on.clipboard"
        case .privacy:
            return "hand.raised"
        case .advanced:
            return "gearshape"
        }
    }
}

private struct TextPolishUsage: Equatable {
    var attempts = 0
    var succeeded = 0
    var failed = 0
    var skipped = 0
    var inputTokens = 0
    var outputTokens = 0

    var summary: String {
        guard attempts > 0 || skipped > 0 else {
            return L10n.text("0 attempts / 0 tokens")
        }
        return L10n.format(
            "%ld attempts / %ld succeeded / %ld failed / %ld skipped / %ld tokens",
            attempts,
            succeeded,
            failed,
            skipped,
            inputTokens + outputTokens
        )
    }
}

private struct ThirdPartyLicensesView: View {
    let documents: [ThirdPartyLicenseDocument]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIdentity: String?

    init(documents: [ThirdPartyLicenseDocument]) {
        self.documents = documents
        _selectedIdentity = State(
            initialValue: documents.first?.entry.identity
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedIdentity) {
                ForEach(documents) { document in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(document.entry.name)
                            .font(.system(size: 13, weight: .semibold))
                        Text(document.entry.pinnedDescription)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .tag(document.entry.identity)
                    .accessibilityElement(children: .combine)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(
                min: 190,
                ideal: 220,
                max: 260
            )
        } detail: {
            if let selectedDocument {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(selectedDocument.entry.name)
                                .font(.system(size: 24, weight: .semibold))
                            Text(selectedDocument.entry.pinnedDescription)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text(selectedDocument.entry.licenseName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        Text(selectedDocument.licenseText)
                            .font(
                                .system(
                                    size: 11,
                                    design: .monospaced
                                )
                            )
                            .textSelection(.enabled)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .topLeading
                            )
                    }
                    .padding(22)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(L10n.text("No license selected"))
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .navigationTitle(L10n.text("Third-Party Licenses"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.text("Close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var selectedDocument: ThirdPartyLicenseDocument? {
        guard let selectedIdentity else {
            return documents.first
        }
        return documents.first {
            $0.entry.identity == selectedIdentity
        }
    }
}

private struct PreferencesView: View {
    private enum TerminologyFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case terms = "Terms"
        case corrections = "Corrections"

        var id: String { rawValue }
    }

    @State private var config: AppConfig
    @State private var persistedConfig: AppConfig
    @State private var showsAdvancedRecovery: Bool
    @StateObject private var permissionStatusMonitor: PermissionStatusMonitor
    @State private var terminologyImportMessage: String?
    @State private var terminologyImportIsError = false
    @State private var terminologyFilter: TerminologyFilter = .all
    @State private var terminologySearchText = ""
    @State private var editingTerminologyID: UUID?
    @State private var editingTerminologyType: TerminologyEntryType = .term
    @State private var editingOriginal = ""
    @State private var editingReplacement = ""
    @State private var authSnapshot: ChatGPTAuthSnapshot
    @State private var browserBridgeSnapshot: BrowserBridgeSnapshot
    @State private var isConnectingBrowserLogin = false
    @State private var isRequestingMicrophoneAccess = false
    @State private var permissionMessage: String?
    @State private var permissionMessageIsError = false
    @State private var selectedSection: SettingsPane?
    @State private var saveStatus: SettingsSaveStatus = .saved
    @State private var textPolishUsage: [TextPolishProviderID: TextPolishUsage] = [:]
    @State private var textPolishMessage: String?
    @State private var textPolishMessageIsError = false
    @State private var editingVoiceModeRuleID: UUID?
    @State private var editingVoiceModeAppName = ""
    @State private var editingVoiceModeBundleIdentifier = ""
    @State private var editingVoiceMode: DictationMode = .reply
    @State private var voiceModeMessage: String?
    @State private var voiceModeMessageIsError = false
    @State private var recentHistoryRecords: [TranscriptionHistoryRecord] = []
    @State private var recentRecoveryRecords: [RecoveryRecord] = []
    @State private var selectedRecoveryKind: RecoveryHistoryKind = .audio
    @State private var copiedHistoryItemID: String?
    @State private var showsDeleteAllDataConfirmation = false
    @State private var privacyMessage: String?
    @State private var privacyMessageIsError = false
    @State private var productMetricsExportMessage: String?
    @State private var productMetricsExportMessageIsError = false
    @State private var diagnosticsExportMessage: String?
    @State private var diagnosticsExportMessageIsError = false
    @State private var recoveryAPIKeyInput = ""
    @State private var recoveryAPIKeyStored: Bool
    @State private var recoveryMessage: String?
    @State private var recoveryMessageIsError = false
    @State private var isTestingRecoveryConnection = false
    @State private var providerPolicySnapshot: ProviderCapabilityPolicySnapshot
    @State private var licenseSnapshot: LicenseSnapshot
    @State private var licenseDeviceIdentifier: String
    @State private var licenseMessage: String?
    @State private var licenseMessageIsError = false
    @State private var showsRemoveLicenseConfirmation = false
    @State private var hotkeyMessage: String?
    @State private var hotkeyMessageIsError = false
    @State private var isCapturingHotkey = false
    @State private var suppressNextPersist = false
    @State private var softwareUpdateSnapshot: SoftwareUpdateSnapshot
    @State private var softwareUpdateMessage: String?
    @State private var softwareUpdateMessageIsError = false
    @State private var thirdPartyLicenseDocuments:
        [ThirdPartyLicenseDocument] = []
    @State private var showsThirdPartyLicenses = false
    @State private var thirdPartyLicenseMessage: String?
    @State private var thirdPartyLicenseMessageIsError = false

    let authManager: ChatGPTAuthManager
    let onSave: (AppConfig) -> Result<Void, any Error>
    let onImportTerminologyDictionary: (AppConfig, URL) -> Result<AppConfig, any Error>
    let onLoadRecentHistory: () -> [TranscriptionHistoryRecord]
    let onLoadRecoveryHistory: () -> [RecoveryRecord]
    let onResolveRecoveryAudioURL: (RecoveryRecord) -> Result<URL, any Error>
    let onRetryRecoveryRecord: (RecoveryRecord) -> Void
    let onRequestMicrophoneAccess:
        @MainActor @Sendable () async -> Result<Void, any Error>
    let onOpenConfigFolder: () -> Void
    let onExportSupportDiagnostics: (URL) -> Result<URL, any Error>
    let onExportProductMetrics: (URL) -> Result<URL, any Error>
    let providerCapabilityPolicy: any ProviderCapabilityChecking
    let recoveryCredentialStore: any OpenAICompatibleCredentialPersisting
    let licenseManager: any CommercialLicenseManaging
    let textPolishUsageDirectoryURL: URL?
    let onCheckForUpdates: () -> Result<Void, SoftwareUpdateError>
    let onSetAutomaticallyChecksForUpdates: (Bool) -> Result<SoftwareUpdateSnapshot, SoftwareUpdateError>
    let onDeleteAllData: () -> Result<AppConfig, any Error>
    let onOpenOnboarding: () -> Void
    let onHotkeyCaptureChanged: (Bool) -> Void
    let onPreviewVisualFeedback:
        (
            VisualFeedbackPreview,
            VisualFeedbackConfig
        ) -> Void
    let windowStateStore: SettingsWindowStateStore

    init(
        initialConfig: AppConfig,
        authManager: ChatGPTAuthManager,
        onSave: @escaping (AppConfig) -> Result<Void, any Error>,
        onImportTerminologyDictionary: @escaping (AppConfig, URL) -> Result<AppConfig, any Error>,
        onLoadRecentHistory: @escaping () -> [TranscriptionHistoryRecord],
        onLoadRecoveryHistory: @escaping () -> [RecoveryRecord],
        onResolveRecoveryAudioURL: @escaping (RecoveryRecord) -> Result<URL, any Error>,
        onRetryRecoveryRecord: @escaping (RecoveryRecord) -> Void,
        onRequestMicrophoneAccess: @escaping @MainActor @Sendable () async -> Result<Void, any Error>,
        onOpenConfigFolder: @escaping () -> Void,
        onExportSupportDiagnostics: @escaping (URL) -> Result<URL, any Error>,
        onExportProductMetrics: @escaping (URL) -> Result<URL, any Error>,
        providerCapabilityPolicy: any ProviderCapabilityChecking,
        recoveryCredentialStore: any OpenAICompatibleCredentialPersisting,
        licenseManager: any CommercialLicenseManaging,
        textPolishUsageDirectoryURL: URL?,
        softwareUpdateSnapshot: SoftwareUpdateSnapshot,
        onCheckForUpdates: @escaping () -> Result<Void, SoftwareUpdateError>,
        onSetAutomaticallyChecksForUpdates: @escaping (Bool) -> Result<SoftwareUpdateSnapshot, SoftwareUpdateError>,
        onDeleteAllData: @escaping () -> Result<AppConfig, any Error>,
        onOpenOnboarding: @escaping () -> Void,
        onHotkeyCaptureChanged:
            @escaping (Bool) -> Void,
        onPreviewVisualFeedback:
            @escaping (
                VisualFeedbackPreview,
                VisualFeedbackConfig
            ) -> Void,
        focusPane: SettingsPane? = nil
    ) {
        let windowStateStore = SettingsWindowStateStore()
        let recoveryCredentialState: Result<Bool, any Error> = Result {
            try recoveryCredentialStore.hasAPIKey()
        }
        _config = State(initialValue: initialConfig)
        _persistedConfig = State(
            initialValue: initialConfig
        )
        _showsAdvancedRecovery = State(initialValue: false)
        _permissionStatusMonitor = StateObject(wrappedValue: PermissionStatusMonitor())
        _terminologyImportMessage = State(initialValue: Self.terminologyStatusMessage(for: initialConfig))
        _authSnapshot = State(initialValue: authManager.authSnapshot())
        _browserBridgeSnapshot = State(initialValue: authManager.browserBridgeSnapshot())
        _textPolishUsage = State(
            initialValue: textPolishUsageDirectoryURL.map {
                Self.loadTextPolishUsage(directoryURL: $0)
            } ?? [:]
        )
        _providerPolicySnapshot = State(initialValue: .loading)
        _licenseSnapshot = State(
            initialValue: licenseManager.snapshot()
        )
        _licenseDeviceIdentifier = State(
            initialValue:
                (try? licenseManager.deviceIdentifier()) ?? ""
        )
        _softwareUpdateSnapshot = State(initialValue: softwareUpdateSnapshot)
        switch recoveryCredentialState {
        case .success(let isStored):
            _recoveryAPIKeyStored = State(initialValue: isStored)
            _recoveryMessage = State(initialValue: nil)
            _recoveryMessageIsError = State(initialValue: false)
        case .failure(let error):
            _recoveryAPIKeyStored = State(initialValue: false)
            _recoveryMessage = State(initialValue: error.localizedDescription)
            _recoveryMessageIsError = State(initialValue: true)
        }
        _selectedSection = State(
            initialValue: windowStateStore.initialPane(
                focusedPane: focusPane
            )
        )
        self.authManager = authManager
        self.onSave = onSave
        self.onImportTerminologyDictionary = onImportTerminologyDictionary
        self.onLoadRecentHistory = onLoadRecentHistory
        self.onLoadRecoveryHistory = onLoadRecoveryHistory
        self.onResolveRecoveryAudioURL = onResolveRecoveryAudioURL
        self.onRetryRecoveryRecord = onRetryRecoveryRecord
        self.onRequestMicrophoneAccess = onRequestMicrophoneAccess
        self.onOpenConfigFolder = onOpenConfigFolder
        self.onExportSupportDiagnostics = onExportSupportDiagnostics
        self.onExportProductMetrics = onExportProductMetrics
        self.providerCapabilityPolicy = providerCapabilityPolicy
        self.recoveryCredentialStore = recoveryCredentialStore
        self.licenseManager = licenseManager
        self.textPolishUsageDirectoryURL = textPolishUsageDirectoryURL
        self.onCheckForUpdates = onCheckForUpdates
        self.onSetAutomaticallyChecksForUpdates = onSetAutomaticallyChecksForUpdates
        self.onDeleteAllData = onDeleteAllData
        self.onOpenOnboarding = onOpenOnboarding
        self.onHotkeyCaptureChanged =
            onHotkeyCaptureChanged
        self.onPreviewVisualFeedback =
            onPreviewVisualFeedback
        self.windowStateStore = windowStateStore
    }

    private var runtimeIssues: [RuntimePreflightIssue] {
        RuntimePreflight.issues(
            for: config,
            authSnapshotProvider: { authSnapshot },
            recoveryCredentialAvailable: {
                try recoveryCredentialStore.hasAPIKey()
            }
        )
    }

    private var chatGPTAccountStatus: SetupStatus {
        if config.transcription.provider == .openAICompatible {
            return SetupStatus(
                title: L10n.text("Advanced recovery route selected"),
                subtitle: L10n.text(
                    "Dictation ASR uses your compatible API. AI Polish still requires a connected ChatGPT account."
                )
            )
        }

        if let issue = runtimeIssues.first(where: {
            switch $0 {
            case .chatGPTLoginRequired, .chatGPTSessionExpired, .chatGPTSessionUnavailable:
                return true
            default:
                return false
            }
        }) {
            return SetupStatus(title: L10n.text("Needs attention"), subtitle: issue.message, isReady: false)
        }

        return SetupStatus(
            title: L10n.text("Ready"),
            subtitle: authSnapshot.detail
        )
    }

    private var microphoneStatus: SetupStatus {
        switch permissionStatusMonitor.snapshot.microphone {
        case .granted:
            return SetupStatus(
                title: L10n.text("Granted"),
                subtitle: L10n.text("Microphone access is ready.")
            )
        case .undetermined:
            return SetupStatus(
                title: L10n.text("Not requested yet"),
                subtitle: L10n.format(
                    "Press %@ once and macOS will ask for microphone access.",
                    config.transcription.dictationHotkey
                        .displayName
                ),
                isReady: false
            )
        case .denied:
            return SetupStatus(
                title: L10n.text("Needs permission"),
                subtitle: L10n.text("Microphone access was previously denied. Open Privacy & Security > Microphone to re-enable it."),
                isReady: false
            )
        }
    }

    private var accessibilityStatus: SetupStatus {
        let guidance = AccessibilityPermission.repairGuidance()

        if permissionStatusMonitor.snapshot.accessibilityTrusted {
            return SetupStatus(
                title: L10n.text("Granted"),
                subtitle: L10n.text("Auto-paste is ready.")
            )
        }

        let title: String
        switch AccessibilityPermission.signatureState() {
        case .adHocOrUnsigned:
            title = L10n.text("Re-add required")
        case .stable, .unavailable:
            title = L10n.text("Optional but recommended")
        }

        return SetupStatus(
            title: title,
            subtitle: guidance.subtitle,
            isReady: false
        )
    }

    private var accessibilityRepairActions: [PermissionRepairAction] {
        guard !permissionStatusMonitor.snapshot.accessibilityTrusted else {
            return []
        }

        return AccessibilityPermission.repairActions()
    }

    private var microphoneRepairActions: [PermissionRepairAction] {
        AudioRecorder.repairActions(for: permissionStatusMonitor.snapshot.microphone)
    }

    private var permissionRepairActions: [PermissionRepairAction] {
        var identifiers = Set<String>()
        return (microphoneRepairActions + accessibilityRepairActions).filter {
            identifiers.insert($0.id).inserted
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section {
                    ForEach(SettingsPane.allCases) { pane in
                        Label(L10n.text(pane.rawValue), systemImage: pane.icon)
                            .foregroundStyle(.primary)
                            .tag(pane)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("OpenWhisper")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(
                            L10n.format(
                                "%@ dictation workflow",
                                config.transcription
                                    .dictationHotkey
                                    .displayName
                            )
                        )
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .textCase(nil)
                    .padding(.vertical, 6)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .controlBackgroundColor))
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } detail: {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    sectionHeader
                    Spacer(minLength: 16)
                    saveStatusIndicator
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 12)

                Divider()

                Form {
                    selectedSectionView
                }
                .formStyle(.grouped)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 820, minHeight: 560)
        .onChange(of: selectedSection) { pane in
            guard let pane else {
                selectedSection = .account
                return
            }
            windowStateStore.saveSelectedPane(pane)
        }
        .onChange(of: config) { _ in
            if suppressNextPersist {
                suppressNextPersist = false
                return
            }
            persistSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionStatusMonitor.refresh()
            authSnapshot = authManager.authSnapshot()
            browserBridgeSnapshot = authManager.browserBridgeSnapshot()
            refreshTextPolishStatus()
            refreshRecentHistory()
            refreshRecoveryHistory()
            refreshRecoveryCredentialState()
            refreshLicenseStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .chatGPTAuthStateDidChange)) { _ in
            authSnapshot = authManager.authSnapshot()
            browserBridgeSnapshot = authManager.browserBridgeSnapshot()
            refreshTextPolishStatus()
        }
        .onAppear {
            permissionStatusMonitor.refresh()
            refreshTextPolishStatus()
            refreshRecentHistory()
            refreshRecoveryHistory()
            refreshRecoveryCredentialState()
            refreshLicenseStatus()
        }
        .task {
            providerPolicySnapshot = await providerCapabilityPolicy.refresh(
                force: false
            )
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else {
                    return
                }
                permissionStatusMonitor.refresh()
            }
        }
        .alert(
            L10n.text("Delete all OpenWhisper data?"),
            isPresented: $showsDeleteAllDataConfirmation
        ) {
            Button(L10n.text("Cancel"), role: .cancel) {}
            Button(L10n.text("Delete All Data"), role: .destructive) {
                deleteAllData()
            }
        } message: {
            Text(
                L10n.text(
                    "This removes transcripts, failed recordings, diagnostics, product metrics, terminology, settings, the saved ChatGPT session, the OpenAI-Compatible API key, the Pro license receipt, and the local License Device ID from this Mac. This action cannot be undone."
                )
            )
        }
        .alert(
            L10n.text("Use OpenAI-Compatible Recovery?"),
            isPresented: $showsAdvancedRecovery
        ) {
            Button(L10n.text("Cancel"), role: .cancel) {}
            Button(L10n.text("Use Paid API")) {
                activateAdvancedRecovery()
            }
        } message: {
            Text(
                L10n.text(
                    "Future dictation audio will be sent to the configured endpoint with the API key stored in Keychain. Your API provider may charge for transcription. AI Polish will still use your ChatGPT account."
                )
            )
        }
        .alert(
            L10n.text("Remove Pro license from this Mac?"),
            isPresented: $showsRemoveLicenseConfirmation
        ) {
            Button(L10n.text("Cancel"), role: .cancel) {}
            Button(L10n.text("Remove License"), role: .destructive) {
                removeLicenseReceipt()
            }
        } message: {
            Text(
                L10n.text(
                    "This removes only the local activation receipt. Community dictation remains available, and the license can be activated again subject to its device limit."
                )
            )
        }
        .sheet(isPresented: $showsThirdPartyLicenses) {
            ThirdPartyLicensesView(
                documents: thirdPartyLicenseDocuments
            )
        }
    }

    private var activeSection: SettingsPane {
        selectedSection ?? .account
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text(activeSection.rawValue))
                .font(.system(size: 24, weight: .semibold))
            Text(sectionSubtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var saveStatusIndicator: some View {
        switch saveStatus {
        case .saved:
            Label(L10n.text("Saved automatically"), systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityLabel(L10n.text("Settings saved automatically"))
        case .failed(let message):
            Label(L10n.text("Save failed"), systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.red)
                .help(message)
                .accessibilityLabel(L10n.format("Could not save settings: %@", message))
        }
    }

    private var sectionSubtitle: String {
        switch activeSection {
        case .account:
            return L10n.text("Connect ChatGPT, verify permissions, and keep the first-run flow healthy.")
        case .dictation:
            return L10n.format(
                "Configure the %@ recording route and ASR behavior.",
                config.transcription.dictationHotkey
                    .displayName
            )
        case .appearance:
            return L10n.text(
                "Choose how OpenWhisper signals recording, processing, delivery, and recovery without taking focus."
            )
        case .polish:
            return L10n.text(
                "Choose the writing shape for each app and control when AI Polish rewrites a transcript."
            )
        case .paste:
            return L10n.text("Control paste behavior while keeping clipboard recovery conservative.")
        case .privacy:
            return L10n.text("Control local retention and delete all OpenWhisper data.")
        case .advanced:
            return L10n.text("Recovery routes and lower-level compatibility settings.")
        }
    }

    @ViewBuilder
    private var selectedSectionView: some View {
        switch activeSection {
        case .account:
            accountOverviewCard
        case .dictation:
            dictationCard
        case .appearance:
            appearanceAndFeedbackCard
        case .polish:
            aiPolishCard
        case .paste:
            settingsCard(title: "Paste & Clipboard") {
                Toggle(
                    L10n.text("Restore clipboard after verified insertion"),
                    isOn: $config.injection.preserveClipboard
                )
                Text(
                    L10n.text(
                        "OpenWhisper restores the previous clipboard only after Accessibility confirms the expected text change. If the target or insertion cannot be verified, the transcript stays in the clipboard for manual Cmd+V."
                    )
                )
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        case .privacy:
            privacyCard
        case .advanced:
            advancedRecoveryCard
        }
    }

    private func persistSettings() {
        let previousHotkey =
            persistedConfig.transcription.dictationHotkey
        let requestedHotkey =
            config.transcription.dictationHotkey
        switch onSave(config) {
        case .success:
            persistedConfig = config
            saveStatus = .saved
            if previousHotkey != requestedHotkey {
                hotkeyMessage = L10n.format(
                    "Dictation shortcut changed to %@.",
                    requestedHotkey.displayName
                )
                hotkeyMessageIsError = false
            }
        case .failure(let error):
            saveStatus = .failed(error.localizedDescription)
            if previousHotkey != requestedHotkey {
                hotkeyMessage = error.localizedDescription
                hotkeyMessageIsError = true
                suppressNextPersist = true
                config.transcription.dictationHotkey =
                    previousHotkey
            }
        }
    }

    private func applyHotkeyCandidate(
        _ candidate: HotkeyBinding
    ) {
        do {
            let validated = try candidate.validated()
            if validated
                == config.transcription
                    .dictationHotkey
            {
                hotkeyMessage = L10n.format(
                    "%@ is already the dictation shortcut.",
                    validated.displayName
                )
                hotkeyMessageIsError = false
                return
            }
            hotkeyMessage = L10n.format(
                "Testing %@…",
                validated.displayName
            )
            hotkeyMessageIsError = false
            config.transcription.dictationHotkey =
                validated
        } catch {
            hotkeyMessage = error.localizedDescription
            hotkeyMessageIsError = true
        }
    }

    private static func terminologyStatusMessage(for config: AppConfig) -> String? {
        let entries = config.transcription.terminology.entries
        guard !entries.isEmpty else {
            return nil
        }

        if let timestamp = config.transcription.terminology.lastImportedAt {
            return L10n.format(
                "Dictionary has %ld entries. Last dictionary import: %@.",
                entries.count,
                timestamp
            )
        }

        return L10n.format("Dictionary has %ld entries.", entries.count)
    }

    private static func loadTextPolishUsage(
        directoryURL: URL = ProductIdentity.applicationSupportURL(
            homeDirectoryURL: FileManager.default.homeDirectoryForCurrentUser
        )
    ) -> [TextPolishProviderID: TextPolishUsage] {
        let samples = (try? LatencyRecorder(directoryURL: directoryURL).loadRecent(limit: 1_000)) ?? []
        var usage: [TextPolishProviderID: TextPolishUsage] = [:]

        for sample in samples {
            let attempted = sample.textPolishAttempted ?? (sample.polishMs > 0 || sample.textPolishProvider != nil)
            let provider = sample.textPolishProvider.flatMap(TextPolishProviderID.init(rawValue:)) ?? .chatGPTAuth
            var current = usage[provider] ?? TextPolishUsage()
            guard attempted else {
                if sample.textPolishDecisionReason != nil {
                    current.skipped += 1
                    usage[provider] = current
                }
                continue
            }

            current.attempts += 1
            if sample.textPolishProvider != nil {
                current.succeeded += 1
                current.inputTokens += sample.estimatedPolishInputTokens
                current.outputTokens += sample.estimatedPolishOutputTokens
            } else {
                current.failed += 1
            }
            usage[provider] = current
        }

        return usage
    }

    private func refreshTextPolishStatus() {
        textPolishUsage = textPolishUsageDirectoryURL.map {
            Self.loadTextPolishUsage(directoryURL: $0)
        } ?? [:]
    }

    private func refreshRecentHistory() {
        recentHistoryRecords = onLoadRecentHistory()
    }

    private func refreshRecoveryHistory() {
        recentRecoveryRecords = onLoadRecoveryHistory()
    }

    private var recentRecoveryItems: [RecoveryHistoryPreview] {
        RecoveryHistoryPreview.recentItems(
            from: recentRecoveryRecords,
            kind: selectedRecoveryKind,
            limit: 10
        )
    }

    private var recentDictationHistoryItems: [TranscriptionHistoryPreview] {
        TranscriptionHistoryPreview.recentItems(
            from: recentHistoryRecords,
            limit: 5,
            textSource: .dictation
        )
    }

    private var recentPolishHistoryItems: [TranscriptionHistoryPreview] {
        TranscriptionHistoryPreview.recentItems(
            from: recentHistoryRecords,
            limit: 5,
            textSource: .polish
        )
    }

    private var filteredTerminologyEntries: [TerminologyEntry] {
        let query = terminologySearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        return config.transcription.terminology.entries.filter { entry in
            let include: Bool
            switch terminologyFilter {
            case .all:
                include = true
            case .terms:
                include = entry.type == .term
            case .corrections:
                include = entry.type == .correction
            }
            guard include else {
                return false
            }
            guard !query.isEmpty else {
                return true
            }
            return [
                entry.original,
                entry.replacement ?? "",
                entry.aliases.joined(separator: " "),
                entry.source,
            ]
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .contains(query)
        }
        .sorted {
            $0.original.localizedStandardCompare($1.original) == .orderedAscending
        }
    }

    private var accountOverviewCard: some View {
        settingsCard(title: "Account & Permissions") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    compactSetupTile(title: "ChatGPT", status: chatGPTAccountStatus)
                    compactSetupTile(title: "Microphone", status: microphoneStatus)
                    compactSetupTile(title: "Accessibility", status: accessibilityStatus)
                }

                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(authSnapshot.userEmail ?? L10n.text("Connect ChatGPT to start dictation."))
                            .font(.system(size: 12, weight: .medium))
                        Text(
                            L10n.format(
                                "%@ starts and stops recording. Output pastes when an editable target is focused; otherwise it stays in the clipboard.",
                                config.transcription
                                    .dictationHotkey
                                    .displayName
                            )
                        )
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    chatGPTSetupActions
                }

                HStack {
                    Text(
                        L10n.format(
                            "Need to revisit the first-run flow or practice %@ again?",
                            config.transcription
                                .dictationHotkey
                                .displayName
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.text("Open Setup Guide"), action: onOpenOnboarding)
                        .buttonStyle(.bordered)
                }

                if permissionStatusMonitor.snapshot.microphone != .granted
                    || !permissionStatusMonitor.snapshot.accessibilityTrusted {
                    Divider()
                    HStack(spacing: 10) {
                        ForEach(permissionRepairActions) { action in
                            repairActionButton(action)
                        }
                    }

                    if isRequestingMicrophoneAccess {
                        Label(
                            L10n.text("Requesting microphone"),
                            systemImage: "mic.badge.plus"
                        )
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    }

                    if !permissionStatusMonitor.snapshot.accessibilityTrusted,
                       let detail = AccessibilityPermission.repairGuidance().detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let permissionMessage {
                    Text(permissionMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(
                            permissionMessageIsError ? .red : .secondary
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                licenseSection
            }
        }
    }

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L10n.text("License & Pro"))
                    .font(.system(size: 13, weight: .semibold))
                Text(licenseSnapshot.localizedStatusTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(licenseStatusColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        licenseStatusColor.opacity(0.12)
                    )
                    .clipShape(Capsule())
                Spacer()
            }

            Text(licenseSnapshot.localizedStatusDetail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let verificationDueAt =
                licenseSnapshot.verificationDueAt
            {
                LabeledContent(L10n.text("Verification due")) {
                    Text(
                        verificationDueAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    .font(.system(size: 11))
                }
            }

            if let maximumBuild = licenseSnapshot.maximumBuild {
                LabeledContent(L10n.text("Eligible through build")) {
                    Text(String(maximumBuild))
                        .font(
                            .system(
                                size: 11,
                                design: .monospaced
                            )
                        )
                }
            }

            if !licenseDeviceIdentifier.isEmpty {
                LabeledContent(L10n.text("Device ID")) {
                    HStack(spacing: 8) {
                        Text(licenseDeviceIdentifier)
                            .font(
                                .system(
                                    size: 10,
                                    design: .monospaced
                                )
                            )
                            .textSelection(.enabled)
                            .lineLimit(1)
                        Button(L10n.text("Copy")) {
                            copyLicenseDeviceIdentifier()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            HStack(spacing: 10) {
                Button(L10n.text("Import Signed License…")) {
                    importLicenseReceipt()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !licenseManager.canInstallReceipts()
                        || licenseSnapshot.state == .preview
                )

                if storedLicenseCanBeRemoved {
                    Button(
                        L10n.text("Remove License"),
                        role: .destructive
                    ) {
                        showsRemoveLicenseConfirmation = true
                    }
                    .buttonStyle(.bordered)
                }

                if !licenseManager.canInstallReceipts() {
                    Text(
                        L10n.text(
                            "Signed license import is unavailable in this preview build."
                        )
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            }

            if let licenseMessage {
                Text(licenseMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        licenseMessageIsError ? .red : .secondary
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var storedLicenseCanBeRemoved: Bool {
        switch licenseSnapshot.state {
        case .active,
             .offlineGrace,
             .verificationRequired,
             .updateEntitlementExpired,
             .deviceMismatch,
             .invalid:
            return true
        case .community, .preview, .configurationError:
            return false
        }
    }

    private var licenseStatusColor: Color {
        switch licenseSnapshot.state {
        case .active, .preview:
            return .green
        case .offlineGrace, .updateEntitlementExpired:
            return .orange
        case .community:
            return .secondary
        case .verificationRequired,
             .deviceMismatch,
             .invalid,
             .configurationError:
            return .red
        }
    }

    private func refreshLicenseStatus() {
        licenseSnapshot = licenseManager.snapshot()
        licenseDeviceIdentifier =
            (try? licenseManager.deviceIdentifier()) ?? ""
    }

    private func copyLicenseDeviceIdentifier() {
        guard !licenseDeviceIdentifier.isEmpty else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            licenseDeviceIdentifier,
            forType: .string
        )
        licenseMessage = L10n.text("Device ID copied.")
        licenseMessageIsError = false
    }

    private func importLicenseReceipt() {
        let panel = NSOpenPanel()
        let receiptType = UTType(
            filenameExtension: "owlicense",
            conformingTo: .json
        )
        panel.allowedContentTypes = [receiptType ?? .json, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = L10n.text("Import Signed License")
        panel.prompt = L10n.text("Import")

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let values = try url.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                ]
            )
            guard
                values.isRegularFile == true,
                values.isSymbolicLink != true,
                let fileSize = values.fileSize,
                fileSize > 0,
                fileSize <= LicenseManager.maximumReceiptBytes
            else {
                throw LicenseValidationError.malformedReceipt
            }
            let data = try Data(
                contentsOf: url,
                options: [.mappedIfSafe]
            )
            licenseSnapshot = try licenseManager.installReceipt(data)
            licenseMessage = L10n.text(
                "The signed Pro license was installed for this Mac."
            )
            licenseMessageIsError = false
        } catch {
            licenseMessage = localizedLicenseImportError(error)
            licenseMessageIsError = true
        }
    }

    private func removeLicenseReceipt() {
        do {
            try licenseManager.removeReceipt()
            refreshLicenseStatus()
            licenseMessage = L10n.text(
                "The local license receipt was removed. Community dictation remains available."
            )
            licenseMessageIsError = false
        } catch {
            licenseMessage = L10n.text(
                "OpenWhisper could not remove the local license receipt."
            )
            licenseMessageIsError = true
        }
    }

    private func localizedLicenseImportError(
        _ error: any Error
    ) -> String {
        switch error as? LicenseValidationError {
        case .deviceMismatch:
            return L10n.text(
                "This license was activated for a different Mac."
            )
        case .invalidSignature:
            return L10n.text(
                "The license signature could not be verified."
            )
        case .wrongProduct:
            return L10n.text(
                "This license was issued for a different product."
            )
        case .configurationMissing, .invalidPublicKey:
            return L10n.text(
                "This build cannot verify signed licenses."
            )
        default:
            return L10n.text(
                "The license could not be installed. Use the original signed receipt and verify that it was issued for this Device ID."
            )
        }
    }

    private var dictationCard: some View {
        settingsCard(title: "Dictation / ASR") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    LabeledContent(
                        L10n.text("Dictation shortcut")
                    ) {
                        HStack(spacing: 8) {
                            HotkeyRecorderView(
                                binding:
                                    config.transcription
                                        .dictationHotkey,
                                onCandidate: {
                                    candidate in
                                    applyHotkeyCandidate(
                                        candidate
                                    )
                                },
                                onCaptureChanged: {
                                    capturing in
                                    isCapturingHotkey =
                                        capturing
                                    onHotkeyCaptureChanged(
                                        capturing
                                    )
                                    if capturing {
                                        hotkeyMessage =
                                            L10n.text(
                                                "Press the shortcut you want to use. Esc cancels without changing the current shortcut."
                                            )
                                        hotkeyMessageIsError =
                                            false
                                    }
                                }
                            )
                            .frame(width: 176, height: 30)

                            Button(
                                L10n.text("Restore F5")
                            ) {
                                applyHotkeyCandidate(.f5)
                            }
                            .buttonStyle(.bordered)
                            .disabled(
                                config.transcription
                                    .dictationHotkey == .f5
                                    || isCapturingHotkey
                            )
                        }
                    }

                    Text(
                        L10n.format(
                            "%@ starts recording, and the same shortcut stops and submits the dictation. Esc and the inline close control still cancel.",
                            config.transcription
                                .dictationHotkey
                                .displayName
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )

                    if let hotkeyMessage {
                        Text(hotkeyMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(
                                hotkeyMessageIsError
                                    ? .red
                                    : .secondary
                            )
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                    }
                }

                Toggle(L10n.text("Feedback sounds"), isOn: $config.transcription.feedbackSoundsEnabled)
                Toggle(L10n.text("ASR prompt cleanup"), isOn: $config.transcription.speechCleanupEnabled)

                Divider()

                LabeledContent(L10n.text("Chinese output")) {
                    Picker(
                        L10n.text("Chinese output"),
                        selection: $config.transcription.languagePreference
                    ) {
                        ForEach(TranscriptLanguagePreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 230)
                }

                LabeledContent(L10n.text("Punctuation")) {
                    Picker(
                        L10n.text("Punctuation"),
                        selection: $config.transcription.punctuationPreference
                    ) {
                        ForEach(TranscriptPunctuationPreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 230)
                }

                Text(
                    L10n.text(
                        "Technical literals such as paths, URLs, filenames, versions, commands, flags, and code spans are preserved byte-for-byte."
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("Default ASR route"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(L10n.text("ChatGPT Account"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(L10n.text("Uses the ChatGPT backend transcribe API. This ASR response is already lightly polished by ChatGPT and is separate from the AI Polish rewrite tab."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                historySection(
                    title: "Recent Dictation History",
                    textSource: .dictation
                )
            }
        }
    }

    private var appearanceAndFeedbackCard:
        some View
    {
        settingsCard(
            title: "Appearance & Feedback"
        ) {
            VStack(
                alignment: .leading,
                spacing: 14
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 7
                ) {
                    Text(
                        L10n.text(
                            "Visual feedback"
                        )
                    )
                    .font(
                        .system(
                            size: 12,
                            weight: .medium
                        )
                    )

                    Picker(
                        L10n.text(
                            "Visual feedback"
                        ),
                        selection:
                            $config.visualFeedback
                                .mode
                    ) {
                        ForEach(
                            VisualFeedbackMode
                                .allCases
                        ) { mode in
                            Text(mode.title)
                                .tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    Text(
                        config.visualFeedback
                            .mode.detail
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }

                Divider()

                LabeledContent(
                    L10n.text("Intensity")
                ) {
                    Picker(
                        L10n.text("Intensity"),
                        selection:
                            $config.visualFeedback
                                .intensity
                    ) {
                        ForEach(
                            VisualFeedbackIntensity
                                .allCases
                        ) { intensity in
                            Text(intensity.title)
                                .tag(intensity)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }

                if config.visualFeedback.mode
                    == .blueSignalFrame
                {
                    LabeledContent(
                        L10n.text("Frame target")
                    ) {
                        Picker(
                            L10n.text(
                                "Frame target"
                            ),
                            selection:
                                $config
                                    .visualFeedback
                                    .frameTarget
                        ) {
                            ForEach(
                                BlueSignalFrameTarget
                                    .allCases
                            ) { target in
                                Text(target.title)
                                    .tag(target)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 230)
                    }
                }

                Toggle(
                    L10n.text(
                        "Show status text when an action needs explanation"
                    ),
                    isOn:
                        $config.visualFeedback
                            .showStatusText
                )
                .disabled(
                    config.visualFeedback.mode
                        == .hidden
                )

                Toggle(
                    L10n.text("Feedback sounds"),
                    isOn:
                        $config.transcription
                            .feedbackSoundsEnabled
                )

                Toggle(
                    L10n.text(
                        "Completion notification"
                    ),
                    isOn:
                        $config.visualFeedback
                            .completionNotificationEnabled
                )

                Toggle(
                    L10n.text(
                        "Always reduce motion"
                    ),
                    isOn:
                        $config.visualFeedback
                            .alwaysReduceMotion
                )

                Text(
                    L10n.text(
                        "OpenWhisper always follows macOS Increase Contrast and Reduce Motion. Always reduce motion keeps every OpenWhisper feedback surface static even when the system setting is off."
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )

                Divider()

                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {
                    Text(
                        L10n.text(
                            "Preview feedback"
                        )
                    )
                    .font(
                        .system(
                            size: 12,
                            weight: .medium
                        )
                    )

                    HStack(spacing: 8) {
                        ForEach(
                            VisualFeedbackPreview
                                .allCases
                        ) { preview in
                            Button(preview.title) {
                                onPreviewVisualFeedback(
                                    preview,
                                    config.visualFeedback
                                )
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if config.visualFeedback.mode
                        == .hidden
                    {
                        Text(
                            L10n.text(
                                "Hidden intentionally produces no visible preview; menu status, sounds, notifications, and accessibility announcements remain available."
                            )
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var privacyCard: some View {
        settingsCard(title: "Privacy & Data") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(
                        L10n.text("Keep local transcript history"),
                        isOn: $config.privacy.historyEnabled
                    )

                    if config.privacy.historyEnabled {
                        Toggle(
                            L10n.text("Also keep the raw ASR transcript"),
                            isOn: $config.privacy.storeRawTranscripts
                        )
                        Stepper(
                            L10n.format(
                                "Keep transcript history for %ld days",
                                config.privacy.historyRetentionDays
                            ),
                            value: $config.privacy.historyRetentionDays,
                            in: 1...3_650
                        )
                        Stepper(
                            L10n.format(
                                "Keep at most %ld transcript records",
                                config.privacy.historyRecordLimit
                            ),
                            value: $config.privacy.historyRecordLimit,
                            in: 10...10_000,
                            step: 50
                        )
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(
                        L10n.text("Keep failed recordings for retry"),
                        isOn: $config.privacy.failedAudioRecoveryEnabled
                    )
                    Text(
                        L10n.text(
                            "Successful recordings are deleted after processing and are never added to Recovery."
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                    if config.privacy.failedAudioRecoveryEnabled {
                        Stepper(
                            L10n.format(
                                "Delete failed recordings after %ld hours",
                                config.privacy.failedAudioRetentionHours
                            ),
                            value: $config.privacy.failedAudioRetentionHours,
                            in: 1...168
                        )
                        Stepper(
                            L10n.format(
                                "Keep at most %ld failed recordings",
                                config.privacy.failedAudioRecordLimit
                            ),
                            value: $config.privacy.failedAudioRecordLimit,
                            in: 1...100
                        )
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(
                        L10n.text("Keep local performance diagnostics"),
                        isOn: $config.privacy.diagnosticsEnabled
                    )
                    Text(
                        L10n.text(
                            "Diagnostics contain timing, byte counts, provider labels, and error categories—not audio, transcript text, clipboard contents, or tokens."
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                    if config.privacy.diagnosticsEnabled {
                        Stepper(
                            L10n.format(
                                "Keep diagnostics for %ld days",
                                config.privacy.diagnosticsRetentionDays
                            ),
                            value: $config.privacy.diagnosticsRetentionDays,
                            in: 1...365
                        )
                        Stepper(
                            L10n.format(
                                "Keep at most %ld diagnostic records",
                                config.privacy.diagnosticsRecordLimit
                            ),
                            value: $config.privacy.diagnosticsRecordLimit,
                            in: 100...20_000,
                            step: 100
                        )
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(
                        L10n.text("Keep local anonymous product metrics"),
                        isOn: $config.privacy.productMetricsEnabled
                    )
                    Text(
                        L10n.text(
                            "Product metrics contain only version, onboarding step, provider category, duration and latency buckets, result category, and failure category. They never include audio, transcript text, app names, paths, account details, or persistent identifiers, and are never uploaded automatically."
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                    if config.privacy.productMetricsEnabled {
                        Stepper(
                            L10n.format(
                                "Keep product metrics for %ld days",
                                config.privacy
                                    .productMetricsRetentionDays
                            ),
                            value: $config.privacy
                                .productMetricsRetentionDays,
                            in: 1...365
                        )
                        Stepper(
                            L10n.format(
                                "Keep at most %ld product metric events",
                                config.privacy.productMetricsRecordLimit
                            ),
                            value: $config.privacy
                                .productMetricsRecordLimit,
                            in: 100...50_000,
                            step: 100
                        )
                    }

                    HStack(spacing: 10) {
                        Button(
                            L10n.text(
                                "Export Product Metrics…"
                            )
                        ) {
                            exportProductMetrics()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!config.privacy.productMetricsEnabled)

                        Text(
                            L10n.text(
                                "Exports an aggregate JSON report with enum and bucket counts only. It contains no event timestamps, content, app names, paths, account details, or persistent identifiers; you decide whether to share it."
                            )
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }

                    if let productMetricsExportMessage {
                        Text(productMetricsExportMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(
                                productMetricsExportMessageIsError
                                    ? .red
                                    : .secondary
                            )
                    }
                }

                Divider()

                Toggle(
                    L10n.text("Do not save history or recovery audio for sensitive apps"),
                    isOn: $config.privacy.excludeSensitiveApps
                )
                Text(
                    L10n.text(
                        "OpenWhisper excludes known password managers and Keychain/Passwords apps by default."
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                Divider()

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.text("Delete all local data"))
                            .font(.system(size: 12, weight: .semibold))
                        Text(
                            L10n.text(
                                "Deletes settings, terminology, history, failed recordings, diagnostics, product metrics, retry files, the saved ChatGPT session, the OpenAI-Compatible API key, the Pro license receipt, and the local License Device ID."
                            )
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.text("Delete All Data")) {
                        showsDeleteAllDataConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                if let privacyMessage {
                    Text(privacyMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(privacyMessageIsError ? .red : .secondary)
                }
            }
        }
    }

    private func deleteAllData() {
        switch onDeleteAllData() {
        case .success(let freshConfig):
            config = freshConfig
            recentHistoryRecords = []
            recentRecoveryRecords = []
            textPolishUsage = [:]
            copiedHistoryItemID = nil
            recoveryAPIKeyInput = ""
            recoveryAPIKeyStored = false
            recoveryMessage = nil
            recoveryMessageIsError = false
            authSnapshot = authManager.authSnapshot()
            browserBridgeSnapshot = authManager.browserBridgeSnapshot()
            privacyMessage = L10n.text("All OpenWhisper data was deleted from this Mac.")
            privacyMessageIsError = false
            refreshLicenseStatus()
        case .failure(let error):
            privacyMessage = error.localizedDescription
            privacyMessageIsError = true
        }
    }

    private var advancedRecoveryCard: some View {
        settingsCard(title: "Current Product Route") {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("OpenWhisper ships as a ChatGPT account dictation app. The normal path uses the ChatGPT backend for ASR and the ChatGPT-authenticated Responses endpoint for AI Polish."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    routeRow(
                        title: "Dictation",
                        value: config.transcription.provider.title,
                        detail: config.transcription.provider == .openAICompatible
                            ? config.transcription.openAITranscriptionURL
                            : ManagedEndpointPolicy.transcriptionURL.absoluteString
                    )
                    routeRow(
                        title: "AI Polish",
                        value: "ChatGPT Auth",
                        detail: L10n.format(
                            "%@ via %@",
                            config.transcription.textPolish.chatGPTResponseModel,
                            ManagedEndpointPolicy.responsesURL.absoluteString
                        )
                    )
                }

                Text(
                    L10n.text(
                        "OpenAI-Compatible Recovery changes dictation ASR only. AI Polish remains on the ChatGPT-authenticated route and still requires a connected ChatGPT account."
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("OpenAI-Compatible Recovery"))
                        .font(.system(size: 13, weight: .semibold))

                    LabeledContent(L10n.text("Endpoint")) {
                        TextField(
                            "",
                            text: $config.transcription.openAITranscriptionURL,
                            prompt: Text(
                                "https://api.example.com/v1/audio/transcriptions"
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(minWidth: 360)
                    }

                    LabeledContent(L10n.text("Model")) {
                        TextField(
                            "",
                            text: $config.transcription.openAIModel,
                            prompt: Text("gpt-4o-mini-transcribe")
                        )
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(minWidth: 260)
                    }

                    LabeledContent(L10n.text("API Key")) {
                        HStack(spacing: 8) {
                            SecureField(
                                "",
                                text: $recoveryAPIKeyInput,
                                prompt: Text(
                                    L10n.text(
                                        "Enter a replacement API key"
                                    )
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(minWidth: 260)

                            Button(L10n.text("Save API Key")) {
                                saveRecoveryAPIKey()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                recoveryAPIKeyInput
                                    .trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    )
                                    .isEmpty
                            )

                            Button(
                                L10n.text("Remove API Key"),
                                role: .destructive
                            ) {
                                removeRecoveryAPIKey()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!recoveryAPIKeyStored)
                        }
                    }

                    Label(
                        L10n.text(
                            recoveryAPIKeyStored
                                ? "API key stored in Keychain"
                                : "API key not configured"
                        ),
                        systemImage: recoveryAPIKeyStored
                            ? "checkmark.shield.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(
                        recoveryAPIKeyStored ? .green : .orange
                    )
                    .font(.system(size: 11, weight: .medium))

                    HStack(spacing: 10) {
                        Button(
                            L10n.text(
                                isTestingRecoveryConnection
                                    ? "Testing Connection…"
                                    : "Test Connection"
                            )
                        ) {
                            testRecoveryConnection()
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            isTestingRecoveryConnection
                                || !recoveryAPIKeyStored
                        )

                        if config.transcription.provider
                            == .openAICompatible
                        {
                            Button(
                                L10n.text("Switch Back to ChatGPT Account")
                            ) {
                                switchBackToChatGPT()
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button(
                                L10n.text(
                                    "Use OpenAI-Compatible Recovery…"
                                )
                            ) {
                                showsAdvancedRecovery = true
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                !recoveryAPIKeyStored
                                    || config.transcription
                                        .openAITranscriptionURL
                                        .trimmingCharacters(
                                            in: .whitespacesAndNewlines
                                        )
                                        .isEmpty
                                    || config.transcription.openAIModel
                                        .trimmingCharacters(
                                            in: .whitespacesAndNewlines
                                        )
                                        .isEmpty
                            )
                        }
                    }

                    Text(
                        L10n.text(
                            "Connection testing sends a generated 0.1-second silent WAV—not your recordings or transcript text. The configured provider may still charge for the request."
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)

                    if let recoveryMessage {
                        Text(recoveryMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(
                                recoveryMessageIsError ? .red : .secondary
                            )
                            .textSelection(.enabled)
                    }
                }

                Divider()

                LabeledContent(L10n.text("Configuration")) {
                    Button(L10n.text("Open Config Folder"), action: onOpenConfigFolder)
                        .buttonStyle(.bordered)
                }
                Text(
                    L10n.text(
                        "Open the local support folder only for advanced troubleshooting, backup, or manual inspection."
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                Divider()

                LabeledContent(L10n.text("Open Source Licenses")) {
                    Button(L10n.text("View Third-Party Licenses…")) {
                        showThirdPartyLicenses()
                    }
                    .buttonStyle(.bordered)
                }
                Text(
                    L10n.text(
                        "Review the exact pinned dependency versions and license texts bundled with this copy of OpenWhisper."
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                if let thirdPartyLicenseMessage {
                    Text(thirdPartyLicenseMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(
                            thirdPartyLicenseMessageIsError
                                ? .red
                                : .secondary
                        )
                }

                Divider()

                LabeledContent(L10n.text("Provider Safety")) {
                    Button(L10n.text("Refresh Safety Policy")) {
                        Task {
                            providerPolicySnapshot =
                                await providerCapabilityPolicy.refresh(force: true)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!providerPolicySnapshot.isConfigured)
                }

                Text(providerPolicySnapshot.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(providerPolicyStatusColor)

                if !providerPolicySnapshot.disabledCapabilities.isEmpty {
                    Text(
                        providerPolicySnapshot.disabledCapabilities
                            .map(\.title)
                            .joined(separator: " · ")
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
                }

                if let expiresAt = providerPolicySnapshot.expiresAt {
                    Text(
                        L10n.format(
                            "Safety policy expires: %@",
                            expiresAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                Divider()

                LabeledContent(L10n.text("Software Updates")) {
                    Button(L10n.text("Check for Updates…")) {
                        checkForSoftwareUpdates()
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        !softwareUpdateSnapshot.isConfigured
                            || !softwareUpdateSnapshot.canCheckForUpdates
                    )
                }

                Toggle(
                    L10n.text("Automatically check for updates"),
                    isOn: Binding(
                        get: {
                            softwareUpdateSnapshot.automaticallyChecksForUpdates
                        },
                        set: { enabled in
                            setAutomaticUpdateChecks(enabled)
                        }
                    )
                )
                .disabled(!softwareUpdateSnapshot.isConfigured)

                Text(softwareUpdateSnapshot.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if let lastCheckDate = softwareUpdateSnapshot.lastUpdateCheckDate {
                    Text(
                        L10n.format(
                            "Last checked: %@",
                            lastCheckDate.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                if let softwareUpdateMessage {
                    Text(softwareUpdateMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(
                            softwareUpdateMessageIsError ? .red : .secondary
                        )
                }

                Divider()

                LabeledContent(L10n.text("Support Diagnostics")) {
                    Button(L10n.text("Export Diagnostics…")) {
                        exportSupportDiagnostics()
                    }
                    .buttonStyle(.bordered)
                }
                Text(
                    L10n.text(
                        "Creates a local ZIP with redacted runtime, permission, latency, optional product-metric, and crash-summary data. It excludes audio, transcripts, clipboard text, account email, tokens, API keys, terminology, custom endpoints, and raw crash reports."
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                if let diagnosticsExportMessage {
                    Text(diagnosticsExportMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(
                            diagnosticsExportMessageIsError ? .red : .secondary
                        )
                }
            }
        }
    }

    private func refreshRecoveryCredentialState() {
        do {
            recoveryAPIKeyStored = try recoveryCredentialStore.hasAPIKey()
            if recoveryMessageIsError {
                recoveryMessage = nil
                recoveryMessageIsError = false
            }
        } catch {
            recoveryAPIKeyStored = false
            recoveryMessage = error.localizedDescription
            recoveryMessageIsError = true
        }
    }

    private func saveRecoveryAPIKey() {
        do {
            try recoveryCredentialStore.saveAPIKey(recoveryAPIKeyInput)
            recoveryAPIKeyInput = ""
            recoveryAPIKeyStored = true
            recoveryMessage = L10n.text(
                "OpenAI-Compatible API key saved in Keychain."
            )
            recoveryMessageIsError = false
        } catch {
            recoveryAPIKeyStored =
                (try? recoveryCredentialStore.hasAPIKey()) ?? false
            recoveryMessage = error.localizedDescription
            recoveryMessageIsError = true
        }
    }

    private func removeRecoveryAPIKey() {
        do {
            try recoveryCredentialStore.deleteAPIKey()
            recoveryAPIKeyInput = ""
            recoveryAPIKeyStored = false
            if config.transcription.provider == .openAICompatible {
                config.transcription.provider = .chatGPTManagedAuth
                recoveryMessage = L10n.text(
                    "API key removed. Dictation switched back to the ChatGPT account route."
                )
            } else {
                recoveryMessage = L10n.text(
                    "OpenAI-Compatible API key removed from Keychain."
                )
            }
            recoveryMessageIsError = false
        } catch {
            recoveryMessage = error.localizedDescription
            recoveryMessageIsError = true
        }
    }

    private func testRecoveryConnection() {
        isTestingRecoveryConnection = true
        recoveryMessage = L10n.text(
            "Testing the configured endpoint with generated silence…"
        )
        recoveryMessageIsError = false
        let tester = OpenAICompatibleConnectionTester(
            credentialStore: recoveryCredentialStore
        )
        let transcriptionConfig = config.transcription

        Task { @MainActor in
            do {
                try await tester.test(config: transcriptionConfig)
                recoveryAPIKeyStored = true
                recoveryMessage = L10n.text(
                    "Connection succeeded. The endpoint accepted the Keychain credential and synthetic audio."
                )
                recoveryMessageIsError = false
            } catch {
                recoveryMessage = error.localizedDescription
                recoveryMessageIsError = true
                recoveryAPIKeyStored =
                    (try? recoveryCredentialStore.hasAPIKey()) ?? false
            }
            isTestingRecoveryConnection = false
        }
    }

    private func activateAdvancedRecovery() {
        do {
            guard try recoveryCredentialStore.hasAPIKey() else {
                throw OpenAICompatibleConnectionTestError.missingAPIKey
            }
            _ = try ManagedEndpointPolicy.validatedUserOwnedURL(
                config.transcription.openAITranscriptionURL
            )
            guard
                !config.transcription.openAIModel
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            else {
                throw OpenAICompatibleConnectionTestError.missingModel
            }

            recoveryAPIKeyStored = true
            config.transcription.provider = .openAICompatible
            recoveryMessage = L10n.text(
                "OpenAI-Compatible Recovery is active for dictation ASR. AI Polish still uses ChatGPT Auth."
            )
            recoveryMessageIsError = false
        } catch {
            recoveryMessage = error.localizedDescription
            recoveryMessageIsError = true
            recoveryAPIKeyStored =
                (try? recoveryCredentialStore.hasAPIKey()) ?? false
        }
    }

    private func switchBackToChatGPT() {
        config.transcription.provider = .chatGPTManagedAuth
        recoveryMessage = L10n.text(
            "Dictation switched back to the ChatGPT account route. The Recovery API key remains stored in Keychain until you remove it."
        )
        recoveryMessageIsError = false
    }

    private var providerPolicyStatusColor: Color {
        switch providerPolicySnapshot.state {
        case .disabled:
            return .red
        case .refreshFailed:
            return .orange
        case .unconfigured, .ready:
            return .secondary
        }
    }

    private func checkForSoftwareUpdates() {
        switch onCheckForUpdates() {
        case .success:
            softwareUpdateMessage = L10n.text("Checking for updates…")
            softwareUpdateMessageIsError = false
        case .failure(let error):
            softwareUpdateMessage = error.localizedDescription
            softwareUpdateMessageIsError = true
        }
    }

    private func setAutomaticUpdateChecks(_ enabled: Bool) {
        switch onSetAutomaticallyChecksForUpdates(enabled) {
        case .success(let snapshot):
            softwareUpdateSnapshot = snapshot
            softwareUpdateMessage = enabled
                ? L10n.text("Automatic update checks are enabled.")
                : L10n.text("Automatic update checks are disabled.")
            softwareUpdateMessageIsError = false
        case .failure(let error):
            softwareUpdateMessage = error.localizedDescription
            softwareUpdateMessageIsError = true
        }
    }

    private func exportProductMetrics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = ProductMetricsExporter
            .suggestedFileName()
        panel.title = L10n.text("Export Product Metrics")
        panel.prompt = L10n.text("Export")

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        switch onExportProductMetrics(destinationURL) {
        case .success(let reportURL):
            productMetricsExportMessage = L10n.format(
                "Saved product metrics report as %@.",
                reportURL.lastPathComponent
            )
            productMetricsExportMessageIsError = false
            NSWorkspace.shared.activateFileViewerSelecting([reportURL])
        case .failure(let error):
            productMetricsExportMessage = error.localizedDescription
            productMetricsExportMessageIsError = true
        }
    }

    private func exportSupportDiagnostics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = SupportDiagnosticsExporter
            .suggestedFileName()
        panel.title = L10n.text("Export Support Diagnostics")
        panel.prompt = L10n.text("Export")

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        switch onExportSupportDiagnostics(destinationURL) {
        case .success(let archiveURL):
            diagnosticsExportMessage = L10n.format(
                "Saved redacted diagnostics as %@.",
                archiveURL.lastPathComponent
            )
            diagnosticsExportMessageIsError = false
            NSWorkspace.shared.activateFileViewerSelecting([archiveURL])
        case .failure(let error):
            diagnosticsExportMessage = error.localizedDescription
            diagnosticsExportMessageIsError = true
        }
    }

    private func showThirdPartyLicenses() {
        do {
            thirdPartyLicenseDocuments =
                try ThirdPartyLicenseCatalog.load()
            thirdPartyLicenseMessage = nil
            thirdPartyLicenseMessageIsError = false
            showsThirdPartyLicenses = true
        } catch {
            thirdPartyLicenseDocuments = []
            thirdPartyLicenseMessage = error.localizedDescription
            thirdPartyLicenseMessageIsError = true
            NSSound.beep()
        }
    }

    private func routeRow(title: String, value: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(L10n.text(title))
                .font(.system(size: 12, weight: .medium))
                .frame(width: 90, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(value))
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(9)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var aiPolishCard: some View {
        settingsCard(title: "AI Polish") {
            VStack(alignment: .leading, spacing: 12) {
                if !licenseSnapshot.allows(.voiceModes) {
                    HStack(alignment: .center, spacing: 10) {
                        Label(
                            L10n.text("Voice Modes require OpenWhisper Pro"),
                            systemImage: "lock.fill"
                        )
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                        Spacer()
                        Button(L10n.text("Manage License")) {
                            selectedSection = .account
                        }
                        .buttonStyle(.bordered)
                    }
                }

                voiceModeSection
                    .disabled(
                        !licenseSnapshot.allows(.voiceModes)
                    )

                Divider()

                Picker(L10n.text("Mode"), selection: $config.transcription.textPolish.mode) {
                    Text(L10n.text("Auto")).tag(TextPolishMode.automaticWhenKeyAvailable)
                    Text(L10n.text("Always rewrite")).tag(TextPolishMode.always)
                    Text(L10n.text("Off")).tag(TextPolishMode.disabled)
                }
                .pickerStyle(.segmented)

                Text(
                    L10n.text(
                        "Auto skips short, low-complexity dictation and rewrites only when corrections, structure, translation, email, or longer input justify the extra latency."
                    )
                )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Toggle(L10n.text("Show estimates"), isOn: $config.transcription.textPolish.showCostEstimates)
                    if let textPolishMessage {
                        Text(textPolishMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(textPolishMessageIsError ? .red : .secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(L10n.text("Test Connection")) {
                        testTextPolishSelection()
                    }
                    .buttonStyle(.bordered)
                }

                polishStatusSection
                historySection(
                    title: "Recent Polish History",
                    textSource: .polish
                )
            }
        }
    }

    private var voiceModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.text("Voice Modes"))
                    .font(.system(size: 13, weight: .semibold))
                Text(
                    licenseSnapshot.state == .preview
                        ? L10n.text("Pro Preview")
                        : L10n.text("Pro")
                )
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Color(nsColor: .controlBackgroundColor)
                    )
                    .clipShape(Capsule())
                Spacer()
            }

            Text(
                L10n.text(
                    "Choose a default writing shape and optionally override it for exact macOS bundle identifiers. OpenWhisper uses only the app name and bundle identifier—not window or document content—to select a mode."
                )
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            LabeledContent(L10n.text("Default Voice Mode")) {
                Picker(
                    L10n.text("Default Voice Mode"),
                    selection: $config.transcription.voiceModes.defaultMode
                ) {
                    ForEach(DictationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
            }

            Text(config.transcription.voiceModes.defaultMode.caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if config.transcription.voiceModes.requiresTextPolish,
               config.transcription.textPolish.mode == .disabled
            {
                Label(
                    L10n.text(
                        "This Voice Mode needs AI Polish. Turn rewrite mode to Auto or Always rewrite to apply it."
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
            } else if config.transcription.voiceModes.requiresTextPolish,
                      authSnapshot.state != .ready
            {
                Label(
                    L10n.text(
                        "Reply, Email, Agent Plan, Code Prompt, and Translate need a connected ChatGPT account for AI Polish. Direct dictation and transcription recovery still work without it."
                    ),
                    systemImage: "person.crop.circle.badge.exclamationmark"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("Application Rules"))
                    .font(.system(size: 12, weight: .semibold))

                HStack(spacing: 8) {
                    Button(L10n.text("Choose App…")) {
                        chooseVoiceModeApplication()
                    }
                    .buttonStyle(.bordered)

                    Text(
                        L10n.text(
                            "Choose an installed app or enter its exact bundle identifier."
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    TextField(
                        L10n.text("App name (optional)"),
                        text: $editingVoiceModeAppName
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 150)

                    TextField(
                        L10n.text("Bundle identifier"),
                        text: $editingVoiceModeBundleIdentifier,
                        prompt: Text("com.apple.Notes")
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                }

                HStack(spacing: 8) {
                    Picker(
                        L10n.text("Voice Mode"),
                        selection: $editingVoiceMode
                    ) {
                        ForEach(DictationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .frame(width: 210)

                    Button(
                        L10n.text(
                            editingVoiceModeRuleID == nil
                                ? "Add Rule"
                                : "Save Rule"
                        )
                    ) {
                        saveVoiceModeRule()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        editingVoiceModeBundleIdentifier
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty
                    )

                    if editingVoiceModeRuleID != nil {
                        Button(L10n.text("Cancel")) {
                            resetVoiceModeRuleEditor()
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()
                }

                if let voiceModeMessage {
                    Text(voiceModeMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(
                            voiceModeMessageIsError ? .red : .secondary
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }

                if config.transcription.voiceModes.applicationRules.isEmpty {
                    Text(
                        L10n.text(
                            "No application rules. The default Voice Mode applies everywhere."
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                } else {
                    VStack(spacing: 6) {
                        ForEach(
                            config.transcription.voiceModes.applicationRules
                        ) { rule in
                            voiceModeRuleRow(rule)
                        }
                    }
                }
            }
        }
    }

    private func voiceModeRuleRow(
        _ rule: AppModeRule
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle(
                L10n.format(
                    "Enable Voice Mode rule for %@",
                    rule.appName ?? rule.bundleIdentifier
                ),
                isOn: Binding(
                    get: { rule.isEnabled },
                    set: { isEnabled in
                        updateVoiceModeRule(rule.id) {
                            $0.isEnabled = isEnabled
                        }
                    }
                )
            )
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.appName ?? rule.bundleIdentifier)
                    .font(.system(size: 12, weight: .medium))
                Text(rule.bundleIdentifier)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(rule.mode.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                .frame(width: 100, alignment: .trailing)

            Button {
                startEditingVoiceModeRule(rule)
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n.text("Edit"))
            .accessibilityLabel(
                L10n.format(
                    "Edit Voice Mode rule for %@",
                    rule.appName ?? rule.bundleIdentifier
                )
            )

            Button(role: .destructive) {
                config.transcription.voiceModes.remove(id: rule.id)
                if editingVoiceModeRuleID == rule.id {
                    resetVoiceModeRuleEditor()
                }
                voiceModeMessage = L10n.text(
                    "Application Voice Mode rule removed."
                )
                voiceModeMessageIsError = false
            } label: {
                Image(systemName: "trash")
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n.text("Delete"))
            .accessibilityLabel(
                L10n.format(
                    "Delete Voice Mode rule for %@",
                    rule.appName ?? rule.bundleIdentifier
                )
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func saveVoiceModeRule() {
        do {
            let existingRule = editingVoiceModeRuleID.flatMap { id in
                config.transcription.voiceModes.applicationRules.first {
                    $0.id == id
                }
            }
            let rule = try AppModeRule.validated(
                id: existingRule?.id ?? UUID(),
                appName: editingVoiceModeAppName,
                bundleIdentifier: editingVoiceModeBundleIdentifier,
                mode: editingVoiceMode,
                isEnabled: existingRule?.isEnabled ?? true
            )
            config.transcription.voiceModes.upsert(rule)
            voiceModeMessage = L10n.format(
                "Voice Mode rule saved for %@.",
                rule.appName ?? rule.bundleIdentifier
            )
            voiceModeMessageIsError = false
            resetVoiceModeRuleEditor(clearMessage: false)
        } catch {
            voiceModeMessage = error.localizedDescription
            voiceModeMessageIsError = true
            NSSound.beep()
        }
    }

    private func chooseVoiceModeApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(
            fileURLWithPath: "/Applications",
            isDirectory: true
        )
        panel.title = L10n.text("Choose an Application")
        panel.message = L10n.text(
            "OpenWhisper stores only the selected app name and bundle identifier for this Voice Mode rule."
        )
        panel.prompt = L10n.text("Choose App")

        guard
            panel.runModal() == .OK,
            let appURL = panel.url,
            let bundle = Bundle(url: appURL),
            let bundleIdentifier = bundle.bundleIdentifier,
            AppModeRule.isValidBundleIdentifier(bundleIdentifier)
        else {
            if panel.url != nil {
                voiceModeMessage = L10n.text(
                    "The selected application does not expose a valid bundle identifier."
                )
                voiceModeMessageIsError = true
                NSSound.beep()
            }
            return
        }

        editingVoiceModeBundleIdentifier =
            AppModeRule.normalizedBundleIdentifier(bundleIdentifier)
        editingVoiceModeAppName = (
            bundle.object(
                forInfoDictionaryKey: "CFBundleDisplayName"
            ) as? String
        ) ?? (
            bundle.object(
                forInfoDictionaryKey: "CFBundleName"
            ) as? String
        ) ?? appURL.deletingPathExtension().lastPathComponent
        voiceModeMessage = nil
        voiceModeMessageIsError = false
    }

    private func startEditingVoiceModeRule(_ rule: AppModeRule) {
        editingVoiceModeRuleID = rule.id
        editingVoiceModeAppName = rule.appName ?? ""
        editingVoiceModeBundleIdentifier = rule.bundleIdentifier
        editingVoiceMode = rule.mode
        voiceModeMessage = nil
        voiceModeMessageIsError = false
    }

    private func resetVoiceModeRuleEditor(
        clearMessage: Bool = true
    ) {
        editingVoiceModeRuleID = nil
        editingVoiceModeAppName = ""
        editingVoiceModeBundleIdentifier = ""
        editingVoiceMode = .reply
        if clearMessage {
            voiceModeMessage = nil
            voiceModeMessageIsError = false
        }
    }

    private func updateVoiceModeRule(
        _ id: UUID,
        update: (inout AppModeRule) -> Void
    ) {
        guard
            var rule = config.transcription.voiceModes
                .applicationRules.first(where: { $0.id == id })
        else {
            return
        }
        update(&rule)
        config.transcription.voiceModes.upsert(rule)
    }

    private var recoveryHistoryCard: some View {
        settingsCard(title: "Recent Records") {
            VStack(alignment: .leading, spacing: 12) {
                Picker(L10n.text("Record type"), selection: $selectedRecoveryKind) {
                    Text(L10n.text("Original audio")).tag(RecoveryHistoryKind.audio)
                    Text(L10n.text("ASR transcript")).tag(RecoveryHistoryKind.asr)
                    Text(L10n.text("AI polish result")).tag(RecoveryHistoryKind.polish)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text(L10n.text("Latest 10"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.text("Refresh")) {
                        refreshRecoveryHistory()
                    }
                    .buttonStyle(.bordered)
                }

                if recentRecoveryItems.isEmpty {
                    Text(L10n.text("No recoverable records yet."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(recentRecoveryItems) { item in
                            recoveryHistoryRow(item)
                        }
                    }
                }
            }
        }
    }

    private func recoveryHistoryRow(_ item: RecoveryHistoryPreview) -> some View {
        let isCopied = copiedHistoryItemID == item.id

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.target)
                        .font(.system(size: 11, weight: .medium))
                    Text(TextDeliveryStatus.localizedLabel(for: item.outcome))
                        .font(.system(size: 10))
                        .foregroundStyle(item.outcome == "error" ? .red : .secondary)
                    Text(item.timestamp.formatted(date: .numeric, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Text(item.text)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                if let errorMessage = item.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if isCopied {
                    Text(L10n.text("Copied"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }

                Button {
                    copyRecoveryHistoryItem(item)
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .frame(width: 12, height: 12)
                }
                .help(L10n.text("Copy"))
                .accessibilityLabel(L10n.text("Copy"))
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    retryRecoveryHistoryItem(item)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 12, height: 12)
                }
                .help(L10n.text("Retry"))
                .accessibilityLabel(L10n.text("Retry"))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(width: 132, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func copyRecoveryHistoryItem(_ item: RecoveryHistoryPreview) {
        NSPasteboard.general.clearContents()
        switch item.copyKind {
        case .text:
            NSPasteboard.general.setString(item.copyText, forType: .string)
        case .audioFile:
            guard let record = recentRecoveryRecords.first(where: { $0.id == item.recordID }) else {
                NSSound.beep()
                return
            }
            switch onResolveRecoveryAudioURL(record) {
            case .success(let audioURL):
                NSPasteboard.general.writeObjects([audioURL as NSURL])
            case .failure(let error):
                terminologyImportMessage = error.localizedDescription
                terminologyImportIsError = true
                NSSound.beep()
                return
            }
        }

        withAnimation(.easeOut(duration: 0.12)) {
            copiedHistoryItemID = item.id
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard copiedHistoryItemID == item.id else {
                return
            }
            withAnimation(.easeOut(duration: 0.18)) {
                copiedHistoryItemID = nil
            }
        }
    }

    private func retryRecoveryHistoryItem(_ item: RecoveryHistoryPreview) {
        guard let record = recentRecoveryRecords.first(where: { $0.id == item.recordID }) else {
            return
        }
        onRetryRecoveryRecord(record)
    }

    private var polishStatusSection: some View {
        let usage = textPolishUsage[.chatGPTAuth] ?? TextPolishUsage()
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: authSnapshot.state == .ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(authSnapshot.state == .ready ? .green : .orange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("ChatGPT Auth rewrite"))
                    .font(.system(size: 12, weight: .semibold))
                Text(
                    authSnapshot.state == .ready
                        ? L10n.format(
                            "Ready with %@.",
                            config.transcription.textPolish.chatGPTResponseModel
                        )
                        : authSnapshot.detail
                )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(
                    L10n.format(
                        "Usage: %ld attempts, %ld succeeded, %ld failed, %ld skipped, %ld input tokens, %ld output tokens.",
                        usage.attempts,
                        usage.succeeded,
                        usage.failed,
                        usage.skipped,
                        usage.inputTokens,
                        usage.outputTokens
                    )
                )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func historySection(
        title: String,
        textSource: TranscriptionHistoryTextSource
    ) -> some View {
        let items = textSource == .dictation ? recentDictationHistoryItems : recentPolishHistoryItems

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text(title))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(L10n.text("Refresh")) {
                    refreshRecentHistory()
                }
                .buttonStyle(.bordered)
            }

            if items.isEmpty {
                Text(L10n.text("No recent transcripts yet."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { item in
                        recentHistoryRow(item)
                    }
                }
            }
        }
    }

    private func recentHistoryRow(_ item: TranscriptionHistoryPreview) -> some View {
        let isCopied = copiedHistoryItemID == item.id

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.target)
                        .font(.system(size: 11, weight: .medium))
                    Text(item.sourceLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(TextDeliveryStatus.localizedLabel(for: item.outcome))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(item.timestamp.formatted(date: .numeric, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Text(item.text)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if isCopied {
                    Text(L10n.text("Copied"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }

                Button {
                    copyRecentHistoryItem(item)
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .frame(width: 12, height: 12)
                }
                .help(L10n.text(isCopied ? "Copied" : "Copy transcript"))
                .accessibilityLabel(L10n.text(isCopied ? "Copied transcript" : "Copy transcript"))
                .disabled(item.copyText.isEmpty)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(width: 74, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func copyRecentHistoryItem(_ item: TranscriptionHistoryPreview) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.copyText, forType: .string)

        withAnimation(.easeOut(duration: 0.12)) {
            copiedHistoryItemID = item.id
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard copiedHistoryItemID == item.id else {
                return
            }
            withAnimation(.easeOut(duration: 0.18)) {
                copiedHistoryItemID = nil
            }
        }
    }

    private func testTextPolishSelection() {
        let selected = TextPolishProviderSelector().selectProvider(
            config: config.transcription.textPolish,
            chatGPTAuthAvailable: authSnapshot.state == .ready
        )
        if let selected {
            let model = config.transcription.textPolish.chatGPTResponseModel
            textPolishMessage = L10n.format("Ready: %@ / %@.", selected.id.title, model)
            textPolishMessageIsError = false
        } else {
            textPolishMessage = L10n.text("ChatGPT Auth is not ready. Connect ChatGPT first.")
            textPolishMessageIsError = true
        }
    }

    private var terminologyDictionarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("Terminology Dictionary"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(L10n.text("Terms guide transcription. Corrections deterministically replace common mistakes after transcription."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(L10n.text("Enabled"), isOn: $config.transcription.terminology.enabled)
                    .toggleStyle(.switch)
            }

            terminologySummaryRow
            terminologyToolbar
            terminologyEditor

            if let terminologyImportMessage {
                Text(terminologyImportMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(terminologyImportIsError ? .red : .secondary)
            }

            terminologyList
        }
    }

    private var chatGPTAccountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("ChatGPT Account"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(authSnapshot.userEmail ?? authSnapshot.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(browserBridgeSnapshot.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    statusPill(for: authSnapshot.state)
                    browserBridgePill(for: browserBridgeSnapshot.state)
                }
            }

            HStack(spacing: 10) {
                Button(L10n.text(isConnectingBrowserLogin ? "Waiting for Browser" : "Use Browser Login")) {
                    connectViaBrowser()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConnectingBrowserLogin || config.transcription.provider == .openAICompatible)

                Button(L10n.text("Refresh Session")) {
                    Task {
                        _ = try? await authManager.refreshAccessToken()
                        await MainActor.run {
                            authSnapshot = authManager.authSnapshot()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(config.transcription.provider == .openAICompatible)

                Button(L10n.text("Sign out")) {
                    do {
                        try authManager.signOut()
                        authSnapshot = authManager.authSnapshot()
                    } catch {
                        terminologyImportMessage = error.localizedDescription
                        terminologyImportIsError = true
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private func connectViaBrowser() {
        isConnectingBrowserLogin = true
        browserBridgeSnapshot = authManager.browserBridgeSnapshot()
        Task {
            do {
                _ = try await authManager.connectViaDefaultBrowser()
                await MainActor.run {
                    authSnapshot = authManager.authSnapshot()
                    browserBridgeSnapshot = authManager.browserBridgeSnapshot()
                    isConnectingBrowserLogin = false
                    terminologyImportMessage = L10n.text(
                        "Browser login connected. OpenWhisper saved the ChatGPT session locally."
                    )
                    terminologyImportIsError = false
                }
            } catch {
                await MainActor.run {
                    authSnapshot = authManager.authSnapshot()
                    browserBridgeSnapshot = authManager.browserBridgeSnapshot()
                    isConnectingBrowserLogin = false
                    terminologyImportMessage = error.localizedDescription
                    terminologyImportIsError = true
                }
            }
        }
    }

    private func statusPill(for state: ChatGPTAuthState) -> some View {
        let label: String
        let color: Color
        switch state {
        case .ready:
            label = L10n.text("Signed In")
            color = .green
        case .signedOut:
            label = L10n.text("Signed Out")
            color = .orange
        case .expired:
            label = L10n.text("Expired")
            color = .orange
        case .unavailable:
            label = L10n.text("Unavailable")
            color = .red
        }

        return Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(Capsule())
    }

    private func browserBridgePill(for state: BrowserBridgeState) -> some View {
        let label: String
        let color: Color
        switch state {
        case .available:
            label = L10n.text("OAuth Ready")
            color = .secondary
        case .waiting:
            label = L10n.text("Waiting")
            color = .orange
        case .connected:
            label = L10n.text("Connected")
            color = .green
        case .failed:
            label = L10n.text("Failed")
            color = .red
        }

        return Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(Capsule())
    }

    private var terminologySummaryRow: some View {
        let entries = config.transcription.terminology.entries
        let termCount = entries.filter { $0.type == .term }.count
        let correctionCount = entries.filter { $0.type == .correction }.count

        return HStack(spacing: 8) {
            terminologyCountBadge(title: "Terms", count: termCount, color: .accentColor)
            terminologyCountBadge(title: "Corrections", count: correctionCount, color: .orange)
            Spacer()
            Text(L10n.text("Import a text or CSV dictionary, then add custom terms or corrections here."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func terminologyCountBadge(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(L10n.text(title))
            Text("\(count)")
                .fontWeight(.semibold)
        }
        .font(.system(size: 11))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(Capsule())
    }

    private var terminologyToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField(
                    L10n.text("Search terminology"),
                    text: $terminologySearchText
                )
                .textFieldStyle(.roundedBorder)

                Picker("", selection: $terminologyFilter) {
                    ForEach(TerminologyFilter.allCases) { filter in
                        Text(L10n.text(filter.rawValue)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }

            HStack {
                Text(
                    L10n.format(
                        "%ld matching entries",
                        filteredTerminologyEntries.count
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("Import Dictionary...")) {
                    importTerminologyDictionary()
                }
            }
        }
    }

    private var terminologyEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text(editingTerminologyID == nil ? "Add Entry" : "Edit Entry"))
                .font(.system(size: 12, weight: .semibold))

            HStack {
                Picker("", selection: terminologyTypeBinding) {
                    Text(L10n.text("Term")).tag(TerminologyEntryType.term)
                    Text(L10n.text("Correction")).tag(TerminologyEntryType.correction)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                TextField(
                    L10n.text(editingTerminologyType == .term ? "Term" : "Wrong text"),
                    text: $editingOriginal
                )

                if editingTerminologyType == .correction {
                    TextField(L10n.text("Correct text"), text: $editingReplacement)
                }

                if editingTerminologyID != nil {
                    Button(L10n.text("Cancel")) {
                        clearTerminologyEditor()
                    }
                }
                Button(L10n.text(editingTerminologyID == nil ? "Add" : "Save Entry")) {
                    saveTerminologyEditor()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSaveTerminologyEntry)
            }
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var terminologyList: some View {
        Group {
            if filteredTerminologyEntries.isEmpty {
                Text(
                    L10n.text(
                        terminologySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "No dictionary entries for this filter."
                            : "No terminology entries match your search."
                    )
                )
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(filteredTerminologyEntries) { entry in
                        terminologyEntryRow(entry: entry)
                    }
                }
            }
        }
    }

    private func terminologyEntryRow(entry: TerminologyEntry) -> some View {
        HStack(spacing: 8) {
            Text(L10n.text(entry.type.rawValue.capitalized))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(entry.type == .correction ? .orange : .accentColor)
                .frame(width: 74, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                if entry.type == .correction {
                    Text("\(entry.original) -> \(entry.replacement ?? "")")
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Text(entry.original)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(
                    "\(entry.source) · \(L10n.text(entry.isEnabled ? "enabled" : "disabled"))"
                )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: {
                    config.transcription.terminology.entries
                        .first(where: { $0.id == entry.id })?
                        .isEnabled ?? false
                },
                set: { isEnabled in
                    updateTerminologyEntry(id: entry.id) {
                        $0.isEnabled = isEnabled
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            Button(L10n.text("Edit")) {
                editTerminologyEntry(id: entry.id)
            }
            .buttonStyle(.borderless)

            Button(L10n.text("Delete")) {
                deleteTerminologyEntry(id: entry.id)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func editTerminologyEntry(id: UUID) {
        guard let entry = config.transcription.terminology.entries.first(where: { $0.id == id }) else {
            terminologyImportMessage = L10n.text(
                "That terminology entry changed before it could be edited. Refresh your search and try again."
            )
            terminologyImportIsError = true
            clearTerminologyEditor()
            return
        }
        editingTerminologyID = entry.id
        editingTerminologyType = entry.type
        editingOriginal = entry.original
        editingReplacement = entry.replacement ?? ""
    }

    private func saveTerminologyEditor() {
        let original = editingOriginal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else {
            return
        }

        let replacement = editingTerminologyType == .correction
            ? editingReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        if let editingTerminologyID {
            guard let index = config.transcription.terminology.entries.firstIndex(where: {
                $0.id == editingTerminologyID
            }) else {
                terminologyImportMessage = L10n.text(
                    "That terminology entry changed before it could be saved. Refresh your search and try again."
                )
                terminologyImportIsError = true
                clearTerminologyEditor()
                return
            }
            var entry = config.transcription.terminology.entries[index]
            entry.type = editingTerminologyType
            entry.original = original
            entry.replacement = replacement
            config.transcription.terminology.entries[index] = entry
        } else {
            config.transcription.terminology.entries.append(
                TerminologyEntry(
                    type: editingTerminologyType,
                    original: original,
                    replacement: replacement,
                    aliases: [],
                    isEnabled: true,
                    source: "user",
                    usageCount: 0,
                    createdAt: ISO8601DateFormatter().string(from: Date())
                )
            )
        }

        clearTerminologyEditor()
    }

    private func clearTerminologyEditor() {
        editingTerminologyID = nil
        editingTerminologyType = .term
        editingOriginal = ""
        editingReplacement = ""
    }

    private func updateTerminologyEntry(
        id: UUID,
        update: (inout TerminologyEntry) -> Void
    ) {
        guard let index = config.transcription.terminology.entries.firstIndex(where: {
            $0.id == id
        }) else {
            return
        }
        update(&config.transcription.terminology.entries[index])
    }

    private func deleteTerminologyEntry(id: UUID) {
        config.transcription.terminology.entries.removeAll { $0.id == id }
        if editingTerminologyID == id {
            clearTerminologyEditor()
        }
    }

    private var canSaveTerminologyEntry: Bool {
        let original = editingOriginal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else {
            return false
        }

        if editingTerminologyType == .correction {
            return !editingReplacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return true
    }

    private func importTerminologyDictionary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .commaSeparatedText]
        panel.message = L10n.text("Choose a plain text or CSV terminology dictionary.")

        guard panel.runModal() == .OK, let fileURL = panel.url else {
            return
        }

        switch onImportTerminologyDictionary(config, fileURL) {
        case .success(let updatedConfig):
            config = updatedConfig
            terminologyImportMessage = Self.terminologyStatusMessage(for: updatedConfig)
            terminologyImportIsError = false
            terminologyFilter = .all
        case .failure(let error):
            terminologyImportMessage = error.localizedDescription
            terminologyImportIsError = true
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
                .font(.system(size: 12))
        } header: {
            Text(L10n.text(title))
        }
    }

    private func setupRow(title: String, status: SetupStatus) -> some View {
        setupRow(title: title, status: status) {
            EmptyView()
        }
    }

    private func compactSetupTile(title: String, status: SetupStatus) -> some View {
        HStack(spacing: 8) {
            Image(systemName: status.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(status.isReady ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(title))
                    .font(.system(size: 12, weight: .semibold))
                Text(status.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func setupRow<Actions: View>(
        title: String,
        status: SetupStatus,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: status.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(status.isReady ? .green : .orange)
                .font(.system(size: 14))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(title))
                    .font(.system(size: 12, weight: .semibold))
                Text(status.title)
                    .font(.system(size: 12, weight: .medium))
                Text(status.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                actions()
            }
        }
    }

    private var chatGPTSetupActions: some View {
        HStack(spacing: 10) {
            if authSnapshot.state == .ready {
                Button(L10n.text("Use Browser Login")) {
                    connectViaBrowser()
                }
                .buttonStyle(.bordered)
            } else {
                Button(L10n.text("Use Browser Login")) {
                    connectViaBrowser()
                }
                .buttonStyle(.borderedProminent)
            }

            Button(L10n.text("Refresh")) {
                Task {
                    _ = try? await authManager.refreshAccessToken()
                    await MainActor.run {
                        authSnapshot = authManager.authSnapshot()
                    }
                }
            }
            .buttonStyle(.bordered)
            .disabled(config.transcription.provider == .openAICompatible)

            if authSnapshot.state == .ready || authSnapshot.state == .expired {
                Button(L10n.text("Sign out")) {
                    do {
                        try authManager.signOut()
                        authSnapshot = authManager.authSnapshot()
                    } catch {
                        terminologyImportMessage = error.localizedDescription
                        terminologyImportIsError = true
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 6)
    }

    private var terminologyTypeBinding: Binding<TerminologyEntryType> {
        Binding(
            get: { editingTerminologyType },
            set: { editingTerminologyType = $0 }
        )
    }

    @ViewBuilder
    private func permissionSetupSection(
        title: String,
        status: SetupStatus,
        detail: String?,
        actions: [PermissionRepairAction]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            setupRow(title: title, status: status)

            if let detail, !detail.isEmpty, status.isReady == false {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !actions.isEmpty {
                HStack(spacing: 10) {
                    ForEach(actions) { action in
                        repairActionButton(action)
                    }
                }
            }
        }
    }

    @MainActor
    private func performRepairAction(_ action: PermissionRepairAction) {
        switch action.kind {
        case .requestMicrophoneAccess:
            requestMicrophoneAccess()
        case .guidedAccessibilityAccess:
            AccessibilityPermission.guideAccess()
        case .openSettings(let destination):
            _ = destination.open()
        case .refreshStatus:
            permissionMessage = nil
            permissionStatusMonitor.refresh()
        }
    }

    @MainActor
    private func requestMicrophoneAccess() {
        guard !isRequestingMicrophoneAccess else {
            return
        }

        isRequestingMicrophoneAccess = true
        permissionMessage = nil

        Task { @MainActor in
            let result = await permissionStatusMonitor.requestMicrophoneAccess(
                using: onRequestMicrophoneAccess
            )
            isRequestingMicrophoneAccess = false

            switch result {
            case .success:
                switch permissionStatusMonitor.snapshot.microphone {
                case .granted:
                    permissionMessage = L10n.text(
                        "Microphone access is ready."
                    )
                    permissionMessageIsError = false
                case .undetermined:
                    permissionMessage = L10n.text(
                        "OpenWhisper still cannot confirm microphone access. Click Refresh Status or reopen the app."
                    )
                    permissionMessageIsError = true
                case .denied:
                    permissionMessage = L10n.text(
                        "Microphone access was previously denied. Open Privacy & Security > Microphone to re-enable it."
                    )
                    permissionMessageIsError = true
                }
            case .failure(let error):
                permissionMessage = error.localizedDescription
                permissionMessageIsError = true
            }
        }
    }

    private func repairActionIsDisabled(
        _ action: PermissionRepairAction
    ) -> Bool {
        action.kind == .requestMicrophoneAccess
            && isRequestingMicrophoneAccess
    }

    @ViewBuilder
    private func repairActionButton(_ action: PermissionRepairAction) -> some View {
        switch action.prominence {
        case .primary:
            Button(L10n.text(action.title)) {
                performRepairAction(action)
            }
            .buttonStyle(.borderedProminent)
            .disabled(repairActionIsDisabled(action))
        case .secondary:
            Button(L10n.text(action.title)) {
                performRepairAction(action)
            }
            .buttonStyle(.bordered)
            .disabled(repairActionIsDisabled(action))
        case .utility:
            Button(L10n.text(action.title)) {
                performRepairAction(action)
            }
            .buttonStyle(.borderless)
            .disabled(repairActionIsDisabled(action))
        }
    }
}

private struct SetupStatus {
    let title: String
    let subtitle: String
    var isReady: Bool = true
}
