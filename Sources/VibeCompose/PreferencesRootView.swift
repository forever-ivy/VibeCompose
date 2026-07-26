import AppKit
import AVFoundation
import ApplicationServices
import SwiftUI

private enum SettingsLayoutMetrics {
    /// Outer width of the source-list glass rail (content + row padding).
    static let sidebarWidth: CGFloat = 236
    /// Music / App Store floating rail: equal float gutters around the glass
    /// card. Transparent titlebar + `ignoresSafeArea(.top)` lets the system
    /// traffic lights rest on the top-leading of this card in their standard
    /// slot — never re-centered over the rail width.
    static let sidebarInsetLeading: CGFloat = 10
    static let sidebarInsetTop: CGFloat = 10
    static let sidebarInsetBottom: CGFloat = 10
    /// Gap between the glass rail and the detail column.
    static let sidebarToDetailGap: CGFloat = 10
    /// Interior top pad so the first section header clears the system traffic
    /// lights that rest on the glass card (14pt widgets + titlebar chrome).
    static let sidebarContentTopPadding: CGFloat = 44
    static let sidebarRowVerticalPadding: CGFloat = 5
    static let sidebarRowOuterPadding: CGFloat = 10
    static let sidebarRowInnerPadding: CGFloat = 10
    static let sidebarRowSpacing: CGFloat = 2
    static let sidebarRowCornerRadius: CGFloat = 8
    static let sidebarSectionSpacing: CGFloat = 18
    static let sidebarHeaderRowSpacing: CGFloat = 6
    static let detailHorizontalPadding: CGFloat = 40
    static let detailTopPadding: CGFloat = 32
    /// Embedded library destinations render their own in-content header
    /// (`VibeComposePaneHeader`), so the shell only clears the traffic lights.
    static let embeddedTopPadding: CGFloat = 6

    /// Leading column reserved for the glass rail + gutters.
    static var sidebarColumnWidth: CGFloat {
        sidebarInsetLeading + sidebarWidth + sidebarToDetailGap
    }
}

private struct SettingsWindowKeyTracker: NSViewRepresentable {
    @Binding var isKeyWindow: Bool
    var onNeedsGlassRematerialize: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isKeyWindow: $isKeyWindow,
            onNeedsGlassRematerialize: onNeedsGlassRematerialize
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onNeedsGlassRematerialize = onNeedsGlassRematerialize
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        @Binding var isKeyWindow: Bool
        var onNeedsGlassRematerialize: () -> Void
        private weak var trackedWindow: NSWindow?
        private var becomeKeyObserver: NSObjectProtocol?
        private var resignKeyObserver: NSObjectProtocol?
        private var deminiaturizeObserver: NSObjectProtocol?
        private var attachAttempts = 0
        /// Skip the first become-key after attach — that is initial open, not a restore.
        private var hasSyncedOnce = false

        init(
            isKeyWindow: Binding<Bool>,
            onNeedsGlassRematerialize: @escaping () -> Void
        ) {
            _isKeyWindow = isKeyWindow
            self.onNeedsGlassRematerialize = onNeedsGlassRematerialize
        }

        func attach(to view: NSView) {
            if let window = view.window {
                track(window)
                return
            }
            guard attachAttempts < 8 else { return }
            attachAttempts += 1
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                self.attach(to: view)
            }
        }

        private func track(_ window: NSWindow) {
            guard trackedWindow !== window else {
                sync(from: window)
                return
            }
            detachObservers()
            trackedWindow = window
            let center = NotificationCenter.default
            becomeKeyObserver = center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let wasKey = self.isKeyWindow
                    self.isKeyWindow = true
                    // Rematerialize glass when key is restored after resign —
                    // miniaturize resigns key and can leave a stale sample.
                    if self.hasSyncedOnce, !wasKey {
                        self.requestGlassRematerialize()
                    }
                }
            }
            resignKeyObserver = center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isKeyWindow = false
                }
            }
            deminiaturizeObserver = center.addObserver(
                forName: NSWindow.didDeminiaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.requestGlassRematerialize()
                }
            }
            sync(from: window)
            hasSyncedOnce = true
        }

        private func requestGlassRematerialize() {
            // Defer one turn so AppKit finishes layout after deminiaturize
            // before SwiftUI remounts the glass layer.
            DispatchQueue.main.async { [weak self] in
                self?.onNeedsGlassRematerialize()
            }
        }

        private func sync(from window: NSWindow) {
            let key = window.isKeyWindow
            if isKeyWindow != key {
                isKeyWindow = key
            }
        }

        func detach() {
            detachObservers()
            trackedWindow = nil
        }

        private func detachObservers() {
            let center = NotificationCenter.default
            if let becomeKeyObserver {
                center.removeObserver(becomeKeyObserver)
                self.becomeKeyObserver = nil
            }
            if let resignKeyObserver {
                center.removeObserver(resignKeyObserver)
                self.resignKeyObserver = nil
            }
            if let deminiaturizeObserver {
                center.removeObserver(deminiaturizeObserver)
                self.deminiaturizeObserver = nil
            }
        }
    }
}

/// macOS 26 source-list row: the selection is a translucent glass pill.
/// Brand-blue only while the sidebar itself holds focus *and* the window is
/// key; click the detail pane (or resign key) and the row falls back to gray —
/// same inactive source-list treatment as Finder and System Settings.
private struct SettingsSidebarRowButton: View {
    let pane: SettingsPane
    let isSelected: Bool
    /// True only while the sidebar owns focus inside a key Settings window.
    let selectionIsActive: Bool
    let reduceMotion: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                VibeComposeSidebarSymbol(systemName: pane.icon)
                Text(pane.displayTitle)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(rowForeground)
            .padding(
                .horizontal,
                SettingsLayoutMetrics.sidebarRowInnerPadding
            )
            .padding(
                .vertical,
                SettingsLayoutMetrics.sidebarRowVerticalPadding
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(
            SettingsSidebarRowButtonStyle(
                isSelected: isSelected,
                isHovered: isHovered,
                selectionIsActive: selectionIsActive,
                reduceMotion: reduceMotion
            )
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var rowForeground: Color {
        if isSelected {
            return Color(
                nsColor: selectionIsActive
                    ? VibeComposePalette.sidebarSelectionForeground
                    : VibeComposePalette.sidebarSelectionForegroundInactive
            )
        }
        return .primary
    }
}

private struct SettingsSidebarRowButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isHovered: Bool
    let selectionIsActive: Bool
    let reduceMotion: Bool

    private var rowShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: SettingsLayoutMetrics.sidebarRowCornerRadius,
            style: .continuous
        )
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                ZStack {
                    rowShape.fill(baseFill)
                    // Pointer-down feedback lands instantly, on both the
                    // selected pill and unselected rows.
                    rowShape.fill(
                        Color.primary.opacity(
                            configuration.isPressed ? 0.06 : 0
                        )
                    )
                }
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: isHovered
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.1),
                value: configuration.isPressed
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.14),
                value: selectionIsActive
            )
    }

    private var baseFill: Color {
        if isSelected {
            return Color(
                nsColor: selectionIsActive
                    ? VibeComposePalette.sidebarSelectionBackground
                    : VibeComposePalette.sidebarSelectionBackgroundInactive
            )
        }
        return Color.primary.opacity(isHovered ? 0.05 : 0)
    }
}

private enum SettingsSaveStatus: Equatable {
    case saved
    case failed(String)
}

private extension SettingsPane {
    /// One monochrome outline SF Symbol family for the settings source list.
    var icon: String {
        switch self {
        case .general:
            return "gearshape"
        case .account:
            return "person.crop.circle"
        case .dictation:
            return "mic"
        case .appearance:
            return "paintpalette"
        case .polish:
            return "sparkles"
        case .context:
            return "lock.shield"
        case .terminology:
            return "book.closed"
        case .styleCapsules:
            return "text.book.closed"
        case .paste:
            return "doc.on.clipboard"
        case .privacy:
            return "lock.shield"
        case .advanced:
            return "slider.horizontal.3"
        case .skills:
            return "sparkles"
        case .rules:
            return "list.bullet.rectangle"
        case .history:
            return "clock"
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

struct PreferencesView: View {
    private enum TerminologyFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case terms = "Terms"
        case corrections = "Corrections"

        var id: String { rawValue }
    }

    @State private var config: AppConfig
    @State private var persistedConfig: AppConfig
    @State private var showsAdvancedRecovery: Bool
    @State private var showsOwnAPIConfigurationSheet = false
    @State private var availableDictationModels: [String] = ProductModelCatalog.dictationPresets
    @State private var availablePolishModels: [String] = ProductModelCatalog.rewritePresets
    /// Account (ChatGPT Auth) polish models from `codex/models`, not Own API `/v1/models`.
    @State private var availableAccountPolishModels: [String] = ProductModelCatalog.rewritePresets
    @State private var accountPolishModelsMessage: String?
    @State private var accountPolishModelsMessageIsError = false
    @State private var isLoadingAccountPolishModels = false
    @State private var isDetectingModels = false
    @State private var ownAPIConfigurationTab: OwnAPIConfigurationTab = .recognition
    @State private var polishEndpointDraft: String = ""
    @State private var polishAPIKeyInput = ""
    @State private var polishAPIKeyStored = false
    @State private var polishMessage: String?
    @State private var polishMessageIsError = false
    @State private var isTestingPolishConnection = false
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
    @State private var selectedSection: SettingsPane
    @State private var saveStatus: SettingsSaveStatus = .saved
    @State private var textPolishUsage: [TextPolishProviderID: TextPolishUsage] = [:]
    @State private var textPolishMessage: String?
    @State private var textPolishMessageIsError = false
    @StateObject private var sonnerToasts = SonnerToastCenter()
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
    @State private var recoveryEndpointDraft: String
    @State private var recoveryModelDraft: String
    @State private var recoveryAPIKeyInput = ""
    @State private var recoveryAPIKeyStored: Bool
    @State private var recoveryMessage: String?
    @State private var recoveryMessageIsError = false
    @State private var isTestingRecoveryConnection = false
    @State private var providerPolicySnapshot: ProviderCapabilityPolicySnapshot
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
    @State private var communitySkillInventory:
        CommunitySkillInventory
    /// Bumped when a Skills deep-link must remount SkillLibraryView.
    @State private var skillLibraryRemountID = UUID()
    /// Bumped when live coordinator terminology changes so embedded manager reseeds.
    @State private var terminologyRemountID = UUID()
    /// AppKit-tracked key-window state for source-list active/inactive tint.
    @State private var isSettingsWindowKey = true
    /// True while primary interaction is in the source list (row click / ↑↓).
    /// Clicking the detail pane clears this so the selection goes gray in-app.
    @State private var isSidebarFocused = true
    /// Bumped on deminiaturize / key restore so Liquid Glass remounts cleanly.
    @State private var sidebarGlassMaterializationID = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let authManager: ChatGPTAuthManager
    let onSave: (AppConfig) -> Result<Void, any Error>
    let onImportTerminologyDictionary: (AppConfig, URL) -> Result<AppConfig, any Error>
    let onLoadRecentHistory: @Sendable () async -> [TranscriptionHistoryRecord]
    let onLoadRecoveryHistory: @Sendable () async -> [RecoveryRecord]
    let onResolveRecoveryAudioURL: (RecoveryRecord) -> Result<URL, any Error>
    let onRetryRecoveryRecord: (RecoveryRecord) -> Void
    let onRequestMicrophoneAccess:
        @MainActor @Sendable () async -> Result<Void, any Error>
    let onOpenConfigFolder: () -> Void
    let onExportSupportDiagnostics: (URL) -> Result<URL, any Error>
    let onExportProductMetrics: (URL) -> Result<URL, any Error>
    let providerCapabilityPolicy: any ProviderCapabilityChecking
    let recoveryCredentialStore: any OpenAICompatibleCredentialPersisting
    let polishCredentialStore: any OpenAICompatibleCredentialPersisting = KeychainOpenAICompatibleCredentialStore(
        service: ProductIdentity.polishAPIKeychainService,
        account: "polish"
    )
    let textPolishUsageDirectoryURL: URL?
    let onCheckForUpdates: () -> Result<Void, SoftwareUpdateError>
    let onSetAutomaticallyChecksForUpdates: (Bool) -> Result<SoftwareUpdateSnapshot, SoftwareUpdateError>
    let onDeleteAllData: () -> Result<AppConfig, any Error>
    let onOpenOnboarding: () -> Void
    let onOpenSkillLibrary: () -> Void
    let onOpenTerminology: () -> Void
    let onLoadFullTranscriptionHistory: @Sendable () async -> [TranscriptionHistoryRecord]
    let onLoadFullRecoveryHistory: @Sendable () async -> [RecoveryRecord]
    let onCanUndoTranscriptionRecord: (UUID) -> Bool
    let onUndoTranscriptionRecord: (UUID) async -> SafeUndoOutcome
    let onDeleteTranscriptionRecord: (UUID) -> Result<Void, any Error>
    let onDeleteRecoveryRecord: (UUID) -> Result<Void, any Error>
    let onRunSkillTest: (SkillTestRunRequest) async -> Result<SkillTestRunResult, any Error>
    let onVoiceSampleAction: (SkillVoiceSampleAction) async -> Result<SkillVoiceSampleResult, any Error>
    let onHotkeyCaptureChanged: (Bool) -> Void
    let onPreviewVisualFeedback:
        (
            VisualFeedbackPreview,
            VisualFeedbackConfig
        ) -> Void
    let windowStateStore: SettingsWindowStateStore
    let skillPackageStore:
        SkillPackageStore
    let styleCapsuleStore:
        StyleCapsuleStore
    let localAssetAccessEnabled:
        Bool
    let skillLibraryInitialSection:
        SkillLibrarySection

    init(
        initialConfig: AppConfig,
        authManager: ChatGPTAuthManager,
        onSave: @escaping (AppConfig) -> Result<Void, any Error>,
        onImportTerminologyDictionary: @escaping (AppConfig, URL) -> Result<AppConfig, any Error>,
        onLoadRecentHistory: @escaping @Sendable () async -> [TranscriptionHistoryRecord],
        onLoadRecoveryHistory: @escaping @Sendable () async -> [RecoveryRecord],
        onResolveRecoveryAudioURL: @escaping (RecoveryRecord) -> Result<URL, any Error>,
        onRetryRecoveryRecord: @escaping (RecoveryRecord) -> Void,
        onRequestMicrophoneAccess: @escaping @MainActor @Sendable () async -> Result<Void, any Error>,
        onOpenConfigFolder: @escaping () -> Void,
        onExportSupportDiagnostics: @escaping (URL) -> Result<URL, any Error>,
        onExportProductMetrics: @escaping (URL) -> Result<URL, any Error>,
        providerCapabilityPolicy: any ProviderCapabilityChecking,
        recoveryCredentialStore: any OpenAICompatibleCredentialPersisting,
        textPolishUsageDirectoryURL: URL?,
        softwareUpdateSnapshot: SoftwareUpdateSnapshot,
        onCheckForUpdates: @escaping () -> Result<Void, SoftwareUpdateError>,
        onSetAutomaticallyChecksForUpdates: @escaping (Bool) -> Result<SoftwareUpdateSnapshot, SoftwareUpdateError>,
        onDeleteAllData: @escaping () -> Result<AppConfig, any Error>,
        onOpenOnboarding: @escaping () -> Void,
        onOpenSkillLibrary: @escaping () -> Void,
        onOpenTerminology: @escaping () -> Void,
        onLoadFullTranscriptionHistory: @escaping @Sendable () async -> [TranscriptionHistoryRecord],
        onLoadFullRecoveryHistory: @escaping @Sendable () async -> [RecoveryRecord],
        onCanUndoTranscriptionRecord: @escaping (UUID) -> Bool,
        onUndoTranscriptionRecord: @escaping (UUID) async -> SafeUndoOutcome,
        onDeleteTranscriptionRecord: @escaping (UUID) -> Result<Void, any Error>,
        onDeleteRecoveryRecord: @escaping (UUID) -> Result<Void, any Error>,
        onRunSkillTest: @escaping (SkillTestRunRequest) async -> Result<SkillTestRunResult, any Error>,
        onVoiceSampleAction: @escaping (SkillVoiceSampleAction) async -> Result<SkillVoiceSampleResult, any Error>,
        onHotkeyCaptureChanged:
            @escaping (Bool) -> Void,
        onPreviewVisualFeedback:
            @escaping (
                VisualFeedbackPreview,
                VisualFeedbackConfig
            ) -> Void,
        skillPackageStore:
            SkillPackageStore = .init(),
        styleCapsuleStore:
            StyleCapsuleStore = .init(),
        localAssetAccessEnabled:
            Bool = true,
        focusPane: SettingsPane? = nil,
        skillLibraryInitialSection:
            SkillLibrarySection = .discover
    ) {
        let windowStateStore = SettingsWindowStateStore()
        // Seed the library segment store once when Settings is created with an
        // explicit deep link (Installed / Created). Later Skills remounts read
        // from the store instead of re-applying this constructor argument, so
        // users who switch to Discover keep that choice after popups dismiss.
        if skillLibraryInitialSection != .discover {
            windowStateStore.saveSkillLibrarySection(
                skillLibraryInitialSection
            )
        }
        _config = State(initialValue: initialConfig)
        _persistedConfig = State(
            initialValue: initialConfig
        )
        _recoveryEndpointDraft = State(
            initialValue: initialConfig.transcription.openAITranscriptionURL
        )
        _recoveryModelDraft = State(
            initialValue: initialConfig.transcription.openAIModel
        )
        _communitySkillInventory = State(
            initialValue: CommunitySkillInventory(packages: [], rejected: [])
        )
        _showsAdvancedRecovery = State(initialValue: false)
        _showsOwnAPIConfigurationSheet = State(initialValue: false)
        _availableDictationModels = State(initialValue: ProductModelCatalog.dictationPresets)
        _availablePolishModels = State(initialValue: ProductModelCatalog.rewritePresets)
        _availableAccountPolishModels = State(initialValue: ProductModelCatalog.rewritePresets)
        _accountPolishModelsMessage = State(initialValue: nil)
        _accountPolishModelsMessageIsError = State(initialValue: false)
        _isLoadingAccountPolishModels = State(initialValue: false)
        _isDetectingModels = State(initialValue: false)
        _ownAPIConfigurationTab = State(initialValue: .recognition)
        _polishEndpointDraft = State(
            initialValue: initialConfig.transcription.textPolish.openAICompatibleURL
        )
        _polishAPIKeyInput = State(initialValue: "")
        _polishAPIKeyStored = State(initialValue: false)
        _polishMessage = State(initialValue: nil)
        _polishMessageIsError = State(initialValue: false)
        _isTestingPolishConnection = State(initialValue: false)
        _permissionStatusMonitor = StateObject(wrappedValue: PermissionStatusMonitor())
        _terminologyImportMessage = State(initialValue: Self.terminologyStatusMessage(for: initialConfig))
        _authSnapshot = State(initialValue: authManager.authSnapshot())
        _browserBridgeSnapshot = State(initialValue: authManager.browserBridgeSnapshot())
        _textPolishUsage = State(initialValue: [:])
        _providerPolicySnapshot = State(initialValue: .loading)
        _softwareUpdateSnapshot = State(initialValue: softwareUpdateSnapshot)
        _recoveryAPIKeyStored = State(initialValue: false)
        _recoveryMessage = State(initialValue: nil)
        _recoveryMessageIsError = State(initialValue: false)
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
        self.textPolishUsageDirectoryURL = textPolishUsageDirectoryURL
        self.onCheckForUpdates = onCheckForUpdates
        self.onSetAutomaticallyChecksForUpdates = onSetAutomaticallyChecksForUpdates
        self.onDeleteAllData = onDeleteAllData
        self.onOpenOnboarding = onOpenOnboarding
        self.onOpenSkillLibrary =
            onOpenSkillLibrary
        self.onOpenTerminology =
            onOpenTerminology
        self.onLoadFullTranscriptionHistory =
            onLoadFullTranscriptionHistory
        self.onLoadFullRecoveryHistory =
            onLoadFullRecoveryHistory
        self.onCanUndoTranscriptionRecord =
            onCanUndoTranscriptionRecord
        self.onUndoTranscriptionRecord =
            onUndoTranscriptionRecord
        self.onDeleteTranscriptionRecord =
            onDeleteTranscriptionRecord
        self.onDeleteRecoveryRecord =
            onDeleteRecoveryRecord
        self.onRunSkillTest = onRunSkillTest
        self.onVoiceSampleAction = onVoiceSampleAction
        self.onHotkeyCaptureChanged =
            onHotkeyCaptureChanged
        self.onPreviewVisualFeedback =
            onPreviewVisualFeedback
        self.skillPackageStore =
            skillPackageStore
        self.styleCapsuleStore =
            styleCapsuleStore
        self.localAssetAccessEnabled =
            localAssetAccessEnabled
        self.skillLibraryInitialSection =
            skillLibraryInitialSection
        self.windowStateStore = windowStateStore
    }

    private var runtimeIssues: [RuntimePreflightIssue] {
        RuntimePreflight.issues(
            for: config,
            authSnapshotProvider: { authSnapshot },
            recoveryCredentialAvailable: { recoveryAPIKeyStored }
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
        let trusted = permissionStatusMonitor.snapshot.accessibilityTrusted
        if trusted {
            return SetupStatus(
                title: AccessibilityPermission.statusTitle(isTrusted: true),
                subtitle: L10n.text("Auto-paste is ready.")
            )
        }

        let guidance = AccessibilityPermission.repairGuidance()
        return SetupStatus(
            title: AccessibilityPermission.statusTitle(
                isTrusted: false,
                signatureState: AccessibilityPermission.signatureState()
            ),
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
        ZStack {
            settingsSplitView
            SonnerToastHost(
                center: sonnerToasts,
                reduceMotion: reduceMotion
            )
        }
        .frame(minWidth: 900, minHeight: 620)
        .background {
            // Zero-size AppKit probe that observes didBecomeKey / didResignKey.
            SettingsWindowKeyTracker(
                isKeyWindow: $isSettingsWindowKey,
                onNeedsGlassRematerialize: {
                    sidebarGlassMaterializationID &+= 1
                }
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        // Selection chrome animates only on the source-list row style.
        // Root-level animation here previously slid the floating sidebar when
        // focus or key-window state changed (safe-area / layout inheritance).
        .onChange(of: selectedSection) { pane in
            let normalized = pane.normalizedVisiblePane
            if normalized != pane {
                // Collapsed legacy panes (Account → General, Polish/Paste →
                // Dictation, Privacy → Context) rewrite once without falling
                // through to a hard General reset.
                selectedSection = normalized
                return
            }
            windowStateStore.saveSelectedPane(normalized)
        }
        .onChange(of: config) { _ in
            if suppressNextPersist {
                suppressNextPersist = false
                return
            }
            persistSettings()
        }
        .onChange(of: config.communitySkills) { _ in
            refreshCommunitySkillInventory()
        }
        .onChange(of: config.transcription.openAITranscriptionURL) { value in
            if recoveryEndpointDraft != value {
                recoveryEndpointDraft = value
            }
        }
        .onChange(of: config.transcription.openAIModel) { value in
            if recoveryModelDraft != value {
                recoveryModelDraft = value
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .vibeComposeNavigateSettingsPane
            )
        ) { notification in
            guard
                let rawValue = notification.userInfo?["pane"] as? String,
                let pane = SettingsPane(rawValue: rawValue)
            else {
                return
            }
            if let sectionRaw = notification.userInfo?[
                "skillLibrarySection"
            ] as? String,
               let section = SkillLibrarySection(rawValue: sectionRaw)
            {
                windowStateStore.saveSkillLibrarySection(section)
                skillLibraryRemountID = UUID()
            }
            // Do not wrap in withAnimation: detail already animates via
            // settingsDetail's activeSection transaction. Animating here also
            // drove the floating sidebar's safe-area frame (slide-down glitch).
            isSidebarFocused = true
            selectedSection = pane.normalizedVisiblePane
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .vibeComposeLiveConfigDidChange
            )
        ) { _ in
            applyLiveConfigFromBridge()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // User may have flipped Accessibility in System Settings while we
            // were inactive — re-read TCC immediately, then poll briefly in case
            // the grant lands a moment after activation.
            permissionStatusMonitor.refresh()
            Task { @MainActor in
                _ = await permissionStatusMonitor.refreshAccessibilityUntilTrusted(
                    maximumRefreshAttempts: 8,
                    refreshDelay: .milliseconds(200)
                )
            }
            authSnapshot = authManager.authSnapshot()
            browserBridgeSnapshot = authManager.browserBridgeSnapshot()
            refreshTextPolishStatus()
            refreshRecentHistory()
            refreshRecoveryHistory()
            refreshRecoveryCredentialState()
            refreshCommunitySkillInventory()
        }
        .onChange(of: isSettingsWindowKey) { isKey in
            guard isKey else {
                return
            }
            permissionStatusMonitor.refresh()
            Task { @MainActor in
                _ = await permissionStatusMonitor.refreshAccessibilityUntilTrusted(
                    maximumRefreshAttempts: 6,
                    refreshDelay: .milliseconds(200)
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chatGPTAuthStateDidChange)) { _ in
            authSnapshot = authManager.authSnapshot()
            browserBridgeSnapshot = authManager.browserBridgeSnapshot()
            refreshTextPolishStatus()
            refreshAccountPolishModels(force: true)
        }
        .onAppear {
            permissionStatusMonitor.refresh()
            refreshTextPolishStatus()
            refreshRecentHistory()
            refreshRecoveryHistory()
            refreshRecoveryCredentialState()
            refreshCommunitySkillInventory()
            refreshAccountPolishModels(force: false)
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
            L10n.text("Delete all VibeCompose data?"),
            isPresented: $showsDeleteAllDataConfirmation
        ) {
            Button(L10n.text("Cancel"), role: .cancel) {}
            Button(L10n.text("Delete All Data"), role: .destructive) {
                deleteAllData()
            }
        } message: {
            Text(
                L10n.text(
                    "This removes transcripts, failed recordings, diagnostics, product metrics, terminology, custom Writing Styles, installed Community Skills, settings, the saved ChatGPT session, and the OpenAI-Compatible API key from this Mac. This action cannot be undone."
                )
            )
        }
        .alert(
            L10n.text("Import Your Own API?"),
            isPresented: $showsAdvancedRecovery
        ) {
            Button(L10n.text("Cancel"), role: .cancel) {}
            Button(L10n.text("Use My API")) {
                activateImportOwnAPI()
            }
        } message: {
            Text(
                L10n.text(
                    "Future dictation audio will be sent to the configured endpoint with your Keychain API key. Your API provider may charge for transcription."
                )
            )
        }
        .sheet(isPresented: $showsThirdPartyLicenses) {
            ThirdPartyLicensesView(
                documents: thirdPartyLicenseDocuments
            )
        }
        .sheet(isPresented: $showsOwnAPIConfigurationSheet) {
            ownAPIConfigurationSheet
        }
    }

    private var settingsSplitView: some View {
        // App Store / Music–style source list: glass rail that extends under
        // the transparent titlebar so the traffic lights sit *on* the sidebar
        // material (official treatment), not floating below a white chrome band.
        ZStack(alignment: .topLeading) {
            // Solid canvas lives under the floating rail, not under the glass
            // material itself — keeps continuous glass corners clean.
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            settingsDetail
                // Clicking anywhere in the detail pane demotes the
                // source-list selection to its inactive (gray) style.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if isSidebarFocused {
                                isSidebarFocused = false
                            }
                        }
                )
                .padding(
                    .leading,
                    SettingsLayoutMetrics.sidebarColumnWidth
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            settingsSidebar
                .padding(.leading, SettingsLayoutMetrics.sidebarInsetLeading)
                .padding(.top, SettingsLayoutMetrics.sidebarInsetTop)
                .padding(.bottom, SettingsLayoutMetrics.sidebarInsetBottom)
                .frame(maxHeight: .infinity, alignment: .top)
                // Reach under the transparent unified titlebar so the glass
                // wraps the traffic lights instead of sitting below them.
                .ignoresSafeArea(.container, edges: .top)
                // Detail page / focus transactions must not interpolate this
                // rail's frame (reads as a slide-down). Row chrome still uses
                // its own local `.animation` modifiers.
                .animation(nil, value: activeSection)
                .animation(nil, value: isSidebarFocused)
                .animation(nil, value: isSettingsWindowKey)
        }
    }

    private var settingsSidebar: some View {
        // Continuous rounded rect so the floating glass rail reads as a card
        // that the traffic lights sit *on* (Music / App Store). Top is kept
        // under the transparent titlebar via `ignoresSafeArea` + zero top
        // inset; leading/bottom gutters come from the outer padding.
        let shape = RoundedRectangle(
            cornerRadius: VibeComposeFloatingChrome.sidebarCornerRadius,
            style: .continuous
        )
        return settingsSidebarList
            .padding(.top, SettingsLayoutMetrics.sidebarContentTopPadding)
            .frame(width: SettingsLayoutMetrics.sidebarWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            // No opaque fill under glass — solid row pills are fine, a full-
            // bleed rectangle is what pokes square corners through Liquid Glass.
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .vibeComposeFloatingSidebarGlass(
                in: shape,
                materializationID: sidebarGlassMaterializationID
            )
            // Clicking the source list re-emphasizes the selection (blue).
            .contentShape(shape)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isSidebarFocused {
                            isSidebarFocused = true
                        }
                    }
            )
    }

    @ViewBuilder
    private var settingsDetail: some View {
        ZStack {
            switch activeSection {
            case .skills, .rules, .history, .terminology, .styleCapsules:
                embeddedDestination
                    .padding(.top, SettingsLayoutMetrics.embeddedTopPadding)
                    .id(activeSection)
                    .transition(settingsPageTransition)
            default:
                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: 22
                    ) {
                        HStack(
                            alignment: .top,
                            spacing: 16
                        ) {
                            sectionHeader
                            Spacer(minLength: 16)
                            saveStatusIndicator
                        }
                        selectedSectionView
                    }
                    .padding(
                        .horizontal,
                        SettingsLayoutMetrics
                            .detailHorizontalPadding
                    )
                    .padding(
                        .top,
                        SettingsLayoutMetrics
                            .detailTopPadding
                    )
                    .padding(.bottom, 44)
                    .frame(
                        maxWidth:
                            VibeComposeMetrics
                                .contentMaxWidth,
                        alignment: .leading
                    )
                    .frame(
                        maxWidth: .infinity,
                        alignment: .top
                    )
                }
                .id(activeSection)
                .transition(settingsPageTransition)
                .background(
                    Color(nsColor: .windowBackgroundColor)
                )
            }
        }
        // Scope page animation to the detail column only so the floating
        // sidebar never inherits opacity/scale transitions.
        .animation(
            reduceMotion ? .linear(duration: 0) : .easeOut(duration: VibeComposeMotion.pageTransition),
            value: activeSection
        )
        .background(
            Color(nsColor: .windowBackgroundColor)
        )
    }

    private var settingsPageTransition: AnyTransition {
        // Opacity only — combined scale previously shifted sibling layout and
        // made the floating sidebar appear to slide down on pane switches.
        .opacity
    }

    private var settingsSidebarList: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: SettingsLayoutMetrics.sidebarSectionSpacing
            ) {
                // Keep the product shell destinations aligned with SettingsPane.visiblePanes.
                ForEach(SettingsSidebarGroup.allCases) { group in
                    VStack(
                        alignment: .leading,
                        spacing: SettingsLayoutMetrics.sidebarHeaderRowSpacing
                    ) {
                        Text(group.title)
                            .font(VibeComposeTypography.caption(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(
                                .leading,
                                SettingsLayoutMetrics.sidebarRowInnerPadding
                            )
                        VStack(
                            alignment: .leading,
                            spacing: SettingsLayoutMetrics.sidebarRowSpacing
                        ) {
                            settingsPaneLinks(
                                group.panes.filter {
                                    SettingsPane.visiblePanes.contains($0)
                                }
                            )
                        }
                    }
                }
            }
            .padding(
                .horizontal,
                SettingsLayoutMetrics.sidebarRowOuterPadding
            )
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var embeddedDestination: some View {
        switch activeSection {
        case .skills:
            SkillLibraryView(
                initialConfig: config,
                store: skillPackageStore,
                localAssetAccessEnabled: localAssetAccessEnabled,
                // Always restore Discover/Install from SettingsWindowStateStore.
                // Deep links seed the store once at PreferencesView init, so
                // remounts after popup dismiss never re-force the original tab.
                // skillLibraryRemountID forces a remount when a deep link updates
                // the stored section while Settings is already open.
                initialSection: .discover,
                isEmbedded: true,
                windowStateStore: windowStateStore,
                onSave: { updated in
                    persistEmbeddedConfig(updated)
                },
                onRunTest: onRunSkillTest,
                onVoiceSampleAction: onVoiceSampleAction
            )
            .id(skillLibraryRemountID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        case .rules:
            SkillRulesSettingsView(
                config: $config,
                inventory: communitySkillInventory
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        case .history:
            HistoryWindowView(
                isEmbedded: true,
                hotkeyBinding: config.transcription.dictationHotkey,
                onLoadTranscriptionHistory: onLoadFullTranscriptionHistory,
                onLoadRecoveryHistory: onLoadFullRecoveryHistory,
                onResolveRecoveryAudioURL: onResolveRecoveryAudioURL,
                onRetryRecoveryRecord: onRetryRecoveryRecord,
                onCanUndoTranscriptionRecord: onCanUndoTranscriptionRecord,
                onUndoTranscriptionRecord: onUndoTranscriptionRecord,
                onDeleteTranscriptionRecord: onDeleteTranscriptionRecord,
                onDeleteRecoveryRecord: onDeleteRecoveryRecord
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        case .terminology:
            TerminologyManagerView(
                initialConfig: config,
                isEmbedded: true,
                onSave: { updated in
                    persistEmbeddedConfig(updated)
                }
            )
            .id(terminologyRemountID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        case .styleCapsules:
            StyleCapsuleLibraryView(
                config: $config,
                registry: availableSkillRegistry,
                store: styleCapsuleStore,
                localAssetAccessEnabled: localAssetAccessEnabled
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        default:
            EmptyView()
        }
    }

    private var activeSection: SettingsPane {
        selectedSection.normalizedVisiblePane
    }

    @ViewBuilder
    private func settingsPaneLinks(
        _ panes: [SettingsPane]
    ) -> some View {
        ForEach(panes) { pane in
            SettingsSidebarRowButton(
                pane: pane,
                isSelected: activeSection == pane,
                selectionIsActive: isSettingsWindowKey && isSidebarFocused,
                reduceMotion: reduceMotion
            ) {
                isSidebarFocused = true
                selectedSection = pane
            }
        }
    }

    private var availableSkillRegistry:
        SkillRegistry
    {
        communitySkillInventory.registry
    }

    private var sectionHeader: some View {
        Text(activeSection.displayTitle)
            .font(VibeComposeTypography.display())
            .tracking(-0.25)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var saveStatusIndicator: some View {
        switch saveStatus {
        case .saved:
            EmptyView()
        case .failed(let message):
            Label(L10n.text("Save failed"), systemImage: "exclamationmark.triangle.fill")
                .font(VibeComposeTypography.caption(.semibold))
                .foregroundStyle(Color(nsColor: VibeComposePalette.error))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Color(nsColor: VibeComposePalette.error).opacity(0.12),
                    in: Capsule(style: .continuous)
                )
                .help(message)
                .accessibilityLabel(L10n.format("Could not save settings: %@", message))
        }
    }

    @ViewBuilder
    private var selectedSectionView: some View {
        switch activeSection {
        case .general, .account:
            VStack(alignment: .leading, spacing: VibeComposeMetrics.space20) {
                generalCard
                accountOverviewCard
            }
        case .dictation, .polish, .paste:
            VStack(alignment: .leading, spacing: VibeComposeMetrics.space20) {
                dictationCard
                pasteAndClipboardCard
                aiPolishCard
            }
        case .appearance:
            appearanceAndFeedbackCard
        case .context, .privacy:
            VStack(alignment: .leading, spacing: VibeComposeMetrics.space20) {
                contextSourcesCard
                skillPermissionsCard
                contextReceiptsCard
                localDataCard
                privacyActionsCard
            }
        case .terminology, .styleCapsules, .skills, .rules, .history:
            EmptyView()
        case .advanced:
            VStack(alignment: .leading, spacing: VibeComposeMetrics.space20) {
                advancedRecognitionCard
                advancedPolishCard
                advancedAPIAccessRow
            }
        }
    }

    private var generalCard: some View {
        // System Settings Form: label left, controls right-aligned on a shared edge.
        settingsCard(title: nil, style: .grouped) {
            SettingsRow(title: L10n.text("App Language")) {
                Picker(
                    L10n.text("App Language"),
                    selection: $config.appLanguage
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(
                    width: GeneralSettingsChrome.controlClusterWidth,
                    alignment: .trailing
                )
            }

            Divider().opacity(0.55)

            SettingsRow(title: L10n.text("Default Skill")) {
                // Show only the active Skill. Tap navigates to Rules inside
                // this Settings window — never spawns a second surface.
                Button {
                    selectedSection = .rules
                } label: {
                    HStack(spacing: 6) {
                        Text(
                            currentGlobalDefaultSkill?.localizedName
                                ?? L10n.text("Direct")
                        )
                        .font(VibeComposeTypography.callout(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .frame(
                    width: GeneralSettingsChrome.controlClusterWidth,
                    alignment: .trailing
                )
                .help(L10n.text("Open Rules…"))
            }

            Divider().opacity(0.55)

            SettingsRow(title: L10n.text("Dictation shortcut")) {
                HStack(spacing: VibeComposeMetrics.space8) {
                    Spacer(minLength: 0)
                    HotkeyRecorderView(
                        binding: config.transcription.dictationHotkey,
                        onCandidate: { candidate in
                            applyHotkeyCandidate(candidate)
                        },
                        onCaptureChanged: { capturing in
                            isCapturingHotkey = capturing
                            onHotkeyCaptureChanged(capturing)
                            if capturing {
                                // Capture UX is self-evident on the recorder button.
                            } else if !hotkeyMessageIsError {
                                hotkeyMessage = nil
                            }
                        }
                    )
                    .frame(
                        width: GeneralSettingsChrome.recorderWidth,
                        height: GeneralSettingsChrome.controlHeight
                    )
                }
                .frame(
                    width: GeneralSettingsChrome.controlClusterWidth,
                    alignment: .trailing
                )
            }

            Divider().opacity(0.55)

            SettingsRow(title: L10n.text("Skill Switcher shortcut")) {
                optionalHotkeyControls(
                    isEnabled: skillSwitcherHotkeyEnabledBinding,
                    accessibilityLabel: L10n.text("Skill Switcher shortcut"),
                    binding: config.skillSwitcherHotkey,
                    onCandidate: { candidate in
                        applySkillSwitcherHotkeyCandidate(candidate)
                    }
                )
            }

            Divider().opacity(0.55)

            SettingsRow(title: L10n.text("Result Preview shortcut")) {
                optionalHotkeyControls(
                    isEnabled: resultPreviewHotkeyEnabledBinding,
                    accessibilityLabel: L10n.text("Result Preview shortcut"),
                    binding: config.resultPreviewHotkey,
                    onCandidate: { candidate in
                        applyResultPreviewHotkeyCandidate(candidate)
                    }
                )
            }

            // Hard errors only (conflicts / registration failures). Capture
            // guidance lives on the recorder control itself — no secondary line.
            if let hotkeyMessage, hotkeyMessageIsError {
                Text(hotkeyMessage)
                    .font(VibeComposeTypography.caption())
                    .foregroundStyle(Color(nsColor: VibeComposePalette.error))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, VibeComposeMetrics.space4)
            }
        }
    }

    /// Shared trailing control cluster for optional shortcuts (toggle + recorder).
    @ViewBuilder
    private func optionalHotkeyControls(
        isEnabled: Binding<Bool>,
        accessibilityLabel: String,
        binding: HotkeyBinding?,
        onCandidate: @escaping @MainActor (HotkeyBinding) -> Void
    ) -> some View {
        HStack(spacing: VibeComposeMetrics.space10) {
            Spacer(minLength: 0)
            Toggle(L10n.text("Enabled"), isOn: isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel(accessibilityLabel)
            if let binding {
                HotkeyRecorderView(
                    binding: binding,
                    onCandidate: onCandidate,
                    onCaptureChanged: { capturing in
                        isCapturingHotkey = capturing
                        onHotkeyCaptureChanged(capturing)
                        if capturing {
                            // Capture UX is self-evident on the recorder button.
                        } else if !hotkeyMessageIsError {
                            hotkeyMessage = nil
                        }
                    }
                )
                .frame(
                    width: GeneralSettingsChrome.recorderWidth,
                    height: GeneralSettingsChrome.controlHeight
                )
            } else {
                // Same footprint as the live recorder so the row never jumps
                // and the trailing edge stays aligned with other controls.
                disabledHotkeyPlaceholder
            }
        }
        .frame(
            width: GeneralSettingsChrome.controlClusterWidth,
            alignment: .trailing
        )
    }

    /// Dimmed capsule matching `HotkeyRecorderView` size — used when an
    /// optional shortcut is toggled off so the control column stays stable.
    private var disabledHotkeyPlaceholder: some View {
        RoundedRectangle(
            cornerRadius: VibeComposeMetrics.radiusS,
            style: .continuous
        )
        .fill(Color.primary.opacity(0.06))
        .overlay {
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusS,
                style: .continuous
            )
            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .frame(
            width: GeneralSettingsChrome.recorderWidth,
            height: GeneralSettingsChrome.controlHeight
        )
        .accessibilityHidden(true)
    }

    private var currentGlobalDefaultSkill:
        SkillDefinition?
    {
        availableSkillRegistry.definition(
            id: config.transcription.skills
                .defaultSkillID
        )
    }

    private var pasteAndClipboardCard: some View {
        settingsCard(title: "Paste & Clipboard", style: .grouped) {
            SettingsRow(
                title: L10n.text("Skip result preview when safe")
            ) {
                Toggle(
                    L10n.text("Skip result preview when safe"),
                    isOn: $config.injection.skipResultPreviewWhenSafe
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            Divider().opacity(0.55)

            SettingsRow(
                title: L10n.text("Restore clipboard after verified insertion")
            ) {
                Toggle(
                    L10n.text("Restore clipboard after verified insertion"),
                    isOn: $config.injection.preserveClipboard
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }
        }
    }

    private func persistSettings() {
        let previousHotkey =
            persistedConfig.transcription.dictationHotkey
        let requestedHotkey =
            config.transcription.dictationHotkey
        let previousSkillSwitcherHotkey =
            persistedConfig.skillSwitcherHotkey
        let requestedSkillSwitcherHotkey =
            config.skillSwitcherHotkey
        switch onSave(config) {
        case .success:
            persistedConfig = config
            saveStatus = .saved
            // Shortcut enable/disable is self-evident from the toggle + recorder
            // row; only keep messages for real errors (handled in the catch path).
            if previousHotkey != requestedHotkey {
                hotkeyMessage = nil
                hotkeyMessageIsError = false
            } else if previousSkillSwitcherHotkey
                != requestedSkillSwitcherHotkey
            {
                hotkeyMessage = nil
                hotkeyMessageIsError = false
            }
        case .failure(let error):
            saveStatus = .failed(error.localizedDescription)
            sonnerToasts.error(
                L10n.text("Save failed"),
                detail: error.localizedDescription
            )
            if previousHotkey != requestedHotkey
                || previousSkillSwitcherHotkey
                    != requestedSkillSwitcherHotkey
            {
                hotkeyMessage = error.localizedDescription
                hotkeyMessageIsError = true
                suppressNextPersist = true
                config.transcription.dictationHotkey =
                    previousHotkey
                config.skillSwitcherHotkey =
                    previousSkillSwitcherHotkey
            }
        }
    }

    private func persistEmbeddedConfig(
        _ updatedConfig: AppConfig
    ) -> Result<Void, any Error> {
        let result = onSave(updatedConfig)
        switch result {
        case .success:
            persistedConfig = updatedConfig
            saveStatus = .saved
            if config != updatedConfig {
                suppressNextPersist = true
                config = updatedConfig
            }
        case .failure(let error):
            saveStatus = .failed(error.localizedDescription)
        }
        return result
    }

    /// Rebase Settings draft against a coordinator commit (non-Settings source).
    private func applyLiveConfigFromBridge() {
        guard let payload = PreferencesLiveConfigBridge.shared.consume()
        else {
            return
        }
        let live = payload.0
        let forceReplace = payload.1
        let previousLocal = config
        let next: AppConfig
        if forceReplace {
            next = live
        } else {
            let base = persistedConfig
            next =
                if previousLocal == base {
                    live
                } else {
                    AppConfig.merging(
                        base: base,
                        local: previousLocal,
                        remote: live
                    )
                }
        }
        if next != previousLocal {
            suppressNextPersist = true
            config = next
        }
        // Baseline tracks last agreed disk/coordinator truth for the next dirty calc.
        persistedConfig = live

        if previousLocal.communitySkills != next.communitySkills
            || previousLocal.transcription.skills != next.transcription.skills
            || previousLocal.skillEcosystem != next.skillEcosystem
        {
            skillLibraryRemountID = UUID()
        }
        if previousLocal.transcription.terminology
            != next.transcription.terminology
            || previousLocal.terminologyPacks != next.terminologyPacks
        {
            terminologyRemountID = UUID()
        }
        if previousLocal.communitySkills != next.communitySkills {
            refreshCommunitySkillInventory()
        }
    }

    private func commitRecoveryEndpointDraft() {
        guard config.transcription.openAITranscriptionURL
            != recoveryEndpointDraft
        else {
            return
        }
        config.transcription.openAITranscriptionURL =
            recoveryEndpointDraft
    }

    private func commitRecoveryModelDraft() {
        guard config.transcription.openAIModel != recoveryModelDraft else {
            return
        }
        config.transcription.openAIModel = recoveryModelDraft
    }

    private func applyHotkeyCandidate(
        _ candidate: HotkeyBinding
    ) {
        do {
            let validated = try candidate.validated()
            try VibeComposeShortcutSetValidator.validate(
                dictation: validated,
                skillSwitcher: config.skillSwitcherHotkey,
                resultPreview: config.resultPreviewHotkey
            )
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

    private var skillSwitcherHotkeyEnabledBinding:
        Binding<Bool>
    {
        Binding(
            get: { config.skillSwitcherHotkey != nil },
            set: { enabled in
                if enabled {
                    applySkillSwitcherHotkeyCandidate(
                        .skillSwitcher
                    )
                } else {
                    config.skillSwitcherHotkey = nil
                    // Clear any leftover capture/status copy; no "disabled" banner.
                    if !hotkeyMessageIsError {
                        hotkeyMessage = nil
                    }
                }
            }
        )
    }

    private var resultPreviewHotkeyEnabledBinding:
        Binding<Bool>
    {
        Binding(
            get: { config.resultPreviewHotkey != nil },
            set: { enabled in
                if enabled {
                    applyResultPreviewHotkeyCandidate(
                        .resultPreview
                    )
                } else {
                    config.resultPreviewHotkey = nil
                    if !hotkeyMessageIsError {
                        hotkeyMessage = nil
                    }
                }
            }
        )
    }

    private func applySkillSwitcherHotkeyCandidate(
        _ candidate: HotkeyBinding
    ) {
        do {
            let validated = try candidate.validated()
            try VibeComposeShortcutSetValidator.validate(
                dictation:
                    config.transcription.dictationHotkey,
                skillSwitcher: validated,
                resultPreview: config.resultPreviewHotkey
            )
            if validated == config.skillSwitcherHotkey {
                hotkeyMessage = L10n.format(
                    "%@ is already the Skill Switcher shortcut.",
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
            config.skillSwitcherHotkey = validated
        } catch {
            hotkeyMessage = error.localizedDescription
            hotkeyMessageIsError = true
        }
    }

    private func applyResultPreviewHotkeyCandidate(
        _ candidate: HotkeyBinding
    ) {
        do {
            let validated = try candidate.validated()
            try VibeComposeShortcutSetValidator.validate(
                dictation:
                    config.transcription.dictationHotkey,
                skillSwitcher: config.skillSwitcherHotkey,
                resultPreview: validated
            )
            if validated == config.resultPreviewHotkey {
                hotkeyMessage = L10n.format(
                    "%@ is already the Result Preview shortcut.",
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
            config.resultPreviewHotkey = validated
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

    nonisolated private static func loadTextPolishUsage(
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
        guard let directoryURL = textPolishUsageDirectoryURL else {
            textPolishUsage = [:]
            return
        }
        Task {
            let usage = await Task.detached(priority: .utility) {
                Self.loadTextPolishUsage(directoryURL: directoryURL)
            }.value
            guard !Task.isCancelled else {
                return
            }
            textPolishUsage = usage
        }
    }

    private func refreshCommunitySkillInventory() {
        guard localAssetAccessEnabled else {
            communitySkillInventory = CommunitySkillInventory(
                packages: [],
                rejected: []
            )
            return
        }
        let store = skillPackageStore
        let communitySkills = config.communitySkills
        Task {
            let inventory = await Task.detached(priority: .utility) {
                store.loadInventory(config: communitySkills)
            }.value
            guard !Task.isCancelled, config.communitySkills == communitySkills else {
                return
            }
            communitySkillInventory = inventory
        }
    }

    private func refreshRecentHistory() {
        Task {
            let records = await onLoadRecentHistory()
            guard !Task.isCancelled else {
                return
            }
            recentHistoryRecords = records
        }
    }

    private func refreshRecoveryHistory() {
        Task {
            let records = await onLoadRecoveryHistory()
            guard !Task.isCancelled else {
                return
            }
            recentRecoveryRecords = records
        }
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
        // Account & permissions — status first, then identity/actions.
        settingsCard(title: "Account & Permissions", style: .grouped) {
            HStack(alignment: .top, spacing: 0) {
                compactSetupTile(title: "ChatGPT", status: chatGPTAccountStatus)
                Divider()
                    .frame(height: 40)
                    .padding(.horizontal, VibeComposeMetrics.space12)
                compactSetupTile(title: "Microphone", status: microphoneStatus)
                Divider()
                    .frame(height: 40)
                    .padding(.horizontal, VibeComposeMetrics.space12)
                compactSetupTile(title: "Accessibility", status: accessibilityStatus)
            }
            .padding(.vertical, VibeComposeMetrics.space4)

            Divider().opacity(0.55)

            HStack(alignment: .center, spacing: VibeComposeMetrics.space12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("ChatGPT Account"))
                        .font(VibeComposeTypography.body(.medium))
                    if let userEmail = authSnapshot.userEmail {
                        Text(userEmail)
                            .font(VibeComposeTypography.caption())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    } else {
                        Text(chatGPTAccountStatus.title)
                            .font(VibeComposeTypography.caption())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: VibeComposeMetrics.space12)
                chatGPTSetupActions
            }
            .padding(.vertical, VibeComposeMetrics.space8)

            // Repair actions only when something still needs attention — no
            // setup-guide link or "ready" caption clutter under the tiles.
            if permissionStatusMonitor.snapshot.microphone != .granted
                || !permissionStatusMonitor.snapshot.accessibilityTrusted
            {
                Divider().opacity(0.55)
                    .padding(.top, VibeComposeMetrics.space8)
                HStack(spacing: VibeComposeMetrics.space10) {
                    ForEach(permissionRepairActions) { action in
                        repairActionButton(action)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, VibeComposeMetrics.space8)

                if isRequestingMicrophoneAccess {
                    Label(
                        L10n.text("Requesting microphone"),
                        systemImage: "mic.badge.plus"
                    )
                    .font(VibeComposeTypography.caption(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, VibeComposeMetrics.space6)
                }
            }

            // Only surface real errors — never a success tip like
            // "Microphone access is ready."
            if let permissionMessage, permissionMessageIsError {
                Text(permissionMessage)
                    .font(VibeComposeTypography.caption())
                    .foregroundStyle(Color(nsColor: VibeComposePalette.error))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, VibeComposeMetrics.space6)
            }
        }
    }

    private var dictationCard: some View {
        // Lean Form: only controls that change dictation behavior. History
        // and account routing live on their own destinations.
        settingsCard(title: "Dictation / ASR", style: .grouped) {
            SettingsRow(title: L10n.text("Feedback sounds")) {
                Toggle(
                    L10n.text("Feedback sounds"),
                    isOn: $config.transcription.feedbackSoundsEnabled
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            Divider().opacity(0.55)

            SettingsRow(title: L10n.text("ASR prompt cleanup")) {
                Toggle(
                    L10n.text("ASR prompt cleanup"),
                    isOn: $config.transcription.speechCleanupEnabled
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }


            Divider().opacity(0.55)

            SettingsRow(title: L10n.text("Punctuation")) {
                Picker(
                    L10n.text("Punctuation"),
                    selection: $config.transcription.punctuationPreference
                ) {
                    ForEach(TranscriptPunctuationPreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: GeneralSettingsChrome.controlClusterWidth, alignment: .trailing)
            }

            Divider().opacity(0.55)

            SettingsRow(title: L10n.text("Recent records")) {
                Button(L10n.text("Open History…")) {
                    selectedSection = .history
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var appearanceAndFeedbackCard: some View {
        // System Settings form: left labels, trailing controls, mode-specific
        // options only. No preview chrome — live dictation is the preview.
        settingsCard(title: nil, style: .grouped) {
            SettingsRow(title: L10n.text("Visual feedback")) {
                Picker(
                    L10n.text("Visual feedback"),
                    selection: $config.visualFeedback.mode
                ) {
                    ForEach(VisualFeedbackMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(
                    width: GeneralSettingsChrome.controlClusterWidth,
                    alignment: .trailing
                )
            }

            if config.visualFeedback.mode == .refinedHUD {
                Divider().opacity(0.55)

                SettingsRow(title: L10n.text("Status Bar position")) {
                    Picker(
                        L10n.text("Status Bar position"),
                        selection: $config.visualFeedback.hudPlacement
                    ) {
                        ForEach(HUDPlacement.allCases) { placement in
                            Text(placement.title).tag(placement)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(
                        width: GeneralSettingsChrome.controlClusterWidth,
                        alignment: .trailing
                    )
                }
            }

            if config.visualFeedback.mode == .aiActivityGlow {
                Divider().opacity(0.55)

                SettingsRow(title: L10n.text("Intensity")) {
                    Picker(
                        L10n.text("Intensity"),
                        selection: $config.visualFeedback.intensity
                    ) {
                        ForEach(VisualFeedbackIntensity.allCases) { intensity in
                            Text(intensity.title).tag(intensity)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(
                        width: GeneralSettingsChrome.controlClusterWidth,
                        alignment: .trailing
                    )
                }

                Divider().opacity(0.55)

                SettingsRow(title: L10n.text("Frame target")) {
                    Picker(
                        L10n.text("Frame target"),
                        selection: $config.visualFeedback.frameTarget
                    ) {
                        ForEach(BlueSignalFrameTarget.allCases) { target in
                            Text(target.title).tag(target)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(
                        width: GeneralSettingsChrome.controlClusterWidth,
                        alignment: .trailing
                    )
                }
            }

            if config.visualFeedback.mode != .hidden {
                Divider().opacity(0.55)

                SettingsRow(
                    title: L10n.text(
                        "Show status text when an action needs explanation"
                    )
                ) {
                    Toggle(
                        L10n.text(
                            "Show status text when an action needs explanation"
                        ),
                        isOn: $config.visualFeedback.showStatusText
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                }
            }

            Divider().opacity(0.55)

            SettingsRow(title: L10n.text("Feedback sounds")) {
                Toggle(
                    L10n.text("Feedback sounds"),
                    isOn: $config.transcription.feedbackSoundsEnabled
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            Divider().opacity(0.55)

            SettingsRow(title: L10n.text("Completion notification")) {
                Toggle(
                    L10n.text("Completion notification"),
                    isOn: $config.visualFeedback
                        .completionNotificationEnabled
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            Divider().opacity(0.55)

            SettingsRow(title: L10n.text("Always reduce motion")) {
                Toggle(
                    L10n.text("Always reduce motion"),
                    isOn: $config.visualFeedback.alwaysReduceMotion
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }
        }
    }

    // MARK: - Context & Privacy

    /// What Skills may read during dictation / rewrite.
    private var contextSourcesCard: some View {
        settingsCard(title: "Context", style: .grouped) {
            ForEach(
                Array(
                    ContextSourceKind.userVisibleSettingsSources.enumerated()
                ),
                id: \.element.id
            ) { index, source in
                if index > 0 {
                    Divider().opacity(0.55)
                }
                contextSourceRow(source)
            }

            if config.context.selectionEnabled {
                Divider().opacity(0.55)
                SettingsRow(
                    title: L10n.text("Maximum selected text")
                ) {
                    Picker(
                        L10n.text("Maximum selected text"),
                        selection: $config.context.maximumSelectionCharacters
                    ) {
                        Text(L10n.text("2,000 characters")).tag(2_000)
                        Text(L10n.text("6,000 characters")).tag(6_000)
                        Text(L10n.text("12,000 characters")).tag(12_000)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(
                        width: GeneralSettingsChrome.controlClusterWidth,
                        alignment: .trailing
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func contextSourceRow(_ source: ContextSourceKind) -> some View {
        let available = source.isAvailableInCurrentRuntime
        let isVoice = source == .voice
        SettingsRow(title: source.title) {
            if available, !isVoice {
                Toggle(
                    L10n.text("Enabled"),
                    isOn: Binding(
                        get: {
                            config.context.setting(for: source).isEnabled
                        },
                        set: { enabled in
                            config.context.setSourceEnabled(
                                enabled,
                                source: source
                            )
                        }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            } else if isVoice {
                Text(L10n.text("Required"))
                    .font(VibeComposeTypography.callout(.medium))
                    .foregroundStyle(.secondary)
                    .frame(
                        width: GeneralSettingsChrome.controlClusterWidth,
                        alignment: .trailing
                    )
            } else {
                Text(L10n.text("Coming soon"))
                    .font(VibeComposeTypography.callout(.medium))
                    .foregroundStyle(.tertiary)
                    .frame(
                        width: GeneralSettingsChrome.controlClusterWidth,
                        alignment: .trailing
                    )
            }
        }
    }

    /// Per-Skill selection access. Hidden when no Skill requests selection.
    @ViewBuilder
    private var skillPermissionsCard: some View {
        let skills = availableSkillRegistry.orderedDefinitions.filter {
            $0.allCapabilities.contains(.selection)
        }
        if !skills.isEmpty {
            settingsCard(title: "Skill Permissions", style: .grouped) {
                ForEach(Array(skills.enumerated()), id: \.element.id) { index, skill in
                    if index > 0 {
                        Divider().opacity(0.55)
                    }
                    SettingsRow(title: skill.localizedName) {
                        Picker(
                            skill.localizedName,
                            selection: Binding(
                                get: {
                                    config.context.scope(
                                        skillID: skill.id,
                                        capability: .selection
                                    )
                                },
                                set: { scope in
                                    config.context.setScope(
                                        scope,
                                        skillID: skill.id,
                                        capability: .selection
                                    )
                                }
                            )
                        ) {
                            ForEach(SkillPermissionScope.allCases) { scope in
                                Text(scope.title).tag(scope)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(
                            width: GeneralSettingsChrome.controlClusterWidth,
                            alignment: .trailing
                        )
                        .disabled(!config.context.selectionEnabled)
                    }
                }

                if !config.context.permissionGrants.isEmpty {
                    Divider().opacity(0.55)
                    SettingsRow(
                        title: L10n.text("Reset Permissions"),
                        detail: L10n.text(
                            "Clear saved Skill access for selected text."
                        )
                    ) {
                        Button(L10n.text("Reset")) {
                            config.context.revokeAll()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var contextReceiptsCard: some View {
        settingsCard(title: "Receipts", style: .grouped) {
            SettingsRow(
                title: L10n.text("Context Receipts")
            ) {
                Picker(
                    L10n.text("Context Receipts"),
                    selection: $config.context.retentionPolicy
                ) {
                    Text(L10n.text("Session only"))
                        .tag(ContextRetentionPolicy.sessionOnly)
                    Text(L10n.text("Keep redacted receipts"))
                        .tag(ContextRetentionPolicy.redactedReceipts)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(
                    width: GeneralSettingsChrome.controlClusterWidth,
                    alignment: .trailing
                )
            }

            if config.context.retentionPolicy == .redactedReceipts,
               !config.context.recentReceipts.isEmpty
            {
                Divider().opacity(0.55)
                VStack(alignment: .leading, spacing: VibeComposeMetrics.space8) {
                    Text(L10n.text("Recent"))
                        .font(VibeComposeTypography.caption(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(
                        config.context.recentReceipts.suffix(5).reversed()
                    ) { receipt in
                        HStack(spacing: VibeComposeMetrics.space8) {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(
                                receipt.grantedSources
                                    .map(\.title)
                                    .joined(separator: ", ")
                            )
                            .font(VibeComposeTypography.caption())
                            .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(
                                receipt.createdAt.formatted(
                                    date: .omitted,
                                    time: .shortened
                                )
                            )
                            .font(VibeComposeTypography.caption())
                            .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, VibeComposeMetrics.space4)
            }
        }
    }

    /// What VibeCompose stores on this Mac.
    private var localDataCard: some View {
        settingsCard(title: "On This Mac", style: .grouped) {
            SettingsRow(
                title: L10n.text("Transcript history"),
                detail: L10n.text("Keep recent dictations for History.")
            ) {
                Toggle(
                    L10n.text("Transcript history"),
                    isOn: $config.privacy.historyEnabled
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            if config.privacy.historyEnabled {
                Divider().opacity(0.55)
                SettingsRow(title: L10n.text("Raw ASR transcript")) {
                    Toggle(
                        L10n.text("Raw ASR transcript"),
                        isOn: $config.privacy.storeRawTranscripts
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                }
                Divider().opacity(0.55)
                SettingsRow(title: L10n.text("History retention")) {
                    Stepper(
                        value: $config.privacy.historyRetentionDays,
                        in: 1...3_650
                    ) {
                        Text(
                            L10n.format(
                                "%ld days",
                                config.privacy.historyRetentionDays
                            )
                        )
                        .font(VibeComposeTypography.callout())
                        .frame(
                            width: GeneralSettingsChrome.controlClusterWidth - 44,
                            alignment: .trailing
                        )
                    }
                }
                Divider().opacity(0.55)
                SettingsRow(title: L10n.text("History limit")) {
                    Stepper(
                        value: $config.privacy.historyRecordLimit,
                        in: 10...10_000,
                        step: 50
                    ) {
                        Text(
                            L10n.format(
                                "%ld records",
                                config.privacy.historyRecordLimit
                            )
                        )
                        .font(VibeComposeTypography.callout())
                        .frame(
                            width: GeneralSettingsChrome.controlClusterWidth - 44,
                            alignment: .trailing
                        )
                    }
                }
            }

            Divider().opacity(0.55)

            SettingsRow(
                title: L10n.text("Failed recordings"),
                detail: L10n.text("Keep audio briefly so failed dictations can retry.")
            ) {
                Toggle(
                    L10n.text("Failed recordings"),
                    isOn: $config.privacy.failedAudioRecoveryEnabled
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            if config.privacy.failedAudioRecoveryEnabled {
                Divider().opacity(0.55)
                SettingsRow(title: L10n.text("Recording retention")) {
                    Stepper(
                        value: $config.privacy.failedAudioRetentionHours,
                        in: 1...168
                    ) {
                        Text(
                            L10n.format(
                                "%ld hours",
                                config.privacy.failedAudioRetentionHours
                            )
                        )
                        .font(VibeComposeTypography.callout())
                        .frame(
                            width: GeneralSettingsChrome.controlClusterWidth - 44,
                            alignment: .trailing
                        )
                    }
                }
                Divider().opacity(0.55)
                SettingsRow(title: L10n.text("Recording limit")) {
                    Stepper(
                        value: $config.privacy.failedAudioRecordLimit,
                        in: 1...100
                    ) {
                        Text(
                            L10n.format(
                                "%ld recordings",
                                config.privacy.failedAudioRecordLimit
                            )
                        )
                        .font(VibeComposeTypography.callout())
                        .frame(
                            width: GeneralSettingsChrome.controlClusterWidth - 44,
                            alignment: .trailing
                        )
                    }
                }
            }

            Divider().opacity(0.55)

            SettingsRow(
                title: L10n.text("Diagnostics"),
                detail: L10n.text("Local performance traces for troubleshooting.")
            ) {
                Toggle(
                    L10n.text("Diagnostics"),
                    isOn: $config.privacy.diagnosticsEnabled
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            if config.privacy.diagnosticsEnabled {
                Divider().opacity(0.55)
                SettingsRow(title: L10n.text("Diagnostics retention")) {
                    Stepper(
                        value: $config.privacy.diagnosticsRetentionDays,
                        in: 1...365
                    ) {
                        Text(
                            L10n.format(
                                "%ld days",
                                config.privacy.diagnosticsRetentionDays
                            )
                        )
                        .font(VibeComposeTypography.callout())
                        .frame(
                            width: GeneralSettingsChrome.controlClusterWidth - 44,
                            alignment: .trailing
                        )
                    }
                }
                Divider().opacity(0.55)
                SettingsRow(title: L10n.text("Diagnostics limit")) {
                    Stepper(
                        value: $config.privacy.diagnosticsRecordLimit,
                        in: 100...20_000,
                        step: 100
                    ) {
                        Text(
                            L10n.format(
                                "%ld records",
                                config.privacy.diagnosticsRecordLimit
                            )
                        )
                        .font(VibeComposeTypography.callout())
                        .frame(
                            width: GeneralSettingsChrome.controlClusterWidth - 44,
                            alignment: .trailing
                        )
                    }
                }
            }

            Divider().opacity(0.55)

            SettingsRow(
                title: L10n.text("Product metrics"),
                detail: L10n.text(
                    "Anonymous local counters. Never includes transcript text."
                )
            ) {
                Toggle(
                    L10n.text("Product metrics"),
                    isOn: $config.privacy.productMetricsEnabled
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            if config.privacy.productMetricsEnabled {
                Divider().opacity(0.55)
                SettingsRow(title: L10n.text("Metrics retention")) {
                    Stepper(
                        value: $config.privacy.productMetricsRetentionDays,
                        in: 1...365
                    ) {
                        Text(
                            L10n.format(
                                "%ld days",
                                config.privacy.productMetricsRetentionDays
                            )
                        )
                        .font(VibeComposeTypography.callout())
                        .frame(
                            width: GeneralSettingsChrome.controlClusterWidth - 44,
                            alignment: .trailing
                        )
                    }
                }
                Divider().opacity(0.55)
                SettingsRow(title: L10n.text("Metrics limit")) {
                    Stepper(
                        value: $config.privacy.productMetricsRecordLimit,
                        in: 100...50_000,
                        step: 100
                    ) {
                        Text(
                            L10n.format(
                                "%ld events",
                                config.privacy.productMetricsRecordLimit
                            )
                        )
                        .font(VibeComposeTypography.callout())
                        .frame(
                            width: GeneralSettingsChrome.controlClusterWidth - 44,
                            alignment: .trailing
                        )
                    }
                }
                Divider().opacity(0.55)
                SettingsRow(title: L10n.text("Export")) {
                    Button(L10n.text("Export…")) {
                        exportProductMetrics()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if let productMetricsExportMessage {
                    Text(productMetricsExportMessage)
                        .font(VibeComposeTypography.caption())
                        .foregroundStyle(
                            productMetricsExportMessageIsError
                                ? Color(nsColor: VibeComposePalette.error)
                                : .secondary
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var privacyActionsCard: some View {
        settingsCard(title: "Privacy", style: .grouped) {
            SettingsRow(
                title: L10n.text("Sensitive apps"),
                detail: L10n.text(
                    "Do not save history or recovery audio for sensitive apps"
                )
            ) {
                Toggle(
                    L10n.text("Sensitive apps"),
                    isOn: $config.privacy.excludeSensitiveApps
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            Divider().opacity(0.55)

            SettingsRow(
                title: L10n.text("Delete all local data"),
                detail: L10n.text(
                    "Removes history, recovery audio, diagnostics, and metrics on this Mac."
                )
            ) {
                Button(L10n.text("Delete All Data")) {
                    showsDeleteAllDataConfirmation = true
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
            }

            if let privacyMessage {
                Text(privacyMessage)
                    .font(VibeComposeTypography.caption())
                    .foregroundStyle(
                        privacyMessageIsError
                            ? Color(nsColor: VibeComposePalette.error)
                            : .secondary
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, VibeComposeMetrics.space4)
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
            refreshCommunitySkillInventory()
            privacyMessage = L10n.text("All VibeCompose data was deleted from this Mac.")
            privacyMessageIsError = false
        case .failure(let error):
            privacyMessage = error.localizedDescription
            privacyMessageIsError = true
        }
    }

    private var usesOwnDictationAPI: Bool {
        config.transcription.provider == .openAICompatible
    }

    private var usesOwnPolishAPI: Bool {
        config.transcription.textPolish.openAICompatibleEnabled
    }

    private var accountDictationModelLabel: String {
        L10n.text("Managed")
    }

    private var advancedRecognitionCard: some View {
        settingsCard(title: "Recognition", style: .grouped) {
            advancedSourceTabBar(
                selection: Binding(
                    get: {
                        usesOwnDictationAPI
                            ? AdvancedAPISource.ownAPI
                            : AdvancedAPISource.account
                    },
                    set: { selectDictationSource($0) }
                )
            )
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(title: L10n.text("Model")) {
                    if usesOwnDictationAPI {
                        modelPicker(
                            selection: Binding(
                                get: { config.transcription.openAIModel },
                                set: { newValue in
                                    config.transcription.openAIModel = newValue
                                    recoveryModelDraft = newValue
                                }
                            ),
                            presets: availableDictationModels,
                            isEnabled: true
                        )
                    } else {
                        // Account ASR is managed by ChatGPT — model is not selectable.
                        modelPicker(
                            selection: .constant(accountDictationModelLabel),
                            presets: [accountDictationModelLabel],
                            isEnabled: false
                        )
                    }
                }

                Divider().opacity(0.55)

                SettingsRow(title: L10n.text("Compatible Fallback")) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: {
                                config.transcription.openAIFallbackEnabled
                            },
                            set: { setCompatibleFallback($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .disabled(usesOwnDictationAPI)
                }
            }
        }
    }

    private var advancedPolishCard: some View {
        settingsCard(title: "Polish", style: .grouped) {
            advancedSourceTabBar(
                selection: Binding(
                    get: {
                        usesOwnPolishAPI
                            ? AdvancedAPISource.ownAPI
                            : AdvancedAPISource.account
                    },
                    set: { selectPolishSource($0) }
                )
            )
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(title: L10n.text("Model")) {
                    if usesOwnPolishAPI {
                        modelPicker(
                            selection: Binding(
                                get: {
                                    config.transcription.textPolish
                                        .openAICompatibleModel
                                },
                                set: { newValue in
                                    config.transcription.textPolish
                                        .openAICompatibleModel = newValue
                                }
                            ),
                            presets: availablePolishModels,
                            isEnabled: true
                        )
                    } else {
                        HStack(spacing: 8) {
                            modelPicker(
                                selection: Binding(
                                    get: {
                                        config.transcription.textPolish
                                            .chatGPTResponseModel
                                    },
                                    set: { newValue in
                                        config.transcription.textPolish
                                            .chatGPTResponseModel = newValue
                                    }
                                ),
                                presets: availableAccountPolishModels,
                                isEnabled: !isLoadingAccountPolishModels
                            )
                            if isLoadingAccountPolishModels {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                }

                // Errors/fallback reasons only — never “Loaded N account models.”
                if !usesOwnPolishAPI,
                   accountPolishModelsMessageIsError,
                   let accountPolishModelsMessage
                {
                    Text(accountPolishModelsMessage)
                        .font(VibeComposeTypography.caption())
                        .foregroundStyle(Color(nsColor: VibeComposePalette.error))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 6)
                }

                Divider().opacity(0.55)

                SettingsRow(title: L10n.text("Compatible Fallback")) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: {
                                config.transcription.textPolish
                                    .openAIFallbackEnabled
                            },
                            set: { setPolishCompatibleFallback($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .disabled(usesOwnPolishAPI)
                }
            }
        }
    }

    private var advancedAPIAccessRow: some View {
        settingsCard(title: nil, style: .grouped) {
            SettingsRow(title: L10n.text("Own API")) {
                Button(L10n.text("Configure…")) {
                    showsOwnAPIConfigurationSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func advancedSourceTabBar(
        selection: Binding<AdvancedAPISource>
    ) -> some View {
        // Trailing header accessory: fixed intrinsic width so it sits flush
        // right of the section title (System Settings–style).
        Picker(L10n.text("Source"), selection: selection) {
            Text(L10n.text("Account"))
                .tag(AdvancedAPISource.account)
            Text(L10n.text("Own API"))
                .tag(AdvancedAPISource.ownAPI)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(L10n.text("Source"))
    }

    @ViewBuilder
    private func modelPicker(
        selection: Binding<String>,
        presets: [String],
        isEnabled: Bool = true
    ) -> some View {
        let effectivePresets = presets.isEmpty
            ? [selection.wrappedValue].filter { !$0.isEmpty }
            : presets
        let resolvedSelection: String = {
            if effectivePresets.contains(selection.wrappedValue) {
                return selection.wrappedValue
            }
            return effectivePresets.first ?? selection.wrappedValue
        }()
        return Picker("", selection: Binding(
            get: { resolvedSelection },
            set: { newValue in
                guard isEnabled else { return }
                selection.wrappedValue = newValue
            }
        )) {
            ForEach(effectivePresets, id: \.self) { model in
                Text(model).tag(model)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(minWidth: 200, alignment: .trailing)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onAppear {
            if !effectivePresets.contains(selection.wrappedValue),
               let first = effectivePresets.first
            {
                selection.wrappedValue = first
            }
        }
    }

    private var ownAPIConfigurationSheet: some View {
        VStack(alignment: .leading, spacing: VibeComposeMetrics.space16) {
            HStack {
                Text(L10n.text("Own API"))
                    .font(VibeComposeTypography.title2(.semibold))
                Spacer()
                if isDetectingModels {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Picker("", selection: $ownAPIConfigurationTab) {
                Text(L10n.text("Recognition"))
                    .tag(OwnAPIConfigurationTab.recognition)
                Text(L10n.text("Polish"))
                    .tag(OwnAPIConfigurationTab.polish)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch ownAPIConfigurationTab {
                case .recognition:
                    ownAPIRecognitionPane
                case .polish:
                    ownAPIPolishPane
                }
            }

            HStack(spacing: 10) {
                Button(
                    L10n.text(
                        isDetectingModels
                            ? "Detecting…"
                            : "Detect Models"
                    )
                ) {
                    detectAvailableModels(for: ownAPIConfigurationTab)
                }
                .buttonStyle(.bordered)
                .disabled(
                    isDetectingModels
                        || !(
                            ownAPIConfigurationTab == .recognition
                                ? recoveryAPIKeyStored
                                : polishAPIKeyStored
                        )
                )

                if ownAPIConfigurationTab == .recognition {
                    Button(
                        L10n.text(
                            isTestingRecoveryConnection
                                ? "Testing…"
                                : "Test Connection"
                        )
                    ) {
                        testRecoveryConnection()
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        isTestingRecoveryConnection || !recoveryAPIKeyStored
                    )
                } else {
                    Button(
                        L10n.text(
                            isTestingPolishConnection
                                ? "Testing…"
                                : "Test Connection"
                        )
                    ) {
                        testPolishConnection()
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        isTestingPolishConnection || !polishAPIKeyStored
                    )
                }

                Spacer(minLength: 0)

                Button(L10n.text("Done")) {
                    commitRecoveryEndpointDraft()
                    commitPolishEndpointDraft()
                    showsOwnAPIConfigurationSheet = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(VibeComposeMetrics.space20)
        .frame(minWidth: 540, minHeight: 400)
        .onAppear {
            polishEndpointDraft =
                config.transcription.textPolish.openAICompatibleURL
            refreshPolishCredentialState()
            if ownAPIConfigurationTab == .recognition, recoveryAPIKeyStored {
                detectAvailableModels(for: .recognition)
            } else if ownAPIConfigurationTab == .polish, polishAPIKeyStored {
                detectAvailableModels(for: .polish)
            }
        }
    }

    private var ownAPIRecognitionPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(title: L10n.text("Endpoint")) {
                TextField(
                    "",
                    text: $recoveryEndpointDraft,
                    prompt: Text(
                        "https://api.openai.com/v1/audio/transcriptions"
                    )
                )
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(minWidth: 260, maxWidth: 420)
                .onSubmit {
                    commitRecoveryEndpointDraft()
                }
            }

            Divider().opacity(0.55)

            SettingsRow(title: L10n.text("API Key")) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        SecureField(
                            "",
                            text: $recoveryAPIKeyInput,
                            prompt: Text(L10n.text("Enter a replacement API key"))
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 160, idealWidth: 240, maxWidth: .infinity)

                        Button(L10n.text("Save API Key")) {
                            saveRecoveryAPIKey()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            recoveryAPIKeyInput
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )

                        Button(L10n.text("Remove API Key"), role: .destructive) {
                            removeRecoveryAPIKey()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!recoveryAPIKeyStored)
                    }
                    VStack(alignment: .trailing, spacing: 8) {
                        SecureField(
                            "",
                            text: $recoveryAPIKeyInput,
                            prompt: Text(L10n.text("Enter a replacement API key"))
                        )
                        .textFieldStyle(.roundedBorder)
                        HStack {
                            Button(L10n.text("Save API Key")) {
                                saveRecoveryAPIKey()
                            }
                            .buttonStyle(.borderedProminent)
                            Button(L10n.text("Remove API Key"), role: .destructive) {
                                removeRecoveryAPIKey()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if let recoveryMessage {
                Text(recoveryMessage)
                    .font(VibeComposeTypography.caption())
                    .foregroundStyle(
                        recoveryMessageIsError
                            ? Color(nsColor: VibeComposePalette.error)
                            : .secondary
                    )
                    .textSelection(.enabled)
                    .padding(.top, VibeComposeMetrics.space8)
            }
        }
        .padding(VibeComposeMetrics.space12)
        .background(
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusM,
                style: .continuous
            )
            .fill(Color(nsColor: VibeComposePalette.insetSurface))
        )
    }

    private var ownAPIPolishPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(title: L10n.text("Endpoint")) {
                TextField(
                    "",
                    text: $polishEndpointDraft,
                    prompt: Text(
                        "https://api.openai.com/v1/chat/completions"
                    )
                )
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(minWidth: 260, maxWidth: 420)
                .onSubmit {
                    commitPolishEndpointDraft()
                }
            }

            Divider().opacity(0.55)

            SettingsRow(title: L10n.text("API Key")) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        SecureField(
                            "",
                            text: $polishAPIKeyInput,
                            prompt: Text(L10n.text("Enter a replacement API key"))
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 160, idealWidth: 240, maxWidth: .infinity)

                        Button(L10n.text("Save API Key")) {
                            savePolishAPIKey()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            polishAPIKeyInput
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )

                        Button(L10n.text("Remove API Key"), role: .destructive) {
                            removePolishAPIKey()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!polishAPIKeyStored)
                    }
                    VStack(alignment: .trailing, spacing: 8) {
                        SecureField(
                            "",
                            text: $polishAPIKeyInput,
                            prompt: Text(L10n.text("Enter a replacement API key"))
                        )
                        .textFieldStyle(.roundedBorder)
                        HStack {
                            Button(L10n.text("Save API Key")) {
                                savePolishAPIKey()
                            }
                            .buttonStyle(.borderedProminent)
                            Button(L10n.text("Remove API Key"), role: .destructive) {
                                removePolishAPIKey()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if let polishMessage {
                Text(polishMessage)
                    .font(VibeComposeTypography.caption())
                    .foregroundStyle(
                        polishMessageIsError
                            ? Color(nsColor: VibeComposePalette.error)
                            : .secondary
                    )
                    .textSelection(.enabled)
                    .padding(.top, VibeComposeMetrics.space8)
            }
        }
        .padding(VibeComposeMetrics.space12)
        .background(
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusM,
                style: .continuous
            )
            .fill(Color(nsColor: VibeComposePalette.insetSurface))
        )
    }

    private enum OwnAPIConfigurationTab: String, Hashable {
        case recognition
        case polish
    }

    private enum AdvancedAPISource: String, Hashable {
        case account
        case ownAPI
    }

    private var canEnableUserOwnedAPI: Bool {
        recoveryAPIKeyStored
            && !config.transcription.openAITranscriptionURL
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            && !config.transcription.openAIModel
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
    }

    private func selectDictationSource(_ source: AdvancedAPISource) {
        switch source {
        case .account:
            config.transcription.provider = .chatGPTManagedAuth
            recoveryMessage = nil
            recoveryMessageIsError = false
        case .ownAPI:
            if !canEnableUserOwnedAPI {
                ownAPIConfigurationTab = .recognition
                showsOwnAPIConfigurationSheet = true
                recoveryMessage = L10n.text(
                    "Save an API key, endpoint, and dictation model before importing your own API."
                )
                recoveryMessageIsError = true
                return
            }
            showsAdvancedRecovery = true
        }
    }

    private func selectPolishSource(_ source: AdvancedAPISource) {
        switch source {
        case .account:
            config.transcription.textPolish.chatGPTAuthEnabled = true
            config.transcription.textPolish.openAICompatibleEnabled = false
            refreshAccountPolishModels(force: true)
        case .ownAPI:
            guard polishAPIKeyStored else {
                ownAPIConfigurationTab = .polish
                showsOwnAPIConfigurationSheet = true
                polishMessage = L10n.text(
                    "Save an API key before using Own API for polish."
                )
                polishMessageIsError = true
                return
            }
            let url = config.transcription.textPolish.openAICompatibleURL
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let model = config.transcription.textPolish.openAICompatibleModel
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty, !model.isEmpty else {
                ownAPIConfigurationTab = .polish
                showsOwnAPIConfigurationSheet = true
                polishMessage = L10n.text(
                    "Save an endpoint and model before using Own API for polish."
                )
                polishMessageIsError = true
                return
            }
            config.transcription.textPolish.chatGPTAuthEnabled = false
            config.transcription.textPolish.openAICompatibleEnabled = true
            config.transcription.textPolish.openAIFallbackEnabled = false
            polishMessage = nil
            polishMessageIsError = false
        }
    }

    /// Load ChatGPT account models from the managed Codex catalog for the Account polish picker.
    private func refreshAccountPolishModels(force: Bool) {
        guard !usesOwnPolishAPI else { return }
        if isLoadingAccountPolishModels, !force { return }

        isLoadingAccountPolishModels = true
        Task { @MainActor in
            defer { isLoadingAccountPolishModels = false }

            let token: String?
            if authSnapshot.state == .ready || authSnapshot.state == .expired {
                token = try? await authManager.bestAvailableAccessToken()
            } else {
                token = nil
            }

            let snapshot = await ChatGPTAccountModelCatalog.shared.resolveForPicker(
                accessToken: token,
                forceRefresh: force
            )

            applyAccountPolishModelSnapshot(snapshot)
        }
    }

    private func applyAccountPolishModelSnapshot(
        _ snapshot: ChatGPTAccountModelCatalogSnapshot
    ) {
        let slugs = snapshot.pickerSlugs
        availableAccountPolishModels = slugs.isEmpty
            ? ProductModelCatalog.rewritePresets
            : slugs

        // Keep the user's selection when still available; otherwise pick catalog default.
        let current = config.transcription.textPolish.chatGPTResponseModel
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !availableAccountPolishModels.contains(current) {
            if let preferred = snapshot.defaultSlug,
               availableAccountPolishModels.contains(preferred)
            {
                config.transcription.textPolish.chatGPTResponseModel = preferred
            } else if let first = availableAccountPolishModels.first {
                config.transcription.textPolish.chatGPTResponseModel = first
            }
        }

        if snapshot.usedFallbackPresets {
            accountPolishModelsMessage = snapshot.message
                ?? L10n.text(
                    "Account model list unavailable. Showing built-in presets."
                )
            accountPolishModelsMessageIsError = true
        } else {
            // Live catalog loaded — keep the card quiet (no “Loaded N models” caption).
            accountPolishModelsMessage = nil
            accountPolishModelsMessageIsError = false
        }
    }

    private func setPolishCompatibleFallback(_ enabled: Bool) {
        if enabled {
            if usesOwnPolishAPI {
                return
            }
            guard polishAPIKeyStored else {
                ownAPIConfigurationTab = .polish
                showsOwnAPIConfigurationSheet = true
                polishMessage = L10n.text(
                    "Save a polish API key before enabling Compatible Fallback."
                )
                polishMessageIsError = true
                return
            }
            config.transcription.textPolish.chatGPTAuthEnabled = true
            config.transcription.textPolish.openAICompatibleEnabled = false
            config.transcription.textPolish.openAIFallbackEnabled = true
            polishMessage = nil
            polishMessageIsError = false
        } else {
            config.transcription.textPolish.openAIFallbackEnabled = false
        }
    }

    private func setCompatibleFallback(_ enabled: Bool) {
        if enabled {
            if usesOwnDictationAPI {
                return
            }
            guard canEnableUserOwnedAPI else {
                ownAPIConfigurationTab = .recognition
                showsOwnAPIConfigurationSheet = true
                recoveryMessage = L10n.text(
                    "Save an API key, endpoint, and dictation model before enabling Compatible Fallback."
                )
                recoveryMessageIsError = true
                return
            }
            config.transcription.provider = .chatGPTManagedAuth
            config.transcription.openAIFallbackEnabled = true
            recoveryMessage = nil
            recoveryMessageIsError = false
        } else {
            config.transcription.openAIFallbackEnabled = false
        }
    }

    private func activateImportOwnAPI() {
        do {
            try validateUserOwnedAPIConfiguration()
            recoveryAPIKeyStored = true
            config.transcription.provider = .openAICompatible
            config.transcription.openAIFallbackEnabled = false
            recoveryMessage = nil
            recoveryMessageIsError = false
            detectAvailableModels(for: .recognition)
        } catch {
            recoveryMessage = error.localizedDescription
            recoveryMessageIsError = true
            recoveryAPIKeyStored =
                (try? recoveryCredentialStore.hasAPIKey()) ?? false
            showsOwnAPIConfigurationSheet = true
        }
    }

    private func validateUserOwnedAPIConfiguration() throws {
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
    }

    private func detectAvailableModels(
        for tab: OwnAPIConfigurationTab = .recognition
    ) {
        guard !isDetectingModels else { return }
        isDetectingModels = true
        if tab == .recognition {
            recoveryMessage = nil
            recoveryMessageIsError = false
        } else {
            polishMessage = nil
            polishMessageIsError = false
        }

        let store: any OpenAICompatibleCredentialPersisting =
            tab == .recognition
            ? recoveryCredentialStore
            : polishCredentialStore
        let endpoint: String =
            tab == .recognition
            ? config.transcription.openAITranscriptionURL
            : config.transcription.textPolish.openAICompatibleURL

        Task { @MainActor in
            defer { isDetectingModels = false }
            do {
                guard let apiKey = try store.loadAPIKey(), !apiKey.isEmpty else {
                    let message = L10n.text(
                        "Save an API key before detecting models."
                    )
                    if tab == .recognition {
                        recoveryMessage = message
                        recoveryMessageIsError = true
                    } else {
                        polishMessage = message
                        polishMessageIsError = true
                    }
                    return
                }

                let modelsURL = try Self.modelsListURL(fromEndpoint: endpoint)
                var request = URLRequest(url: modelsURL)
                request.httpMethod = "GET"
                request.setValue(
                    "Bearer \(apiKey)",
                    forHTTPHeaderField: "Authorization"
                )
                request.setValue(
                    ProductIdentity.userAgent,
                    forHTTPHeaderField: "User-Agent"
                )

                let (data, response) = try await SecureHTTPClient.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode)
                else {
                    throw TextPolishError.requestFailed(
                        L10n.text("Model list request failed.")
                    )
                }

                let ids = Self.parseModelIDs(from: data)
                if ids.isEmpty {
                    if tab == .recognition {
                        availableDictationModels =
                            ProductModelCatalog.dictationPresets
                        recoveryMessage = L10n.text(
                            "No models returned. Using built-in presets."
                        )
                        recoveryMessageIsError = false
                    } else {
                        availablePolishModels =
                            ProductModelCatalog.rewritePresets
                        polishMessage = L10n.text(
                            "No models returned. Using built-in presets."
                        )
                        polishMessageIsError = false
                    }
                    return
                }

                if tab == .recognition {
                    let dictation = ids.filter { id in
                        let lower = id.lowercased()
                        return lower.contains("transcribe")
                            || lower.contains("whisper")
                    }
                    availableDictationModels = dictation.isEmpty
                        ? ProductModelCatalog.dictationPresets
                        : Self.mergePreservingOrder(
                            preferred: ProductModelCatalog.dictationPresets,
                            extra: dictation
                        )
                    if !availableDictationModels.contains(
                        config.transcription.openAIModel
                    ),
                       let first = availableDictationModels.first
                    {
                        config.transcription.openAIModel = first
                        recoveryModelDraft = first
                    }
                    recoveryMessage = L10n.format(
                        "Detected %d models.",
                        ids.count
                    )
                    recoveryMessageIsError = false
                } else {
                    let chat = ids.filter { id in
                        let lower = id.lowercased()
                        return !lower.contains("transcribe")
                            && !lower.contains("whisper")
                            && !lower.contains("embedding")
                            && !lower.contains("tts")
                            && !lower.contains("dall-e")
                            && !lower.contains("moderation")
                    }
                    availablePolishModels = chat.isEmpty
                        ? ProductModelCatalog.rewritePresets
                        : Self.mergePreservingOrder(
                            preferred: ProductModelCatalog.rewritePresets,
                            extra: chat
                        )
                    if !availablePolishModels.contains(
                        config.transcription.textPolish.openAICompatibleModel
                    ),
                       let first = availablePolishModels.first
                    {
                        config.transcription.textPolish
                            .openAICompatibleModel = first
                    }
                    polishMessage = L10n.format(
                        "Detected %d models.",
                        ids.count
                    )
                    polishMessageIsError = false
                }
            } catch {
                if tab == .recognition {
                    recoveryMessage = error.localizedDescription
                    recoveryMessageIsError = true
                } else {
                    polishMessage = error.localizedDescription
                    polishMessageIsError = true
                }
            }
        }
    }

    private static func modelsListURL(fromEndpoint endpoint: String) throws -> URL {
        let url = try ManagedEndpointPolicy.validatedUserOwnedURL(endpoint)
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            throw TextPolishError.providerUnavailable
        }
        var path = components.path
        for suffix in [
            "/audio/transcriptions",
            "/chat/completions",
            "/responses",
            "/completions",
        ] {
            if path.hasSuffix(suffix) {
                path = String(path.dropLast(suffix.count))
                break
            }
        }
        if path.hasSuffix("/") {
            path = String(path.dropLast())
        }
        if path.hasSuffix("/v1") {
            path += "/models"
        } else if let range = path.range(of: "/v1") {
            path = String(path[..<range.upperBound]) + "/models"
        } else {
            path += path.isEmpty ? "/v1/models" : "/models"
        }
        components.path = path
        components.query = nil
        components.fragment = nil
        guard let result = components.url else {
            throw TextPolishError.providerUnavailable
        }
        return result
    }

    private static func parseModelIDs(from data: Data) -> [String] {
        guard
            let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            let list = object["data"] as? [[String: Any]]
        else {
            return []
        }
        var seen = Set<String>()
        var ids: [String] = []
        for item in list {
            guard let id = item["id"] as? String else { continue }
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            ids.append(trimmed)
        }
        return ids.sorted()
    }

    private static func mergePreservingOrder(
        preferred: [String],
        extra: [String]
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in preferred + extra {
            if seen.insert(id).inserted {
                result.append(id)
            }
        }
        return result
    }

    private var recoveryAPIKeyField: some View {
        SecureField(
            "",
            text: $recoveryAPIKeyInput,
            prompt: Text(
                L10n.text("Enter a replacement API key")
            )
        )
        .textFieldStyle(.roundedBorder)
        .labelsHidden()
        .frame(
            minWidth: 160,
            idealWidth: 260,
            maxWidth: .infinity
        )
    }

    private var recoveryAPIKeyActions: some View {
        HStack(spacing: 8) {
            Button(L10n.text("Save API Key")) {
                saveRecoveryAPIKey()
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                recoveryAPIKeyInput
                    .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func refreshRecoveryCredentialState() {
        let store = recoveryCredentialStore
        Task {
            let result: Result<Bool, any Error> = await Task.detached(priority: .utility) {
                Result { try store.hasAPIKey() }
            }.value
            guard !Task.isCancelled else {
                return
            }
            switch result {
            case .success(let isStored):
                recoveryAPIKeyStored = isStored
                if recoveryMessageIsError {
                    recoveryMessage = nil
                    recoveryMessageIsError = false
                }
            case .failure(let error):
                recoveryAPIKeyStored = false
                recoveryMessage = error.localizedDescription
                recoveryMessageIsError = true
            }
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
            detectAvailableModels(for: .recognition)
        } catch {
            recoveryMessage = error.localizedDescription
            recoveryMessageIsError = true
            refreshRecoveryCredentialState()
        }
    }

    private func removeRecoveryAPIKey() {
        do {
            try recoveryCredentialStore.deleteAPIKey()
            recoveryAPIKeyInput = ""
            recoveryAPIKeyStored = false
            if config.transcription.provider == .openAICompatible
                || config.transcription.openAIFallbackEnabled
            {
                config.transcription.provider = .chatGPTManagedAuth
                config.transcription.openAIFallbackEnabled = false
                recoveryMessage = L10n.text(
                    "API key removed. Switched back to ChatGPT account."
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

    private func commitPolishEndpointDraft() {
        let trimmed = polishEndpointDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            config.transcription.textPolish.openAICompatibleURL = trimmed
        }
        polishEndpointDraft =
            config.transcription.textPolish.openAICompatibleURL
    }

    private func refreshPolishCredentialState() {
        let store = polishCredentialStore
        Task {
            let result: Result<Bool, any Error> = await Task.detached(
                priority: .utility
            ) {
                Result { try store.hasAPIKey() }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let isStored):
                polishAPIKeyStored = isStored
            case .failure:
                polishAPIKeyStored = false
            }
        }
    }

    private func savePolishAPIKey() {
        do {
            try polishCredentialStore.saveAPIKey(polishAPIKeyInput)
            polishAPIKeyInput = ""
            polishAPIKeyStored = true
            polishMessage = L10n.text(
                "OpenAI-Compatible API key saved in Keychain."
            )
            polishMessageIsError = false
            detectAvailableModels(for: .polish)
        } catch {
            polishMessage = error.localizedDescription
            polishMessageIsError = true
            refreshPolishCredentialState()
        }
    }

    private func removePolishAPIKey() {
        do {
            try polishCredentialStore.deleteAPIKey()
            polishAPIKeyInput = ""
            polishAPIKeyStored = false
            if config.transcription.textPolish.openAICompatibleEnabled
                || config.transcription.textPolish.openAIFallbackEnabled
            {
                config.transcription.textPolish.chatGPTAuthEnabled = true
                config.transcription.textPolish.openAICompatibleEnabled = false
                config.transcription.textPolish.openAIFallbackEnabled = false
                polishMessage = L10n.text(
                    "API key removed. Switched back to ChatGPT account."
                )
            } else {
                polishMessage = L10n.text(
                    "OpenAI-Compatible API key removed from Keychain."
                )
            }
            polishMessageIsError = false
        } catch {
            polishMessage = error.localizedDescription
            polishMessageIsError = true
        }
    }

    private func testPolishConnection() {
        isTestingPolishConnection = true
        polishMessage = L10n.text("Testing polish endpoint…")
        polishMessageIsError = false
        commitPolishEndpointDraft()

        let store = polishCredentialStore
        let endpoint = config.transcription.textPolish.openAICompatibleURL
        let model = config.transcription.textPolish.openAICompatibleModel

        Task { @MainActor in
            defer { isTestingPolishConnection = false }
            do {
                guard let apiKey = try store.loadAPIKey(), !apiKey.isEmpty else {
                    throw OpenAICompatibleConnectionTestError.missingAPIKey
                }
                let url = try ManagedEndpointPolicy.validatedUserOwnedURL(endpoint)
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(
                    "Bearer \(apiKey)",
                    forHTTPHeaderField: "Authorization"
                )
                request.setValue(
                    "application/json",
                    forHTTPHeaderField: "Content-Type"
                )
                request.setValue(
                    ProductIdentity.userAgent,
                    forHTTPHeaderField: "User-Agent"
                )
                let body: [String: Any] = [
                    "model": model,
                    "messages": [
                        ["role": "user", "content": "ping"],
                    ],
                    "max_tokens": 1,
                    "stream": false,
                ]
                request.httpBody = try JSONSerialization.data(
                    withJSONObject: body
                )
                let (data, response) = try await SecureHTTPClient.data(
                    for: request
                )
                guard let http = response as? HTTPURLResponse else {
                    throw TextPolishError.invalidResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    let prefix = String(
                        data: data.prefix(200),
                        encoding: .utf8
                    ) ?? ""
                    throw TextPolishError.requestFailed(
                        "HTTP \(http.statusCode) \(prefix)"
                    )
                }
                polishAPIKeyStored = true
                polishMessage = L10n.text(
                    "Connection succeeded. The polish endpoint accepted the Keychain credential."
                )
                polishMessageIsError = false
            } catch {
                polishMessage = error.localizedDescription
                polishMessageIsError = true
                polishAPIKeyStored =
                    (try? polishCredentialStore.hasAPIKey()) ?? false
            }
        }
    }

    private func testRecoveryConnection() {
        isTestingRecoveryConnection = true
        recoveryMessage = L10n.text(
            "Testing the configured endpoint with generated silence…"
        )
        recoveryMessageIsError = false
        sonnerToasts.loading(
            L10n.text("Testing connection…"),
            detail: L10n.text(
                "Testing the configured endpoint with generated silence…"
            )
        )
        let tester = OpenAICompatibleConnectionTester(
            credentialStore: recoveryCredentialStore
        )
        let transcriptionConfig = config.transcription

        Task { @MainActor in
            do {
                try await tester.test(config: transcriptionConfig)
                recoveryAPIKeyStored = true
                let title = L10n.text(
                    "Connection succeeded. The endpoint accepted the Keychain credential and synthetic audio."
                )
                recoveryMessage = title
                recoveryMessageIsError = false
                sonnerToasts.success(
                    L10n.text("Connection succeeded"),
                    detail: title
                )
            } catch {
                recoveryMessage = error.localizedDescription
                recoveryMessageIsError = true
                recoveryAPIKeyStored =
                    (try? recoveryCredentialStore.hasAPIKey()) ?? false
                sonnerToasts.error(
                    L10n.text("Connection failed"),
                    detail: error.localizedDescription
                )
            }
            isTestingRecoveryConnection = false
        }
    }


    private func activateAdvancedRecovery() {
        activateImportOwnAPI()
    }

    private func switchBackToChatGPT() {
        config.transcription.provider = .chatGPTManagedAuth
        recoveryMessage = nil
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
            sonnerToasts.loading(L10n.text("Checking for updates…"))
        case .failure(let error):
            softwareUpdateMessage = error.localizedDescription
            softwareUpdateMessageIsError = true
            sonnerToasts.error(
                L10n.text("Update check failed"),
                detail: error.localizedDescription
            )
        }
    }


    private func setAutomaticUpdateChecks(_ enabled: Bool) {
        switch onSetAutomaticallyChecksForUpdates(enabled) {
        case .success(let snapshot):
            softwareUpdateSnapshot = snapshot
            let title = enabled
                ? L10n.text("Automatic update checks are enabled.")
                : L10n.text("Automatic update checks are disabled.")
            softwareUpdateMessage = title
            softwareUpdateMessageIsError = false
            sonnerToasts.success(title)
        case .failure(let error):
            softwareUpdateMessage = error.localizedDescription
            softwareUpdateMessageIsError = true
            sonnerToasts.error(
                L10n.text("Could not update settings"),
                detail: error.localizedDescription
            )
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
                .font(VibeComposeTypography.callout(.medium))
                .frame(width: 90, alignment: .leading)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(value))
                    .font(VibeComposeTypography.callout(.semibold))
                Text(detail)
                    .font(VibeComposeTypography.caption())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(12)
        .background(
            Color(nsColor: VibeComposePalette.insetSurface),
            in: RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusM,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusM,
                style: .continuous
            )
            .stroke(
                Color(nsColor: VibeComposePalette.hairline),
                lineWidth: 0.5
            )
        }
    }

    private var aiPolishCard: some View {
        settingsCard(title: "AI Polish", style: .grouped) {
            SettingsRow(title: L10n.text("Mode")) {
                Picker(
                    L10n.text("Mode"),
                    selection: $config.transcription.textPolish.mode
                ) {
                    Text(L10n.text("Auto")).tag(TextPolishMode.automaticWhenKeyAvailable)
                    Text(L10n.text("Always rewrite")).tag(TextPolishMode.always)
                    Text(L10n.text("Off")).tag(TextPolishMode.disabled)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: GeneralSettingsChrome.controlClusterWidth, alignment: .trailing)
            }

            Divider().opacity(0.55)

            SettingsRow(title: L10n.text("Show estimates")) {
                Toggle(
                    L10n.text("Show estimates"),
                    isOn: $config.transcription.textPolish.showCostEstimates
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            Divider().opacity(0.55)

            SettingsRow(title: L10n.text("Connection")) {
                HStack(spacing: VibeComposeMetrics.space8) {
                    if config.transcription.textPolish.openAICompatibleEnabled {
                        if recoveryAPIKeyStored {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(nsColor: VibeComposePalette.success))
                            Text(
                                config.transcription.textPolish
                                    .openAICompatibleModel
                            )
                            .font(VibeComposeTypography.callout(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color(nsColor: VibeComposePalette.amber))
                            Text(L10n.text("Own API"))
                                .font(VibeComposeTypography.caption())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else if authSnapshot.state == .ready {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(nsColor: VibeComposePalette.success))
                        Text(config.transcription.textPolish.chatGPTResponseModel)
                            .font(VibeComposeTypography.callout(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(nsColor: VibeComposePalette.amber))
                        Text(authSnapshot.detail)
                            .font(VibeComposeTypography.caption())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Button(L10n.text("Test Connection")) {
                        testTextPolishSelection()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

        }
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

                if !recentRecoveryItems.isEmpty {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color(nsColor: VibeComposePalette.insetSurface),
            in: RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusM,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusM,
                style: .continuous
            )
            .stroke(
                Color(nsColor: VibeComposePalette.hairline),
                lineWidth: 0.5
            )
        }
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
        .padding(12)
        .background(
            Color(nsColor: VibeComposePalette.insetSurface),
            in: RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusM,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusM,
                style: .continuous
            )
            .stroke(
                Color(nsColor: VibeComposePalette.hairline),
                lineWidth: 0.5
            )
        }
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

            if !items.isEmpty {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color(nsColor: VibeComposePalette.insetSurface),
            in: RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusM,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusM,
                style: .continuous
            )
            .stroke(
                Color(nsColor: VibeComposePalette.hairline),
                lineWidth: 0.5
            )
        }
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
        sonnerToasts.loading(L10n.text("Testing connection…"))
        let openAIKeyAvailable =
            (try? polishCredentialStore.hasAPIKey()) ?? false
        let polish = config.transcription.textPolish
        let selected = TextPolishProviderSelector().selectProvider(
            config: polish,
            chatGPTAuthAvailable: authSnapshot.state == .ready,
            openAICompatibleKeyAvailable: openAIKeyAvailable
        )
        if let selected {
            let model: String
            switch selected.id {
            case .chatGPTAuth:
                model = polish.chatGPTResponseModel
            case .openAICompatible:
                model = polish.openAICompatibleModel
            }
            let title = L10n.format(
                "Ready: %@ / %@.",
                selected.id.title,
                model
            )
            textPolishMessage = title
            textPolishMessageIsError = false
            sonnerToasts.success(title)
        } else if polish.openAICompatibleEnabled {
            let title = L10n.text(
                "OpenAI-Compatible API key is not ready. Save a key first."
            )
            textPolishMessage = title
            textPolishMessageIsError = true
            sonnerToasts.error(title)
        } else {
            let title = L10n.text(
                "ChatGPT Auth is not ready. Connect ChatGPT first."
            )
            textPolishMessage = title
            textPolishMessageIsError = true
            sonnerToasts.error(title)
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
                        Task {
                            await ChatGPTAccountModelCatalog.shared.invalidate()
                        }
                        availableAccountPolishModels = ProductModelCatalog.rewritePresets
                        accountPolishModelsMessage = L10n.text(
                            "Connect ChatGPT before loading account models."
                        )
                        accountPolishModelsMessageIsError = true
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
                        "Browser login connected. VibeCompose saved the ChatGPT session locally."
                    )
                    terminologyImportIsError = false
                    refreshAccountPolishModels(force: true)
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
            .font(VibeComposeTypography.micro(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(color.opacity(0.18), lineWidth: 0.5)
            }
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
            color = Color(nsColor: VibeComposePalette.amber)
        case .connected:
            label = L10n.text("Connected")
            color = Color(nsColor: VibeComposePalette.success)
        case .failed:
            label = L10n.text("Failed")
            color = Color(nsColor: VibeComposePalette.error)
        }

        return Text(label)
            .font(VibeComposeTypography.micro(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(color.opacity(0.18), lineWidth: 0.5)
            }
    }

    private var terminologySummaryRow: some View {
        let entries = config.transcription.terminology.entries
        let termCount = entries.filter { $0.type == .term }.count
        let correctionCount = entries.filter { $0.type == .correction }.count

        return HStack(spacing: 8) {
            terminologyCountBadge(title: "Terms", count: termCount, color: .accentColor)
            terminologyCountBadge(title: "Corrections", count: correctionCount, color: .orange)
            Spacer()
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
        .padding(12)
        .background(
            Color(nsColor: VibeComposePalette.insetSurface),
            in: RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusM,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusM,
                style: .continuous
            )
            .stroke(
                Color(nsColor: VibeComposePalette.hairline),
                lineWidth: 0.5
            )
        }
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
            Text(
                L10n.text(
                    entry.type == .correction ? "Correction" : "Term"
                )
            )
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color(nsColor: VibeComposePalette.insetSurface),
            in: RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusM,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusM,
                style: .continuous
            )
            .stroke(
                Color(nsColor: VibeComposePalette.hairline),
                lineWidth: 0.5
            )
        }
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
        title: String?,
        style: SettingsCardContainer<Content, EmptyView>.Style = .grouped,
        @ViewBuilder content: () -> Content
    ) -> some View {
        SettingsCardContainer(title: title, style: style) {
            content()
        }
    }

    private func settingsCard<Content: View, HeaderAccessory: View>(
        title: String?,
        style: SettingsCardContainer<Content, HeaderAccessory>.Style = .grouped,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        SettingsCardContainer(
            title: title,
            style: style,
            headerAccessory: headerAccessory,
            content: content
        )
    }

    private func setupRow(title: String, status: SetupStatus) -> some View {
        setupRow(title: title, status: status) {
            EmptyView()
        }
    }

    private func compactSetupTile(title: String, status: SetupStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: status.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    status.isReady
                        ? Color(nsColor: VibeComposePalette.success)
                        : Color(nsColor: VibeComposePalette.amber)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(title))
                    .font(VibeComposeTypography.callout(.semibold))
                Text(status.title)
                    .font(VibeComposeTypography.caption())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setupRow<Actions: View>(
        title: String,
        status: SetupStatus,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: VibeComposeMetrics.space10) {
            Image(systemName: status.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(status.isReady ? .green : .orange)
                .font(VibeComposeTypography.callout(.semibold))
                .padding(.top, VibeComposeMetrics.space2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: VibeComposeMetrics.space2) {
                Text(L10n.text(title))
                    .font(VibeComposeTypography.callout(.semibold))
                // Visible subtitle replaces atmospheric accessibilityHint so
                // VoiceOver and sighted users share the same status detail.
                Text(status.title)
                    .font(VibeComposeTypography.callout(.medium))
                if !status.subtitle.isEmpty,
                   status.subtitle != status.title
                {
                    Text(status.subtitle)
                        .font(VibeComposeTypography.caption())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actions()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(L10n.text(title)). \(status.title)"
                    + (
                        status.subtitle.isEmpty
                            || status.subtitle == status.title
                            ? ""
                            : ". \(status.subtitle)"
                    )
            )
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
                        Task {
                            await ChatGPTAccountModelCatalog.shared.invalidate()
                        }
                        availableAccountPolishModels = ProductModelCatalog.rewritePresets
                        accountPolishModelsMessage = L10n.text(
                            "Connect ChatGPT before loading account models."
                        )
                        accountPolishModelsMessageIsError = true
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
            // Guided flow opens System Settings; poll so the tile flips to
            // Granted as soon as TCC trusts this process.
            Task { @MainActor in
                _ = await permissionStatusMonitor.refreshAccessibilityUntilTrusted()
            }
        case .openSettings(let destination):
            _ = destination.open()
            Task { @MainActor in
                _ = await permissionStatusMonitor.refreshAccessibilityUntilTrusted()
            }
        case .refreshStatus:
            permissionMessage = nil
            permissionStatusMonitor.refresh()
            Task { @MainActor in
                _ = await permissionStatusMonitor.refreshAccessibilityUntilTrusted(
                    maximumRefreshAttempts: 8,
                    refreshDelay: .milliseconds(150)
                )
            }
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
                    // Status tiles already show "Granted" — no tip caption.
                    permissionMessage = nil
                    permissionMessageIsError = false
                case .undetermined:
                    permissionMessage = L10n.text(
                        "VibeCompose still cannot confirm microphone access. Click Refresh Status or reopen the app."
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
