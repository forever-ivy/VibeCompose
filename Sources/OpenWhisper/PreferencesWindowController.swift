import AppKit
import AVFoundation
import ApplicationServices
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
        onRequestMicrophoneAccess: @escaping () -> Void,
        onOpenConfigFolder: @escaping () -> Void,
        onExportSupportDiagnostics: @escaping (URL) -> Result<URL, any Error>,
        onDeleteAllData: @escaping () -> Result<AppConfig, any Error>,
        onOpenOnboarding: @escaping () -> Void,
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
            onDeleteAllData: onDeleteAllData,
            onOpenOnboarding: onOpenOnboarding,
            focusPane: focusPane
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

        if
            let window,
            window.windowNumber > 0,
            let windowImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                CGWindowID(window.windowNumber),
                [.boundsIgnoreFraming, .bestResolution]
            ),
            let png = NSBitmapImageRep(cgImage: windowImage)
                .representation(using: .png, properties: [:])
        {
            try png.write(to: url, options: [.atomic])
            return
        }

        guard let contentView = window?.contentView else {
            throw PreferencesSnapshotError.missingContentView
        }

        contentView.layoutSubtreeIfNeeded()
        contentView.displayIfNeeded()
        let bounds = contentView.bounds
        guard
            bounds.width > 0,
            bounds.height > 0,
            let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds)
        else {
            throw PreferencesSnapshotError.bitmapUnavailable
        }

        contentView.cacheDisplay(in: bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw PreferencesSnapshotError.pngEncodingFailed
        }
        try png.write(to: url, options: [.atomic])
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
    var inputTokens = 0
    var outputTokens = 0

    var summary: String {
        guard attempts > 0 else {
            return L10n.text("0 attempts / 0 tokens")
        }
        return L10n.format(
            "%ld attempts / %ld succeeded / %ld failed / %ld tokens",
            attempts,
            succeeded,
            failed,
            inputTokens + outputTokens
        )
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
    @State private var selectedSection: SettingsPane?
    @State private var saveStatus: SettingsSaveStatus = .saved
    @State private var textPolishUsage: [TextPolishProviderID: TextPolishUsage] = [:]
    @State private var textPolishMessage: String?
    @State private var textPolishMessageIsError = false
    @State private var recentHistoryRecords: [TranscriptionHistoryRecord] = []
    @State private var recentRecoveryRecords: [RecoveryRecord] = []
    @State private var selectedRecoveryKind: RecoveryHistoryKind = .audio
    @State private var copiedHistoryItemID: String?
    @State private var showsDeleteAllDataConfirmation = false
    @State private var privacyMessage: String?
    @State private var privacyMessageIsError = false
    @State private var diagnosticsExportMessage: String?
    @State private var diagnosticsExportMessageIsError = false

    let authManager: ChatGPTAuthManager
    let onSave: (AppConfig) -> Result<Void, any Error>
    let onImportTerminologyDictionary: (AppConfig, URL) -> Result<AppConfig, any Error>
    let onLoadRecentHistory: () -> [TranscriptionHistoryRecord]
    let onLoadRecoveryHistory: () -> [RecoveryRecord]
    let onResolveRecoveryAudioURL: (RecoveryRecord) -> Result<URL, any Error>
    let onRetryRecoveryRecord: (RecoveryRecord) -> Void
    let onRequestMicrophoneAccess: () -> Void
    let onOpenConfigFolder: () -> Void
    let onExportSupportDiagnostics: (URL) -> Result<URL, any Error>
    let onDeleteAllData: () -> Result<AppConfig, any Error>
    let onOpenOnboarding: () -> Void
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
        onRequestMicrophoneAccess: @escaping () -> Void,
        onOpenConfigFolder: @escaping () -> Void,
        onExportSupportDiagnostics: @escaping (URL) -> Result<URL, any Error>,
        onDeleteAllData: @escaping () -> Result<AppConfig, any Error>,
        onOpenOnboarding: @escaping () -> Void,
        focusPane: SettingsPane? = nil
    ) {
        let windowStateStore = SettingsWindowStateStore()
        _config = State(initialValue: initialConfig)
        _showsAdvancedRecovery = State(initialValue: initialConfig.transcription.provider == .openAICompatible)
        _permissionStatusMonitor = StateObject(wrappedValue: PermissionStatusMonitor())
        _terminologyImportMessage = State(initialValue: Self.terminologyStatusMessage(for: initialConfig))
        _authSnapshot = State(initialValue: authManager.authSnapshot())
        _browserBridgeSnapshot = State(initialValue: authManager.browserBridgeSnapshot())
        _textPolishUsage = State(initialValue: Self.loadTextPolishUsage())
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
        self.onDeleteAllData = onDeleteAllData
        self.onOpenOnboarding = onOpenOnboarding
        self.windowStateStore = windowStateStore
    }

    private var runtimeIssues: [RuntimePreflightIssue] {
        RuntimePreflight.issues(
            for: config,
            environment: ProcessInfo.processInfo.environment,
            authSnapshotProvider: { authSnapshot }
        )
    }

    private var chatGPTAccountStatus: SetupStatus {
        if config.transcription.provider == .openAICompatible {
            return SetupStatus(
                title: L10n.text("Advanced recovery route selected"),
                subtitle: L10n.text("ChatGPT account checks are bypassed while you use your own compatible API.")
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
                subtitle: L10n.text("Press F5 once and macOS will ask for microphone access."),
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
                        Text(L10n.text("F5 dictation workflow"))
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
            persistSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionStatusMonitor.refresh()
            authSnapshot = authManager.authSnapshot()
            browserBridgeSnapshot = authManager.browserBridgeSnapshot()
            refreshTextPolishStatus()
            refreshRecentHistory()
            refreshRecoveryHistory()
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
        }
        .task {
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
                    "This removes transcripts, failed recordings, diagnostics, terminology, settings, and the saved ChatGPT session from this Mac. This action cannot be undone."
                )
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
            return L10n.text("Configure the F5 recording route and ASR behavior.")
        case .polish:
            return L10n.text("Rewrite long transcripts into concise, agent-friendly plans after ASR.")
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
        case .polish:
            aiPolishCard
        case .paste:
            settingsCard(title: "Paste & Clipboard") {
                Toggle(L10n.text("Restore clipboard after paste"), isOn: $config.injection.preserveClipboard)
                Text(L10n.text("When no editable focus is detected, OpenWhisper leaves the polished transcript in the clipboard for manual Cmd+V."))
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
        switch onSave(config) {
        case .success:
            saveStatus = .saved
        case .failure(let error):
            saveStatus = .failed(error.localizedDescription)
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
            guard attempted else {
                continue
            }

            let provider = sample.textPolishProvider.flatMap(TextPolishProviderID.init(rawValue:)) ?? .chatGPTAuth
            var current = usage[provider] ?? TextPolishUsage()
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
        textPolishUsage = Self.loadTextPolishUsage()
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
                        Text(L10n.text("F5 starts and stops recording. Output pastes when an editable target is focused; otherwise it stays in the clipboard."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    chatGPTSetupActions
                }

                HStack {
                    Text(
                        L10n.text(
                            "Need to revisit the first-run flow or practice F5 again?"
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
                        ForEach(microphoneRepairActions + accessibilityRepairActions) { action in
                            repairActionButton(action)
                        }
                    }

                    if !permissionStatusMonitor.snapshot.accessibilityTrusted,
                       let detail = AccessibilityPermission.repairGuidance().detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var dictationCard: some View {
        settingsCard(title: "Dictation / ASR") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.text("Hotkey"))
                    Spacer()
                    Text("F5")
                        .monospaced()
                        .foregroundStyle(.secondary)
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
                                "Deletes settings, terminology, history, failed recordings, diagnostics, retry files, and the saved ChatGPT session."
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
            authSnapshot = authManager.authSnapshot()
            browserBridgeSnapshot = authManager.browserBridgeSnapshot()
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
                Text(L10n.text("OpenWhisper ships as a ChatGPT account dictation app. The normal path uses the ChatGPT backend for ASR and the ChatGPT-authenticated Responses endpoint for AI Polish."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    routeRow(
                        title: "Dictation",
                        value: "ChatGPT Account",
                        detail: ManagedEndpointPolicy.transcriptionURL.absoluteString
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

                if config.transcription.provider == .openAICompatible {
                    Divider()
                    Text(L10n.text("Advanced transcription recovery is selected. It uses the configured OpenAI-compatible ASR environment variable, but OpenWhisper no longer ships a provider-key fallback matrix or text-polish provider key UI."))
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
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

                LabeledContent(L10n.text("Support Diagnostics")) {
                    Button(L10n.text("Export Diagnostics…")) {
                        exportSupportDiagnostics()
                    }
                    .buttonStyle(.bordered)
                }
                Text(
                    L10n.text(
                        "Creates a local ZIP with redacted runtime, permission, latency, and crash-summary data. It excludes audio, transcripts, clipboard text, account email, tokens, API keys, terminology, custom endpoints, and raw crash reports."
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
                    Text(L10n.text(item.outcome))
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
                        "Usage: %ld attempts, %ld succeeded, %ld failed, %ld input tokens, %ld output tokens.",
                        usage.attempts,
                        usage.succeeded,
                        usage.failed,
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
                    Text(L10n.text(item.outcome))
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
            onRequestMicrophoneAccess()
        case .guidedAccessibilityAccess:
            AccessibilityPermission.guideAccess()
        case .openSettings(let destination):
            _ = destination.open()
        case .refreshStatus:
            permissionStatusMonitor.refresh()
        }
    }

    @ViewBuilder
    private func repairActionButton(_ action: PermissionRepairAction) -> some View {
        switch action.prominence {
        case .primary:
            Button(L10n.text(action.title)) {
                performRepairAction(action)
            }
            .buttonStyle(.borderedProminent)
        case .secondary:
            Button(L10n.text(action.title)) {
                performRepairAction(action)
            }
            .buttonStyle(.bordered)
        case .utility:
            Button(L10n.text(action.title)) {
                performRepairAction(action)
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct SetupStatus {
    let title: String
    let subtitle: String
    var isReady: Bool = true
}
