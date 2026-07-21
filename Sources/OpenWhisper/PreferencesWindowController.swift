import AppKit
import AVFoundation
import ApplicationServices
import SwiftUI

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

private enum SettingsLayoutMetrics {
    static let sidebarWidth: CGFloat = 236
    static let sidebarTopPadding: CGFloat = 52
    static let sidebarRowVerticalPadding: CGFloat = 5
    static let sidebarRowOuterPadding: CGFloat = 8
    static let sidebarRowInnerPadding: CGFloat = 8
    static let sidebarRowSpacing: CGFloat = 2
    static let sidebarRowCornerRadius: CGFloat = 8
    static let sidebarSectionSpacing: CGFloat = 20
    static let sidebarHeaderRowSpacing: CGFloat = 5
    static let detailHorizontalPadding: CGFloat = 40
    static let detailTopPadding: CGFloat = 32
    /// Embedded library destinations render their own in-content header
    /// (`OpenWhisperPaneHeader`), so the shell only clears the traffic lights.
    static let embeddedTopPadding: CGFloat = 6
}

@MainActor
final class PreferencesWindowController: NSWindowController {
    private var sidebarArrowKeyMonitor: Any?

    init(
        config: AppConfig,
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
        textPolishUsageDirectoryURL: URL? = ProductIdentity
            .applicationSupportURL(
                homeDirectoryURL: FileManager.default.homeDirectoryForCurrentUser
            ),
        softwareUpdateSnapshot: SoftwareUpdateSnapshot,
        onCheckForUpdates: @escaping () -> Result<Void, SoftwareUpdateError>,
        onSetAutomaticallyChecksForUpdates: @escaping (Bool) -> Result<SoftwareUpdateSnapshot, SoftwareUpdateError>,
        onDeleteAllData: @escaping () -> Result<AppConfig, any Error>,
        onOpenOnboarding: @escaping () -> Void,
        onOpenSkillLibrary: @escaping () -> Void,
        onOpenTerminology: @escaping () -> Void,
        onLoadFullTranscriptionHistory: @escaping @Sendable () async -> [TranscriptionHistoryRecord] = { [] },
        onLoadFullRecoveryHistory: @escaping @Sendable () async -> [RecoveryRecord] = { [] },
        onCanUndoTranscriptionRecord: @escaping (UUID) -> Bool = { _ in false },
        onUndoTranscriptionRecord: @escaping (UUID) async -> SafeUndoOutcome = { _ in .unavailable },
        onDeleteTranscriptionRecord: @escaping (UUID) -> Result<Void, any Error> = { _ in .success(()) },
        onDeleteRecoveryRecord: @escaping (UUID) -> Result<Void, any Error> = { _ in .success(()) },
        onUseNextSkill: @escaping (UUID) -> Void = { _ in },
        onRunSkillTest: @escaping (SkillTestRunRequest) async -> Result<SkillTestRunResult, any Error> = { _ in
            .failure(SkillTestRunError.appBusy)
        },
        onVoiceSampleAction: @escaping (SkillVoiceSampleAction) async -> Result<SkillVoiceSampleResult, any Error> = { _ in
            .failure(SkillTestRunError.appBusy)
        },
        onHotkeyCaptureChanged:
            @escaping (Bool) -> Void = { _ in },
        onPreviewVisualFeedback:
            @escaping (
                VisualFeedbackPreview,
                VisualFeedbackConfig
            ) -> Void = { _, _ in },
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
            textPolishUsageDirectoryURL: textPolishUsageDirectoryURL,
            softwareUpdateSnapshot: softwareUpdateSnapshot,
            onCheckForUpdates: onCheckForUpdates,
            onSetAutomaticallyChecksForUpdates: onSetAutomaticallyChecksForUpdates,
            onDeleteAllData: onDeleteAllData,
            onOpenOnboarding: onOpenOnboarding,
            onOpenSkillLibrary:
                onOpenSkillLibrary,
            onOpenTerminology:
                onOpenTerminology,
            onLoadFullTranscriptionHistory:
                onLoadFullTranscriptionHistory,
            onLoadFullRecoveryHistory:
                onLoadFullRecoveryHistory,
            onCanUndoTranscriptionRecord:
                onCanUndoTranscriptionRecord,
            onUndoTranscriptionRecord:
                onUndoTranscriptionRecord,
            onDeleteTranscriptionRecord:
                onDeleteTranscriptionRecord,
            onDeleteRecoveryRecord:
                onDeleteRecoveryRecord,
            onUseNextSkill: onUseNextSkill,
            onRunSkillTest: onRunSkillTest,
            onVoiceSampleAction: onVoiceSampleAction,
            onHotkeyCaptureChanged:
                onHotkeyCaptureChanged,
            onPreviewVisualFeedback:
                onPreviewVisualFeedback,
            skillPackageStore:
                skillPackageStore,
            styleCapsuleStore:
                styleCapsuleStore,
            localAssetAccessEnabled:
                localAssetAccessEnabled,
            focusPane: focusPane,
            skillLibraryInitialSection:
                skillLibraryInitialSection
        )
        .applyingAccessibilityDisplayOptionsOverride(
            .currentVisualAcceptance
        )
        let hostingController = NSHostingController(rootView: view)

        let window = CommandClosingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )
        window.title = ProductIdentity.name
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.hasShadow = true
        // The Settings shell never enters full screen (its fixed sidebar
        // layout is not designed for it), so the zoom control stays disabled.
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.formUnion([.managed, .fullScreenDisallowsTiling])
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        let settingsToolbar = NSToolbar(
            identifier: "OpenWhisper.SettingsToolbar"
        )
        settingsToolbar.displayMode = .iconOnly
        settingsToolbar.allowsUserCustomization = false
        settingsToolbar.autosavesConfiguration = false
        window.toolbar = settingsToolbar
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier("OpenWhisper.SettingsWindow")
        window.minSize = NSSize(width: 900, height: 620)
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

        sidebarArrowKeyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self else {
                return event
            }
            return handleSidebarArrowKey(event)
        }
    }

    isolated deinit {
        if let sidebarArrowKeyMonitor {
            NSEvent.removeMonitor(sidebarArrowKeyMonitor)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else {
            return
        }
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func navigate(to pane: SettingsPane) {
        NotificationCenter.default.post(
            name: .openWhisperNavigateSettingsPane,
            object: nil,
            userInfo: ["pane": pane.rawValue]
        )
        show()
    }

    /// The custom sidebar rows (unlike the previous stock `List`) do not come
    /// with built-in arrow-key navigation, so the window reproduces the native
    /// source-list behavior here: Up/Down moves the sidebar selection unless a
    /// text editor, control, or collection view owns the key event.
    private func handleSidebarArrowKey(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else {
            return event
        }
        guard event.keyCode == 126 || event.keyCode == 125 else {
            return event
        }
        let modifiers = event.modifierFlags.intersection(
            .deviceIndependentFlagsMask
        )
        guard modifiers.isDisjoint(with: [.command, .option, .control]) else {
            return event
        }
        if let responder = window.firstResponder, responder !== window {
            let responderOwnsArrows =
                responder is NSTextView
                || responder is NSControl
                || responder is NSCollectionView
            if responderOwnsArrows {
                return event
            }
        }

        let orderedPanes = SettingsSidebarGroup.allCases
            .flatMap(\.panes)
            .filter { SettingsPane.visiblePanes.contains($0) }
        guard !orderedPanes.isEmpty else {
            return event
        }
        let currentPane = SettingsWindowStateStore()
            .initialPane(focusedPane: nil)
        let currentIndex =
            orderedPanes.firstIndex(of: currentPane) ?? 0
        let nextIndex =
            event.keyCode == 126
            ? max(0, currentIndex - 1)
            : min(orderedPanes.count - 1, currentIndex + 1)
        guard nextIndex != currentIndex else {
            return nil
        }
        NotificationCenter.default.post(
            name: .openWhisperNavigateSettingsPane,
            object: nil,
            userInfo: ["pane": orderedPanes[nextIndex].rawValue]
        )
        return nil
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

/// The macOS 26 source-list backdrop: AppKit's `.sidebar` material renders as
/// Liquid Glass on macOS 26 and as the classic source-list material on earlier
/// releases, sampling the desktop behind the window like System Settings.
private struct SettingsSidebarMaterialView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// macOS 26 source-list row: the selection is a translucent gray glass pill
/// (the product-owner approved `sidebarSelectionBackground`) with the symbol
/// and label tinted in the accent color, matching the Music source list.
private struct SettingsSidebarRowButton: View {
    let pane: SettingsPane
    let isSelected: Bool
    let reduceMotion: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                OpenWhisperSidebarSymbol(systemName: pane.icon)
                Text(pane.displayTitle)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(
                isSelected
                    ? Color(nsColor: OpenWhisperPalette.sidebarSelectionForeground)
                    : .primary
            )
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
                reduceMotion: reduceMotion
            )
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct SettingsSidebarRowButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isHovered: Bool
    let reduceMotion: Bool

    private var rowShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: SettingsLayoutMetrics.sidebarRowCornerRadius,
            style: .continuous
        )
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
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
    }

    private var baseFill: Color {
        if isSelected {
            return Color(nsColor: OpenWhisperPalette.sidebarSelectionBackground)
        }
        return Color.primary.opacity(isHovered ? 0.05 : 0)
    }
}

private enum SettingsSaveStatus: Equatable {
    case saved
    case failed(String)
}

private extension SettingsPane {
    var icon: String {
        switch self {
        case .general:
            return "gearshape"
        case .account:
            return "person.crop.circle"
        case .dictation:
            return "mic"
        case .appearance:
            return "paintbrush"
        case .polish:
            return "wand.and.stars"
        case .context:
            return "hand.raised"
        case .terminology:
            return "text.book.closed"
        case .paste:
            return "doc.on.clipboard"
        case .privacy:
            return "hand.raised"
        case .advanced:
            return "slider.horizontal.3"
        case .skills:
            return "wand.and.stars"
        case .history:
            return "clock.arrow.circlepath"
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
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(selectedDocument.entry.name)
                                .font(.system(size: 24, weight: .semibold))
                                .tracking(-0.3)
                            Text(selectedDocument.entry.pinnedDescription)
                                .font(OpenWhisperTypography.callout())
                                .foregroundStyle(.secondary)
                            OpenWhisperStatusChip(
                                text: selectedDocument.entry.licenseName,
                                kind: .neutral
                            )
                        }

                        Divider().opacity(0.5)

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
                            .padding(14)
                            .background(
                                Color(nsColor: OpenWhisperPalette.insetSurface),
                                in: RoundedRectangle(
                                    cornerRadius: OpenWhisperMetrics.radiusM,
                                    style: .continuous
                                )
                            )
                    }
                    .padding(24)
                }
            } else {
                OpenWhisperEmptyState(
                    systemImage: "doc.text",
                    title: L10n.text("No license selected")
                )
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
    @State private var editingSkillRuleID: UUID?
    @State private var editingSkillAppName = ""
    @State private var editingSkillBundleIdentifier = ""
    @State private var editingSkillID =
        SkillRegistry.replySkillID
    @State private var skillMessage: String?
    @State private var skillMessageIsError = false
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
    let onUseNextSkill: (UUID) -> Void
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
        onUseNextSkill: @escaping (UUID) -> Void,
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
        self.onUseNextSkill = onUseNextSkill
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
        settingsSplitView
        .frame(minWidth: 900, minHeight: 620)
        .onChange(of: selectedSection) { pane in
            guard let pane else {
                selectedSection = .general
                return
            }
            let normalized = pane.normalizedVisiblePane
            if normalized != pane {
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
                for: .openWhisperNavigateSettingsPane
            )
        ) { notification in
            guard
                let rawValue = notification.userInfo?["pane"] as? String,
                let pane = SettingsPane(rawValue: rawValue)
            else {
                return
            }
            withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.86)) {
                selectedSection = pane.normalizedVisiblePane
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionStatusMonitor.refresh()
            authSnapshot = authManager.authSnapshot()
            browserBridgeSnapshot = authManager.browserBridgeSnapshot()
            refreshTextPolishStatus()
            refreshRecentHistory()
            refreshRecoveryHistory()
            refreshRecoveryCredentialState()
            refreshCommunitySkillInventory()
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
            refreshCommunitySkillInventory()
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
                    "This removes transcripts, failed recordings, diagnostics, product metrics, terminology, custom Style Capsules, installed Community Skills, settings, the saved ChatGPT session, and the OpenAI-Compatible API key from this Mac. This action cannot be undone."
                )
            )
        }
        .alert(
            L10n.text("Use OpenAI-Compatible Recovery?"),
            isPresented: $showsAdvancedRecovery
        ) {
            Button(L10n.text("Cancel"), role: .cancel) {}
            Button(L10n.text("Use Recovery API")) {
                activateAdvancedRecovery()
            }
        } message: {
            Text(
                L10n.text(
                    "Future dictation audio will be sent to the configured endpoint with the API key stored in Keychain. Your API provider may charge for transcription. AI Polish will still use your ChatGPT account."
                )
            )
        }
        .sheet(isPresented: $showsThirdPartyLicenses) {
            ThirdPartyLicensesView(
                documents: thirdPartyLicenseDocuments
            )
        }
    }

    private var settingsSplitView: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                settingsSidebar
                Divider()
                    .ignoresSafeArea(.container, edges: .top)
                settingsDetail
                    .frame(
                        width: max(
                            0,
                            geometry.size.width
                                - SettingsLayoutMetrics.sidebarWidth
                                - 1
                        ),
                        height: geometry.size.height
                    )
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var settingsSidebar: some View {
        ZStack(alignment: .top) {
            SettingsSidebarMaterialView()
                .ignoresSafeArea(.container, edges: .top)
            settingsSidebarList
                .padding(.top, SettingsLayoutMetrics.sidebarTopPadding)
        }
        .frame(width: SettingsLayoutMetrics.sidebarWidth)
    }

    @ViewBuilder
    private var settingsDetail: some View {
        ZStack {
            switch activeSection {
            case .skills, .history, .terminology:
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
                            OpenWhisperMetrics
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
        .animation(
            reduceMotion ? .linear(duration: 0) : .easeOut(duration: OpenWhisperMotion.pageTransition),
            value: activeSection
        )
        .background(
            Color(nsColor: .windowBackgroundColor)
        )
    }

    private var settingsPageTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.995))
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
                            .font(OpenWhisperTypography.caption(.semibold))
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
                initialSection: skillLibraryInitialSection,
                isEmbedded: true,
                onSave: { updated in
                    persistEmbeddedConfig(updated)
                },
                onUseNext: onUseNextSkill,
                onRunTest: onRunSkillTest,
                onVoiceSampleAction: onVoiceSampleAction
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        default:
            EmptyView()
        }
    }

    private var activeSection: SettingsPane {
        (selectedSection ?? .general)
            .normalizedVisiblePane
    }

    @ViewBuilder
    private func settingsPaneLinks(
        _ panes: [SettingsPane]
    ) -> some View {
        ForEach(panes) { pane in
            SettingsSidebarRowButton(
                pane: pane,
                isSelected: activeSection == pane,
                reduceMotion: reduceMotion
            ) {
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
            .font(OpenWhisperTypography.display())
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
                .font(OpenWhisperTypography.caption(.semibold))
                .foregroundStyle(Color(nsColor: OpenWhisperPalette.error))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Color(nsColor: OpenWhisperPalette.error).opacity(0.12),
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
            VStack(spacing: 18) {
                generalCard
                accountOverviewCard
            }
        case .dictation, .polish, .paste:
            VStack(spacing: 18) {
                dictationCard
                pasteAndClipboardCard
                aiPolishCard
            }
        case .appearance:
            appearanceAndFeedbackCard
        case .context, .privacy:
            VStack(spacing: 18) {
                contextCard
                privacyCard
            }
        case .terminology, .skills, .history:
            EmptyView()
        case .advanced:
            advancedRecoveryCard
        }
    }

    private var generalCard: some View {
        settingsCard(title: nil, style: .hero) {
            SettingsRow(
                title: L10n.text("App Language"),
                detail: L10n.text(
                    "Applies to Settings, the menu bar, feedback, and new windows."
                )
            ) {
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
                    minWidth: 150,
                    idealWidth: 190,
                    maxWidth: 240
                )
            }

            Divider()

            SettingsRow(
                title: L10n.text("Default Skill"),
                detail:
                    currentGlobalDefaultSkill?
                        .localizedSummary
                    ?? L10n.text(
                        "Saved Skill unavailable. OpenWhisper will fall back to Direct."
                    )
            ) {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(
                        currentGlobalDefaultSkill?
                            .localizedName
                        ?? L10n.text("Direct")
                    )
                    .font(.system(size: 12, weight: .semibold))
                    Button(L10n.text("Open Skill Library…")) {
                        withAnimation(
                            .spring(response: 0.32, dampingFraction: 0.86)
                        ) {
                            selectedSection = .skills
                        }
                        onOpenSkillLibrary()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Divider()

            SettingsRow(
                title: L10n.text("Dictation shortcut"),
                detail: L10n.format(
                    "%@ starts and stops dictation everywhere on this Mac.",
                    config.transcription.dictationHotkey.displayName
                )
            ) {
                Text(config.transcription.dictationHotkey.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            }

            Divider()

            SettingsRow(
                title: L10n.text("Skill Switcher shortcut"),
                detail: L10n.text(
                    "Optional. Opens the Skill Switcher without starting dictation."
                )
            ) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        skillSwitcherShortcutControls
                    }
                    VStack(alignment: .trailing, spacing: 7) {
                        skillSwitcherShortcutControls
                    }
                }
            }

            if let hotkeyMessage {
                Text(hotkeyMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        hotkeyMessageIsError ? .red : .secondary
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var currentGlobalDefaultSkill:
        SkillDefinition?
    {
        availableSkillRegistry.definition(
            id: config.transcription.skills
                .defaultSkillID
        )
    }

    @ViewBuilder
    private var skillSwitcherShortcutControls: some View {
        Toggle(
            L10n.text("Enabled"),
            isOn: skillSwitcherHotkeyEnabledBinding
        )
        .toggleStyle(.switch)
        .controlSize(.small)

        if let binding = config.skillSwitcherHotkey {
            HotkeyRecorderView(
                binding: binding,
                onCandidate: { candidate in
                    applySkillSwitcherHotkeyCandidate(candidate)
                },
                onCaptureChanged: { capturing in
                    isCapturingHotkey = capturing
                    onHotkeyCaptureChanged(capturing)
                    if capturing {
                        hotkeyMessage = L10n.text(
                            "Press the shortcut you want to use. Esc cancels without changing the current shortcut."
                        )
                        hotkeyMessageIsError = false
                    }
                }
            )
            .frame(
                minWidth: 150,
                idealWidth: 176,
                maxWidth: 220,
                minHeight: 30,
                idealHeight: 30,
                maxHeight: 30
            )
        }
    }

    private var pasteAndClipboardCard: some View {
        settingsCard(title: "Paste & Clipboard") {
            Toggle(
                L10n.text("Restore clipboard after verified insertion"),
                isOn: $config.injection.preserveClipboard
            )
            .accessibilityHint(
                L10n.text(
                    "OpenWhisper restores the previous clipboard only after Accessibility confirms the expected text change. If the target or insertion cannot be verified, the transcript stays in the clipboard for manual Cmd+V."
                )
            )
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
            if previousHotkey != requestedHotkey {
                hotkeyMessage = L10n.format(
                    "Dictation shortcut changed to %@.",
                    requestedHotkey.displayName
                )
                hotkeyMessageIsError = false
            } else if previousSkillSwitcherHotkey
                != requestedSkillSwitcherHotkey
            {
                hotkeyMessage = requestedSkillSwitcherHotkey.map {
                    L10n.format(
                        "Skill Switcher shortcut changed to %@.",
                        $0.displayName
                    )
                } ?? L10n.text(
                    "Skill Switcher shortcut disabled."
                )
                hotkeyMessageIsError = false
            }
        case .failure(let error):
            saveStatus = .failed(error.localizedDescription)
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
            try OpenWhisperShortcutSetValidator.validate(
                dictation: validated,
                skillSwitcher: config.skillSwitcherHotkey
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
                }
            }
        )
    }

    private func applySkillSwitcherHotkeyCandidate(
        _ candidate: HotkeyBinding
    ) {
        do {
            let validated = try candidate.validated()
            try OpenWhisperShortcutSetValidator.validate(
                dictation:
                    config.transcription.dictationHotkey,
                skillSwitcher: validated
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
        settingsCard(title: nil, style: .hero) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 0) {
                    compactSetupTile(title: "ChatGPT", status: chatGPTAccountStatus)
                    Divider()
                        .frame(height: 36)
                        .padding(.horizontal, 14)
                    compactSetupTile(title: "Microphone", status: microphoneStatus)
                    Divider()
                        .frame(height: 36)
                        .padding(.horizontal, 14)
                    compactSetupTile(title: "Accessibility", status: accessibilityStatus)
                }

                HStack(alignment: .center, spacing: 10) {
                    if let userEmail = authSnapshot.userEmail {
                        Text(userEmail)
                            .font(.system(size: 12, weight: .medium))
                    }

                    Spacer()

                    chatGPTSetupActions
                }

                HStack {
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

                }

                if let permissionMessage {
                    Text(permissionMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(
                            permissionMessageIsError ? .red : .secondary
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }

            }
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
                            .frame(
                                minWidth: 150,
                                idealWidth: 176,
                                maxWidth: 220,
                                minHeight: 30,
                                idealHeight: 30,
                                maxHeight: 30
                            )

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
                    .pickerStyle(.menu)
                    .frame(
                        minWidth: 170,
                        idealWidth: 230,
                        maxWidth: 280
                    )
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
                    .pickerStyle(.menu)
                    .frame(
                        minWidth: 170,
                        idealWidth: 230,
                        maxWidth: 280
                    )
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("Default ASR route"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(L10n.text("ChatGPT Account"))
                        .font(.system(size: 14, weight: .semibold))
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
            title: nil,
            style: .hero
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
                    .pickerStyle(.menu)
                    .frame(
                        minWidth: 190,
                        idealWidth: 240,
                        maxWidth: 300,
                        alignment: .leading
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
                    .pickerStyle(.menu)
                    .frame(
                        minWidth: 150,
                        idealWidth: 180,
                        maxWidth: 240
                    )
                }

                if config.visualFeedback.mode
                    == .aiActivityGlow
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
                        .pickerStyle(.menu)
                        .frame(
                            minWidth: 180,
                            idealWidth: 230,
                            maxWidth: 290
                        )
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

                }
            }
        }
    }

    private var privacyCard: some View {
        settingsCard(title: nil, style: .hero) {
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
                Divider()

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.text("Delete all local data"))
                            .font(.system(size: 12, weight: .semibold))
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
            refreshCommunitySkillInventory()
            privacyMessage = L10n.text("All OpenWhisper data was deleted from this Mac.")
            privacyMessageIsError = false
        case .failure(let error):
            privacyMessage = error.localizedDescription
            privacyMessageIsError = true
        }
    }

    private var advancedRecoveryCard: some View {
        settingsCard(title: "Current Product Route") {
            VStack(alignment: .leading, spacing: 12) {
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

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("OpenAI-Compatible Recovery"))
                        .font(.system(size: 13, weight: .semibold))

                    LabeledContent(L10n.text("Endpoint")) {
                        TextField(
                            "",
                            text: $recoveryEndpointDraft,
                            prompt: Text(
                                "https://api.example.com/v1/audio/transcriptions"
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(
                            minWidth: 180,
                            idealWidth: 360,
                            maxWidth: .infinity
                        )
                        .onSubmit {
                            commitRecoveryEndpointDraft()
                        }
                        .onDisappear {
                            commitRecoveryEndpointDraft()
                        }
                        .task(id: recoveryEndpointDraft) {
                            try? await Task.sleep(for: .milliseconds(450))
                            guard !Task.isCancelled else {
                                return
                            }
                            commitRecoveryEndpointDraft()
                        }
                    }

                    LabeledContent(L10n.text("Model")) {
                        TextField(
                            "",
                            text: $recoveryModelDraft,
                            prompt: Text("gpt-4o-mini-transcribe")
                        )
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(
                            minWidth: 180,
                            idealWidth: 260,
                            maxWidth: .infinity
                        )
                        .onSubmit {
                            commitRecoveryModelDraft()
                        }
                        .onDisappear {
                            commitRecoveryModelDraft()
                        }
                        .task(id: recoveryModelDraft) {
                            try? await Task.sleep(for: .milliseconds(450))
                            guard !Task.isCancelled else {
                                return
                            }
                            commitRecoveryModelDraft()
                        }
                    }

                    LabeledContent(L10n.text("API Key")) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                recoveryAPIKeyField
                                recoveryAPIKeyActions
                            }
                            VStack(alignment: .trailing, spacing: 8) {
                                recoveryAPIKeyField
                                recoveryAPIKeyActions
                            }
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
                Divider()

                LabeledContent(L10n.text("Open Source Licenses")) {
                    Button(L10n.text("View Third-Party Licenses…")) {
                        showThirdPartyLicenses()
                    }
                    .buttonStyle(.bordered)
                }
                if let thirdPartyLicenseMessage {
                    Text(thirdPartyLicenseMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(
                            thirdPartyLicenseMessageIsError
                                ? .red
                                : .secondary
                        )
                }

                if providerPolicySnapshot.isConfigured {
                    Divider()

                    LabeledContent(L10n.text("Provider Safety")) {
                    Button(L10n.text("Refresh Safety Policy")) {
                        Task {
                            providerPolicySnapshot =
                                await providerCapabilityPolicy.refresh(force: true)
                        }
                    }
                    .buttonStyle(.bordered)
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
                }

                if softwareUpdateSnapshot.isConfigured {
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
                }

                Divider()

                LabeledContent(L10n.text("Support Diagnostics")) {
                    Button(L10n.text("Export Diagnostics…")) {
                        exportSupportDiagnostics()
                    }
                    .buttonStyle(.bordered)
                }
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
                .font(OpenWhisperTypography.callout(.medium))
                .frame(width: 90, alignment: .leading)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(value))
                    .font(OpenWhisperTypography.callout(.semibold))
                Text(detail)
                    .font(OpenWhisperTypography.caption())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(12)
        .background(
            Color(nsColor: OpenWhisperPalette.insetSurface),
            in: RoundedRectangle(
                cornerRadius: OpenWhisperMetrics.radiusM,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OpenWhisperMetrics.radiusM,
                style: .continuous
            )
            .stroke(
                Color(nsColor: OpenWhisperPalette.hairline),
                lineWidth: 0.5
            )
        }
    }

    private var terminologyCard:
        some View
    {
        settingsCard(
            title: "Terminology"
        ) {
            VStack(
                alignment: .leading,
                spacing: 14
            ) {
                TerminologyPackSettingsView(
                    config: $config
                )
                Divider()
                terminologyLibrarySummary
            }
        }
    }

    private var contextCard: some View {
        settingsCard(title: "Global Context") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("Context Sources"))
                        .font(.system(size: 12, weight: .semibold))
                    ForEach(
                        ContextSourceKind
                            .userVisibleSettingsSources
                    ) { source in
                        HStack(spacing: 10) {
                            Image(systemName: source.isAvailableInCurrentRuntime ? "checkmark.circle.fill" : "clock.badge")
                                .foregroundStyle(
                                    source.isAvailableInCurrentRuntime
                                        ? Color(nsColor: OpenWhisperPalette.success)
                                        : Color.secondary
                                )
                            Text(source.title)
                                .font(.system(size: 12, weight: .medium))
                            Spacer(minLength: 16)
                            if source.isAvailableInCurrentRuntime,
                               source != .voice
                            {
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
                                .labelsHidden()
                                .toggleStyle(.switch)
                            } else {
                                Text(
                                    L10n.text("Required")
                                )
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Divider()

                LabeledContent(
                    L10n.text(
                        "Maximum selected text"
                    )
                ) {
                    Picker(
                        L10n.text(
                            "Maximum selected text"
                        ),
                        selection:
                            $config.context
                                .maximumSelectionCharacters
                    ) {
                        Text(
                            L10n.text(
                                "2,000 characters"
                            )
                        ).tag(2_000)
                        Text(
                            L10n.text(
                                "6,000 characters"
                            )
                        ).tag(6_000)
                        Text(
                            L10n.text(
                                "12,000 characters"
                            )
                        ).tag(12_000)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(
                        minWidth: 150,
                        idealWidth: 190,
                        maxWidth: 240
                    )
                }
                .disabled(
                    !config.context
                        .selectionEnabled
                )

                Divider()

                Text(
                    L10n.text(
                        "Skill Permissions"
                    )
                )
                .font(
                    .system(
                        size: 12,
                        weight: .semibold
                    )
                )

                ForEach(
                    availableSkillRegistry
                        .orderedDefinitions
                        .filter {
                            $0.allCapabilities
                                .contains(
                                    .selection
                                )
                        }
                ) { skill in
                    HStack(spacing: 12) {
                        Text(skill.localizedName)
                            .font(
                                .system(
                                    size: 12,
                                    weight: .medium
                                )
                            )
                        Spacer()
                        Picker(
                            skill.localizedName,
                            selection: Binding(
                                get: {
                                    config.context
                                        .scope(
                                            skillID:
                                                skill.id,
                                            capability:
                                                .selection
                                        )
                                },
                                set: { scope in
                                    config.context
                                        .setScope(
                                            scope,
                                            skillID:
                                                skill.id,
                                            capability:
                                                .selection
                                        )
                                }
                            )
                        ) {
                            ForEach(
                                SkillPermissionScope
                                    .allCases
                            ) { scope in
                                Text(scope.title)
                                    .tag(scope)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(
                            minWidth: 130,
                            idealWidth: 165,
                            maxWidth: 220
                        )
                    }
                    .padding(
                        .vertical,
                        4
                    )
                }
                .disabled(
                    !config.context
                        .selectionEnabled
                )

                HStack(spacing: 10) {
                    Spacer()
                    Button(
                        L10n.text(
                            "Reset Permissions"
                        )
                    ) {
                        config.context
                            .revokeAll()
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        config.context
                            .permissionGrants
                            .isEmpty
                    )
                }

                Divider()

                SettingsRow(
                    title: L10n.text("Context Receipts"),
                    detail: L10n.text(
                        "Receipts contain only source names and character counts, never Context text."
                    )
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
                        minWidth: 160,
                        idealWidth: 210,
                        maxWidth: 260
                    )
                }

                if !config.context.recentReceipts.isEmpty {
                    ForEach(config.context.recentReceipts.suffix(5).reversed()) { receipt in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.shield")
                                .foregroundStyle(.secondary)
                            Text(receipt.grantedSources.map(\.title).joined(separator: ", "))
                                .lineLimit(1)
                            Spacer()
                            Text(receipt.createdAt.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 10))
                    }
                }

                Divider()

                StyleCapsuleSettingsView(
                    config: $config,
                    registry:
                        availableSkillRegistry,
                    store: styleCapsuleStore,
                    localAssetAccessEnabled:
                        localAssetAccessEnabled
                )
            }
        }
    }

    private var aiPolishCard: some View {
        settingsCard(title: nil, style: .hero) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    OpenWhisperIconWell(
                        systemName: "wand.and.stars",
                        size: OpenWhisperMetrics.iconWellSizeLarge,
                        symbolSize: 18
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("Skill Library"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Spacer()
                    Button(L10n.text("Open Skill Library…")) {
                        withAnimation(
                            .spring(response: 0.32, dampingFraction: 0.86)
                        ) {
                            selectedSection = .skills
                        }
                        onOpenSkillLibrary()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()

                Picker(L10n.text("Mode"), selection: $config.transcription.textPolish.mode) {
                    Text(L10n.text("Auto")).tag(TextPolishMode.automaticWhenKeyAvailable)
                    Text(L10n.text("Always rewrite")).tag(TextPolishMode.always)
                    Text(L10n.text("Off")).tag(TextPolishMode.disabled)
                }
                .pickerStyle(.segmented)

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

    private var skillSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.text("Skills"))
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.text("Community"))
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

            LabeledContent(L10n.text("Default Skill")) {
                Picker(
                    L10n.text("Default Skill"),
                    selection:
                        $config.transcription.skills.defaultSkillID
                ) {
                    ForEach(
                        availableSkillRegistry.orderedDefinitions
                    ) { skill in
                        Text(skill.localizedName)
                            .tag(skill.id)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
            }

            if config.transcription.skills.requiresTextPolish,
               config.transcription.textPolish.mode == .disabled
            {
                Label(
                    L10n.text(
                        "This Skill needs AI Polish. Turn rewrite mode to Auto or Always rewrite to apply it."
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
            } else if config.transcription.skills.requiresTextPolish,
                      authSnapshot.state != .ready
            {
                Label(
                    L10n.text(
                        "Reply, Email, Backend Prompt, Code Prompt, and Translate need a connected ChatGPT account for AI Polish. Direct dictation and transcription recovery still work without it."
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
                        chooseSkillApplication()
                    }
                    .buttonStyle(.bordered)

                }

                HStack(spacing: 8) {
                    TextField(
                        L10n.text("App name (optional)"),
                        text: $editingSkillAppName
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 150)

                    TextField(
                        L10n.text("Bundle identifier"),
                        text: $editingSkillBundleIdentifier,
                        prompt: Text("com.apple.Notes")
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                }

                HStack(spacing: 8) {
                    Picker(
                        L10n.text("Skill"),
                        selection: $editingSkillID
                    ) {
                        ForEach(
                            availableSkillRegistry.orderedDefinitions
                        ) { skill in
                            Text(skill.localizedName)
                                .tag(skill.id)
                        }
                    }
                    .frame(width: 210)

                    Button(
                        L10n.text(
                            editingSkillRuleID == nil
                                ? "Add Rule"
                                : "Save Rule"
                        )
                    ) {
                        saveSkillRule()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        editingSkillBundleIdentifier
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty
                    )

                    if editingSkillRuleID != nil {
                        Button(L10n.text("Cancel")) {
                            resetSkillRuleEditor()
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()
                }

                if let skillMessage {
                    Text(skillMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(
                            skillMessageIsError ? .red : .secondary
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !config.transcription.skills.applicationRules.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(
                            config.transcription.skills.applicationRules
                        ) { rule in
                            skillRuleRow(rule)
                        }
                    }
                }
            }
        }
    }

    private func skillRuleRow(
        _ rule: AppSkillRule
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle(
                L10n.format(
                    "Enable Skill rule for %@",
                    rule.appName ?? rule.bundleIdentifier
                ),
                isOn: Binding(
                    get: { rule.isEnabled },
                    set: { isEnabled in
                        updateSkillRule(rule.id) {
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

            Text(
                availableSkillRegistry
                    .definition(id: rule.skillID)?
                    .localizedName
                    ?? L10n.text("Direct")
            )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                .frame(width: 100, alignment: .trailing)

            Button {
                startEditingSkillRule(rule)
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n.text("Edit"))
            .accessibilityLabel(
                L10n.format(
                    "Edit Skill rule for %@",
                    rule.appName ?? rule.bundleIdentifier
                )
            )

            Button(role: .destructive) {
                config.transcription.skills.remove(id: rule.id)
                if editingSkillRuleID == rule.id {
                    resetSkillRuleEditor()
                }
                skillMessage = L10n.text(
                    "Application Skill rule removed."
                )
                skillMessageIsError = false
            } label: {
                Image(systemName: "trash")
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n.text("Delete"))
            .accessibilityLabel(
                L10n.format(
                    "Delete Skill rule for %@",
                    rule.appName ?? rule.bundleIdentifier
                )
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color(nsColor: OpenWhisperPalette.insetSurface),
            in: RoundedRectangle(
                cornerRadius: OpenWhisperMetrics.radiusM,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OpenWhisperMetrics.radiusM,
                style: .continuous
            )
            .stroke(
                Color(nsColor: OpenWhisperPalette.hairline),
                lineWidth: 0.5
            )
        }
    }

    private func saveSkillRule() {
        do {
            let existingRule = editingSkillRuleID.flatMap { id in
                config.transcription.skills.applicationRules.first {
                    $0.id == id
                }
            }
            let rule = try AppSkillRule.validated(
                id: existingRule?.id ?? UUID(),
                appName: editingSkillAppName,
                bundleIdentifier: editingSkillBundleIdentifier,
                skillID: editingSkillID,
                skillInstallationID:
                    communitySkillInventory.packages.first {
                        $0.isActive
                            && $0.definition.id == editingSkillID
                    }?.installation.id
                    ?? (existingRule?.skillID == editingSkillID
                        ? existingRule?.skillInstallationID
                        : nil),
                isEnabled: existingRule?.isEnabled ?? true,
                registry:
                    availableSkillRegistry
            )
            config.transcription.skills.upsert(
                rule,
                registry:
                    availableSkillRegistry
            )
            skillMessage = L10n.format(
                "Skill rule saved for %@.",
                rule.appName ?? rule.bundleIdentifier
            )
            skillMessageIsError = false
            resetSkillRuleEditor(clearMessage: false)
        } catch {
            skillMessage = error.localizedDescription
            skillMessageIsError = true
            NSSound.beep()
        }
    }

    private func chooseSkillApplication() {
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
            "OpenWhisper stores only the selected app name and bundle identifier for this Skill rule."
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
                skillMessage = L10n.text(
                    "The selected application does not expose a valid bundle identifier."
                )
                skillMessageIsError = true
                NSSound.beep()
            }
            return
        }

        editingSkillBundleIdentifier =
            AppModeRule.normalizedBundleIdentifier(bundleIdentifier)
        editingSkillAppName = (
            bundle.object(
                forInfoDictionaryKey: "CFBundleDisplayName"
            ) as? String
        ) ?? (
            bundle.object(
                forInfoDictionaryKey: "CFBundleName"
            ) as? String
        ) ?? appURL.deletingPathExtension().lastPathComponent
        skillMessage = nil
        skillMessageIsError = false
    }

    private func startEditingSkillRule(_ rule: AppSkillRule) {
        editingSkillRuleID = rule.id
        editingSkillAppName = rule.appName ?? ""
        editingSkillBundleIdentifier = rule.bundleIdentifier
        editingSkillID = rule.skillID
        skillMessage = nil
        skillMessageIsError = false
    }

    private func resetSkillRuleEditor(
        clearMessage: Bool = true
    ) {
        editingSkillRuleID = nil
        editingSkillAppName = ""
        editingSkillBundleIdentifier = ""
        editingSkillID =
            SkillRegistry.replySkillID
        if clearMessage {
            skillMessage = nil
            skillMessageIsError = false
        }
    }

    private func updateSkillRule(
        _ id: UUID,
        update: (inout AppSkillRule) -> Void
    ) {
        guard
            var rule = config.transcription.skills
                .applicationRules.first(where: { $0.id == id })
        else {
            return
        }
        update(&rule)
        config.transcription.skills.upsert(
            rule,
            registry:
                availableSkillRegistry
        )
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
            Color(nsColor: OpenWhisperPalette.insetSurface),
            in: RoundedRectangle(
                cornerRadius: OpenWhisperMetrics.radiusM,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OpenWhisperMetrics.radiusM,
                style: .continuous
            )
            .stroke(
                Color(nsColor: OpenWhisperPalette.hairline),
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
            Color(nsColor: OpenWhisperPalette.insetSurface),
            in: RoundedRectangle(
                cornerRadius: OpenWhisperMetrics.radiusM,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OpenWhisperMetrics.radiusM,
                style: .continuous
            )
            .stroke(
                Color(nsColor: OpenWhisperPalette.hairline),
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
            Color(nsColor: OpenWhisperPalette.insetSurface),
            in: RoundedRectangle(
                cornerRadius: OpenWhisperMetrics.radiusM,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OpenWhisperMetrics.radiusM,
                style: .continuous
            )
            .stroke(
                Color(nsColor: OpenWhisperPalette.hairline),
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

    private var terminologyLibrarySummary: some View {
        SettingsRow(
            title: L10n.text("Terminology Dictionary"),
            detail: terminologyLibrarySummaryText
        ) {
            Button(L10n.text("Open Terminologies…")) {
                withAnimation(
                    .spring(response: 0.32, dampingFraction: 0.86)
                ) {
                    selectedSection = .terminology
                }
                onOpenTerminology()
            }
            .buttonStyle(.bordered)
        }
    }

    private var terminologyLibrarySummaryText: String {
        let entries = config.transcription
            .terminology.entries
        let enabledCount = entries.filter(\.isEnabled).count
        return L10n.format(
            "%ld entries · %ld enabled. Add, edit, import, export, and remove entries in the Terminologies window.",
            entries.count,
            enabledCount
        )
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
            .font(OpenWhisperTypography.micro(.semibold))
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
            color = Color(nsColor: OpenWhisperPalette.amber)
        case .connected:
            label = L10n.text("Connected")
            color = Color(nsColor: OpenWhisperPalette.success)
        case .failed:
            label = L10n.text("Failed")
            color = Color(nsColor: OpenWhisperPalette.error)
        }

        return Text(label)
            .font(OpenWhisperTypography.micro(.semibold))
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
            Color(nsColor: OpenWhisperPalette.insetSurface),
            in: RoundedRectangle(
                cornerRadius: OpenWhisperMetrics.radiusM,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OpenWhisperMetrics.radiusM,
                style: .continuous
            )
            .stroke(
                Color(nsColor: OpenWhisperPalette.hairline),
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
            Color(nsColor: OpenWhisperPalette.insetSurface),
            in: RoundedRectangle(
                cornerRadius: OpenWhisperMetrics.radiusM,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OpenWhisperMetrics.radiusM,
                style: .continuous
            )
            .stroke(
                Color(nsColor: OpenWhisperPalette.hairline),
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
        style: SettingsCardContainer<Content>.Style = .grouped,
        @ViewBuilder content: () -> Content
    ) -> some View {
        SettingsCardContainer(title: title, style: style) {
            content()
        }
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
                        ? Color(nsColor: OpenWhisperPalette.success)
                        : Color(nsColor: OpenWhisperPalette.amber)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(title))
                    .font(OpenWhisperTypography.callout(.semibold))
                Text(status.title)
                    .font(OpenWhisperTypography.caption())
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
                    .accessibilityHint(status.subtitle)
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
