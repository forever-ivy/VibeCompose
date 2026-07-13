import AppKit
import AVFoundation
import Foundation
import OpenWhisperLicensing
import OSLog

struct TranscriptionAttemptPolicy: Sendable, Equatable {
    let cloudflareChallengeMaxAttempts: Int
    let transientFailureMaxAttempts: Int

    static let automatic = TranscriptionAttemptPolicy(
        cloudflareChallengeMaxAttempts: 3,
        transientFailureMaxAttempts: 3
    )
    static let manualRetry = TranscriptionAttemptPolicy(
        cloudflareChallengeMaxAttempts: 1,
        transientFailureMaxAttempts: 1
    )
}

@MainActor
final class AppCoordinator {
    enum State: Equatable {
        case idle
        case recording
        case processing
    }

    typealias RecorderFactory = @MainActor (Int) -> any RecordingControlling
    typealias StatusMenuFactory = @MainActor (
        @escaping () -> Void,
        @escaping () -> Void,
        @escaping () -> Void,
        @escaping () -> Void,
        @escaping () -> Void,
        @escaping () -> Void
    ) -> any StatusMenuUpdating
    typealias PipelineFactory = @Sendable (
        TranscriptionConfig,
        any ChatGPTAuthProviding,
        TranscriptionAttemptPolicy,
        any ProviderCapabilityChecking,
        any OpenAICompatibleCredentialPersisting
    ) -> any DictationPreparing
    typealias LaunchAppContextProvider = @MainActor () -> LaunchAppContext?

    let configStore: ConfigStore
    let notifier: any NotificationDispatching
    let injector: any TextInjecting
    let overlay: any OverlayControlling
    let authManager: any ChatGPTAuthProviding
    let latencyRecorder: any LatencyRecording
    let productMetricsRecorder: any ProductMetricsRecording
    let historyRecorder: any TranscriptionHistoryRecording
    let recoveryRecorder: any RecoveryRecording
    let soundFeedback: any SoundFeedbackPlaying
    let softwareUpdater: any SoftwareUpdating
    let providerCapabilityPolicy: any ProviderCapabilityChecking
    let recoveryCredentialStore: any OpenAICompatibleCredentialPersisting
    let licenseManager: any CommercialLicenseManaging
    let hotkeyRegistrationService: HotkeyRegistrationService
    let recorderFactory: RecorderFactory
    let statusMenuFactory: StatusMenuFactory
    let pipelineFactory: PipelineFactory
    let launchAppContextProvider: LaunchAppContextProvider
    let contextBroker: ContextBroker
    let contextPermissionPrompter:
        any ContextPermissionPrompting
    let previewPresenter:
        any PreviewPresenting
    let outputRouter: OutputRouter
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? ProductIdentity.defaultBundleIdentifier,
        category: "AppCoordinator"
    )

    var config: AppConfig
    private var quickAddHotkeyMonitor: HotkeyMonitor?
    var recorder: (any RecordingControlling)?
    var statusMenu: (any StatusMenuUpdating)?
    private var preferencesWindowController: PreferencesWindowController?
    private var historyWindowController: HistoryWindowController?
    private var terminologyWindowController: TerminologyWindowController?
    private var terminologyQuickAddWindowController: TerminologyQuickAddWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var microphonePermissionWindowController: MicrophonePermissionWindowController?
    var state: State = .idle
    private var recordingLevelTimer: Timer?
    private var overlayDemoFrameIndex = 0
    var launchAppContext: LaunchAppContext?
    var processingTask: Task<Void, Never>?
    private var startRecordingTask: Task<Void, Never>?
    private var activeSessionID: UUID?
    private var recordingStartedAt: DispatchTime?
    private var recordingTranscriptionConfig: TranscriptionConfig?
    private var recordingPreparedContext =
        PreparedSkillContext()
    private var pendingRetry: PendingRetry?
    private var pendingRetryExpiryTask: Task<Void, Never>?
    private var authStateObserver: NSObjectProtocol?
    private var activeProcessingAudio: ActiveProcessingAudio?
    private var snapshotPrivacyMode = SnapshotPrivacyMode.disabled
    private var hotkeyRegistrationIssue: String?
    private var visualFeedbackPreviewTask:
        Task<Void, Never>?
    private var previewDemoTask:
        Task<Void, Never>?

    private struct PendingRetry {
        let id: UUID
        let audio: RecordedAudio
        let launchAppContext: LaunchAppContext?
        let transcriptionConfig: TranscriptionConfig
        let injectionConfig: InjectionConfig
        let expiresAt: Date
    }

    private struct ActiveProcessingAudio {
        let fileURL: URL
        let deleteWhenFinished: Bool
    }

    init(
        configStore: ConfigStore = ConfigStore(),
        config: AppConfig = AppConfig(),
        notifier: any NotificationDispatching = Notifier(),
        injector: any TextInjecting = TextInjector(),
        overlay: (any OverlayControlling)? = nil,
        authManager: any ChatGPTAuthProviding = ChatGPTAuthManager(),
        latencyRecorder: (any LatencyRecording)? = nil,
        productMetricsRecorder: (any ProductMetricsRecording)? = nil,
        historyRecorder: (any TranscriptionHistoryRecording)? = nil,
        recoveryRecorder: (any RecoveryRecording)? = nil,
        soundFeedback: any SoundFeedbackPlaying = SoundFeedbackService(),
        recoveryCredentialStore: any OpenAICompatibleCredentialPersisting =
            KeychainOpenAICompatibleCredentialStore(),
        hotkeyRegistrationService: HotkeyRegistrationService =
            HotkeyRegistrationService(),
        recorderFactory: @escaping RecorderFactory = { AudioRecorder(sampleRateHz: $0) },
        statusMenuFactory: @escaping StatusMenuFactory = {
            openHistory,
            openQuickAdd,
            openTerminology,
            openSettings,
            checkForUpdates,
            quit in
            StatusMenuController(
                openHistoryHandler: openHistory,
                openQuickAddHandler: openQuickAdd,
                openTerminologyHandler: openTerminology,
                openSettingsHandler: openSettings,
                checkForUpdatesHandler: checkForUpdates,
                quitHandler: quit
            )
        },
        softwareUpdater: (any SoftwareUpdating)? = nil,
        providerCapabilityPolicy: any ProviderCapabilityChecking = ProviderCapabilityPolicyController.shared,
        licenseManager: any CommercialLicenseManaging =
            StaticLicenseManager.preview,
        pipelineFactory: @escaping PipelineFactory = {
            transcriptionConfig,
            authManager,
            attemptPolicy,
            providerCapabilityPolicy,
            recoveryCredentialStore in
            let textPolishConfig = transcriptionConfig.textPolish
            let skillPlan =
                transcriptionConfig
                    .resolvedSkillPlan
                ?? SkillResolver().resolve(
                    config:
                        transcriptionConfig
                            .skills,
                    launchAppContext: nil
                )
            let dictationMode =
                skillPlan.legacyMode
            let chatGPTAuthAvailable =
                authManager.authSnapshot().state == .ready
            let textPolishAvailable = TextPolishProviderSelector()
                .selectProvider(
                    config: textPolishConfig,
                    chatGPTAuthAvailable: chatGPTAuthAvailable
                ) != nil
            let textPolisher: (any TextPolishing)? = textPolishAvailable
                ? OpenAICompatibleTextPolisher(
                    config: textPolishConfig,
                    dictationMode: dictationMode,
                    skillPlan: skillPlan,
                    skillPromptContext:
                        transcriptionConfig
                            .skillPromptContext,
                    chatGPTAuthProvider: authManager,
                    chatGPTAuthAvailable: chatGPTAuthAvailable,
                    providerCapabilityPolicy: providerCapabilityPolicy,
                    providerHealthMonitor: ProviderHealthMonitor.shared
                )
                : nil

            return DictationPipeline(
                transcriber: ChatGPTTranscriber(
                    authManager: authManager,
                    config: transcriptionConfig,
                    providerCapabilityPolicy: providerCapabilityPolicy,
                    providerHealthMonitor: ProviderHealthMonitor.shared,
                    recoveryCredentialStore: recoveryCredentialStore,
                    cloudflareChallengeMaxAttempts:
                        attemptPolicy.cloudflareChallengeMaxAttempts,
                    transientFailureMaxAttempts:
                        attemptPolicy.transientFailureMaxAttempts
                ),
                normalizer: TerminologyNormalizer(
                    languagePreference: transcriptionConfig.languagePreference,
                    punctuationPreference: transcriptionConfig.punctuationPreference
                ),
                importedEntries: transcriptionConfig.activeDictionaryEntries,
                hintTerms: transcriptionConfig.hintTerms,
                textPolisher: textPolisher,
                textPolishConfig: textPolishConfig,
                dictationMode: dictationMode,
                skillPlan: skillPlan,
                skillPromptContext:
                    transcriptionConfig
                        .skillPromptContext
            )
        },
        launchAppContextProvider: @escaping LaunchAppContextProvider = { LaunchAppContext.current() },
        contextBroker: ContextBroker = .init(),
        contextPermissionPrompter:
            (any ContextPermissionPrompting)? = nil,
        previewPresenter:
            (any PreviewPresenting)? = nil,
        outputRouter: OutputRouter = .init()
    ) {
        self.configStore = configStore
        self.config = config
        self.notifier = notifier
        self.injector = injector
        let resolvedOverlay =
            overlay ?? FeedbackSurfaceController()
        self.overlay = resolvedOverlay
        self.authManager = authManager
        self.latencyRecorder = latencyRecorder ?? LatencyRecorder(directoryURL: configStore.directoryURL)
        self.productMetricsRecorder = productMetricsRecorder
            ?? ProductMetricsRecorder(
                directoryURL: configStore.directoryURL
            )
        self.historyRecorder = historyRecorder ?? TranscriptionHistoryRecorder(directoryURL: configStore.directoryURL)
        self.recoveryRecorder = recoveryRecorder ?? RecoveryStore(
            directoryURL: configStore.directoryURL.appendingPathComponent("Recovery", isDirectory: true)
        )
        self.soundFeedback = soundFeedback
        self.softwareUpdater = softwareUpdater ?? SparkleSoftwareUpdater()
        self.providerCapabilityPolicy = providerCapabilityPolicy
        self.recoveryCredentialStore = recoveryCredentialStore
        self.licenseManager = licenseManager
        self.hotkeyRegistrationService =
            hotkeyRegistrationService
        self.recorderFactory = recorderFactory
        self.statusMenuFactory = statusMenuFactory
        self.pipelineFactory = pipelineFactory
        self.launchAppContextProvider = launchAppContextProvider
        self.contextBroker = contextBroker
        self.contextPermissionPrompter =
            contextPermissionPrompter
            ?? ContextPermissionPromptController()
        self.previewPresenter =
            previewPresenter
            ?? PreviewWindowController()
        self.outputRouter = outputRouter
        self.overlay.onCancel = { [weak self] source in
            self?.cancelCurrentSession(source: source)
        }
        self.overlay.onRetry = { [weak self] in
            self?.retryPendingTranscription()
        }
        authStateObserver = NotificationCenter.default.addObserver(
            forName: .chatGPTAuthStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshReadyState()
            }
        }
    }

    func start(launchMode: AppLaunchMode = .normal) {
        do {
            snapshotPrivacyMode = SnapshotPrivacyMode.resolve(
                environment: ProcessInfo.processInfo.environment,
                arguments: ProcessInfo.processInfo.arguments
            )

            if let launchBlocker = AppInstallLocation.launchBlocker() {
                NSSound.beep()
                showInstallRequiredAlert(message: launchBlocker.message)
                notifier.notify(title: L10n.text("OpenWhisper install required"), body: launchBlocker.message)
                AppInstallLocation.revealApplicationsFolder()
                NSApplication.shared.terminate(nil)
                return
            }

            statusMenu = statusMenuFactory(
                { [weak self] in self?.openHistory() },
                { [weak self] in self?.openQuickAdd() },
                { [weak self] in self?.openTerminology() },
                { [weak self] in self?.openSettings() },
                { [weak self] in self?.checkForUpdates() },
                { NSApplication.shared.terminate(nil) }
            )
            statusMenu?.setToggleDictationHandler { [weak self] in
                self?.handleHotkeyPress()
            }
            statusMenu?.setRetryDictationHandler {
                [weak self] in
                self?.retryPendingTranscription()
            }
            statusMenu?.setManualDictationAvailable(false)
            statusMenu?.setRetryDictationAvailable(false)

            switch launchMode {
            case .normal,
                 .settings,
                 .privacySettings,
                 .advancedSettings,
                 .accessibilityGuide,
                 .onboarding,
                 .history,
                 .terminology,
                 .quickAdd:
                if snapshotPrivacyMode.isEnabled {
                    config = AppConfig()
                } else {
                    config = try configStore.load()
                    enforceStoragePolicies()
                    if launchMode == .normal {
                        recordProductMetric(event: .appLaunch)
                    }
                    Task { [providerCapabilityPolicy] in
                        _ = await providerCapabilityPolicy.refresh(force: false)
                    }
                    recorder = recorderFactory(config.transcription.sampleRateHz)
                    recorder?.configure(maxDurationSeconds: config.transcription.maxDurationSeconds)
                    overlay.updateVisualFeedbackConfiguration(
                        config.visualFeedback
                    )
                    configureDictationHotkeyAtStartup()
                    refreshReadyState()
                    checkLaunchLoginState()
                    prewarmAuthIfNeeded()

                    do {
                        quickAddHotkeyMonitor = try HotkeyMonitor(
                            keyCode: OpenWhisperHotkeys.quickAddKeyCode,
                            modifiers: OpenWhisperHotkeys.quickAddModifiers
                        ) { [weak self] in
                            Task { @MainActor in
                                self?.openQuickAdd()
                            }
                        }
                    } catch {
                        logger.error(
                            "Quick Add hotkey registration failed: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                    notifier.ensureAuthorization()
                }
                if launchMode == .settings
                    || launchMode == .privacySettings
                    || launchMode == .advancedSettings
                    || launchMode == .accessibilityGuide
                {
                    let focusedPane: SettingsPane? = switch launchMode {
                    case .privacySettings:
                        .privacy
                    case .advancedSettings:
                        .advanced
                    default:
                        AppLaunchMode.settingsPane(
                            arguments: ProcessInfo.processInfo.arguments
                        )
                    }
                    openSettings(focusPane: focusedPane)
                    scheduleSettingsSnapshotIfRequested()
                    scheduleAccessibilityAuditIfRequested(
                        window: preferencesWindowController?.window,
                        surface: "settings-\((focusedPane ?? .account).launchArgumentValue)"
                    )
                }
                if launchMode == .accessibilityGuide {
                    DispatchQueue.main.async {
                        AccessibilityPermission.guideAccess()
                    }
                }
                if launchMode == .onboarding {
                    let onboardingStep = AppLaunchMode.onboardingStep(
                        arguments: ProcessInfo.processInfo.arguments
                    ) ?? .welcome
                    openOnboarding(initialStep: onboardingStep)
                    scheduleOnboardingSnapshotIfRequested()
                    scheduleAccessibilityAuditIfRequested(
                        window: onboardingWindowController?.window,
                        surface: "onboarding-\(onboardingStep.launchArgumentValue)"
                    )
                }
                if launchMode == .history {
                    openHistory()
                    scheduleProductSurfaceSnapshotIfRequested(mode: .history)
                    scheduleAccessibilityAuditIfRequested(
                        window: historyWindowController?.window,
                        surface: "history"
                    )
                }
                if launchMode == .terminology {
                    openTerminology()
                    scheduleProductSurfaceSnapshotIfRequested(mode: .terminology)
                    scheduleAccessibilityAuditIfRequested(
                        window: terminologyWindowController?.window,
                        surface: "terminology"
                    )
                }
                if launchMode == .quickAdd {
                    openQuickAdd()
                    scheduleProductSurfaceSnapshotIfRequested(mode: .quickAdd)
                    scheduleAccessibilityAuditIfRequested(
                        window: terminologyQuickAddWindowController?.window,
                        surface: "quick-add"
                    )
                }
                if launchMode == .normal, OnboardingStateStore().shouldPresent() {
                    DispatchQueue.main.async { [weak self] in
                        self?.openOnboarding()
                    }
                }
            case .previewDemo:
                runPreviewDemo()
                return
            case .overlayDemo:
                config = snapshotPrivacyMode.isEnabled
                    ? AppConfig()
                    : ((try? configStore.load()) ?? config)
                applyVisualFeedbackLaunchOverride()
                applyActiveDictationHotkey(
                    config.transcription.dictationHotkey
                )
                overlay.updateVisualFeedbackConfiguration(
                    config.visualFeedback
                )
                runOverlayDemo()
                return
            case .overlayDemoState(let demoState):
                config = snapshotPrivacyMode.isEnabled
                    ? AppConfig()
                    : ((try? configStore.load()) ?? config)
                applyVisualFeedbackLaunchOverride()
                applyActiveDictationHotkey(
                    config.transcription.dictationHotkey
                )
                overlay.updateVisualFeedbackConfiguration(
                    config.visualFeedback
                )
                runOverlayDemoState(demoState)
                return
            case .pasteAcceptance:
                runPasteAcceptance()
                return
            case .benchmark:
                config = try configStore.load()
                Task {
                    defer { NSApplication.shared.terminate(nil) }
                    do {
                        let runner = BenchmarkRunner(
                            config: config,
                            authManager: authManager
                        )
                        try await runner.run()
                    } catch {
                        print("Benchmark failed: \(error.localizedDescription)")
                    }
                }
                return
            }
        } catch {
            NSSound.beep()
            notifier.notify(title: L10n.text("OpenWhisper launch failed"), body: error.localizedDescription)
            statusMenu?.update(state: .error, detail: error.localizedDescription)
        }
    }

    private var activeDictationHotkey: HotkeyBinding {
        hotkeyRegistrationService.activeBinding
            ?? config.transcription.dictationHotkey
    }

    private func applyVisualFeedbackLaunchOverride() {
        guard
            let mode = AppLaunchMode
                .visualFeedbackModeOverride(
                    environment:
                        ProcessInfo.processInfo
                            .environment,
                    arguments:
                        ProcessInfo.processInfo
                            .arguments
                )
        else {
            return
        }
        config.visualFeedback.mode = mode
    }

    private func dictationHotkeyPressHandler()
        -> @Sendable () -> Void
    {
        { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleHotkeyPress()
            }
        }
    }

    private func configureDictationHotkeyAtStartup() {
        let requested = config.transcription.dictationHotkey
        let outcome = hotkeyRegistrationService.start(
            preferred: requested,
            onPress: dictationHotkeyPressHandler()
        )

        switch outcome {
        case .registered(let binding):
            hotkeyRegistrationIssue = nil
            applyActiveDictationHotkey(binding)
        case .fellBack(
            let requested,
            let active,
            let reason
        ):
            hotkeyRegistrationIssue = nil
            config.transcription.dictationHotkey = active
            try? configStore.save(config)
            applyActiveDictationHotkey(active)
            let detail = L10n.format(
                "%@ could not be registered. OpenWhisper restored %@. Choose another shortcut in Settings. %@",
                requested.displayName,
                active.displayName,
                reason
            )
            logger.error(
                "Dictation shortcut fallback requested=\(requested.displayName, privacy: .public) active=\(active.displayName, privacy: .public) reason=\(reason, privacy: .public)"
            )
            notifier.notify(
                title: L10n.text(
                    "OpenWhisper shortcut restored"
                ),
                body: detail
            )
        case .unavailable(_, let reason):
            hotkeyRegistrationIssue = L10n.format(
                "The global dictation shortcut is unavailable. Use Start or Stop Dictation from the menu and choose another shortcut in Settings. %@",
                reason
            )
            applyActiveDictationHotkey(requested)
            logger.error(
                "Dictation shortcut registration unavailable: \(reason, privacy: .public)"
            )
            notifier.notify(
                title: L10n.text(
                    "OpenWhisper shortcut unavailable"
                ),
                body: hotkeyRegistrationIssue
                    ?? reason
            )
        }

        statusMenu?.setManualDictationAvailable(
            recorder != nil
        )
    }

    private func applyActiveDictationHotkey(
        _ binding: HotkeyBinding
    ) {
        overlay.updateHotkeyBinding(binding)
        statusMenu?.updateDictationHotkey(binding)
    }

    private func setHotkeyCaptureActive(
        _ isCapturing: Bool
    ) {
        if isCapturing {
            if state != .idle {
                cancelCurrentSession()
            }
            hotkeyRegistrationService.suspend()
            return
        }

        do {
            try hotkeyRegistrationService.resume()
            if let activeBinding =
                hotkeyRegistrationService
                    .activeBinding
            {
                applyActiveDictationHotkey(
                    activeBinding
                )
            }
        } catch {
            logger.error(
                "Restoring the dictation shortcut after recorder capture failed: \(error.localizedDescription, privacy: .public)"
            )
            configureDictationHotkeyAtStartup()
            refreshReadyState()
        }
    }

    func handleHotkeyPress() {
        logger.info(
            "Dictation trigger received shortcut=\(self.activeDictationHotkey.displayName, privacy: .public) state=\(String(describing: self.state), privacy: .public)"
        )
        switch state {
        case .idle:
            cancelVisualFeedbackPreview()
            startRecording()
        case .recording:
            stopRecording()
        case .processing:
            NSSound.beep()
        }
    }

    private func cancelVisualFeedbackPreview() {
        guard visualFeedbackPreviewTask != nil else {
            return
        }
        visualFeedbackPreviewTask?.cancel()
        visualFeedbackPreviewTask = nil
        previewDemoTask?.cancel()
        previewDemoTask = nil
        overlay.hide()
        overlay.updateVisualFeedbackConfiguration(
            config.visualFeedback
        )
    }

    private func previewVisualFeedback(
        _ preview: VisualFeedbackPreview,
        config: VisualFeedbackConfig
    ) {
        guard state == .idle else {
            NSSound.beep()
            return
        }

        cancelVisualFeedbackPreview()
        overlay.updateVisualFeedbackConfiguration(
            config
        )
        switch preview {
        case .recording:
            overlay.showRecording(
                elapsedText: "00:07"
            )
            overlay.updateRecording(
                level: 0.72,
                elapsedText: "00:07"
            )
        case .processing:
            overlay.showProcessing()
        case .copied:
            overlay.showResult(
                text: L10n.text("Preview"),
                outcome: .copiedToClipboard(
                    reason: .noEditableTarget
                )
            )
        case .error:
            overlay.showError(
                L10n.text(
                    "Preview error — no user data was used."
                )
            )
        }

        visualFeedbackPreviewTask =
            Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(
                        for: .seconds(2.4)
                    )
                } catch {
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                self?.overlay.hide()
                if let self {
                    self.overlay
                        .updateVisualFeedbackConfiguration(
                            self.config
                                .visualFeedback
                        )
                }
                self?.visualFeedbackPreviewTask =
                    nil
            }
    }

    func cancelCurrentSession(source: OverlayCancelSource? = nil) {
        let sourceLabel = source?.rawValue ?? "programmatic"
        logger.info(
            "Cancel requested source=\(sourceLabel, privacy: .public) state=\(String(describing: self.state), privacy: .public) activeSession=\(self.activeSessionID != nil, privacy: .public) startTask=\(self.startRecordingTask != nil, privacy: .public) processingTask=\(self.processingTask != nil, privacy: .public)"
        )
        guard state != .idle || activeSessionID != nil || processingTask != nil || startRecordingTask != nil else {
            logger.debug("Cancel request ignored because no dictation session is active")
            return
        }

        recordProductMetric(
            event: .dictationDiscarded,
            provider: config.transcription.provider
        )
        startRecordingTask?.cancel()
        startRecordingTask = nil
        processingTask?.cancel()
        processingTask = nil
        previewPresenter.dismiss()
        stopRecordingLevelUpdates()
        clearPendingRetry()

        if state == .recording {
            do {
                try recorder?.cancelRecording()
                logger.info("Active recording was cancelled and its audio was discarded")
            } catch {
                logger.error("Cancelling active recording failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        state = .idle
        activeSessionID = nil
        recordingStartedAt = nil
        recordingTranscriptionConfig = nil
        recordingPreparedContext =
            PreparedSkillContext()
        launchAppContext = nil
        overlay.hide()
        refreshReadyState()
        logger.info("Cancellation completed; state returned to idle")
    }

    func shutdown() {
        hotkeyRegistrationService.stop()
        visualFeedbackPreviewTask?.cancel()
        visualFeedbackPreviewTask = nil
        startRecordingTask?.cancel()
        startRecordingTask = nil
        processingTask?.cancel()
        processingTask = nil
        previewPresenter.dismiss()
        pendingRetryExpiryTask?.cancel()
        pendingRetryExpiryTask = nil
        stopRecordingLevelUpdates()

        if state == .recording {
            try? recorder?.cancelRecording()
        }
        if let activeProcessingAudio, activeProcessingAudio.deleteWhenFinished {
            try? FileManager.default.removeItem(at: activeProcessingAudio.fileURL)
        }
        activeProcessingAudio = nil
        clearPendingRetry()
        _ = TemporaryArtifactCleanupService().cleanupOrphans()
        state = .idle
        activeSessionID = nil
        recordingStartedAt = nil
        recordingTranscriptionConfig = nil
        recordingPreparedContext =
            PreparedSkillContext()
        launchAppContext = nil
        overlay.hide()
    }

    private func startRecording() {
        guard let recorder else { return }

        clearPendingRetry()
        logger.info("Start recording requested from hotkey")
        let sessionID = UUID()
        logger.info("Allocated recording session \(sessionID.uuidString, privacy: .public)")
        activeSessionID = sessionID
        launchAppContext = launchAppContextProvider()
        recordingPreparedContext =
            PreparedSkillContext()
        recordingTranscriptionConfig = config.transcription
            .resolvingVoiceMode(
                for: launchAppContext,
                voiceModesAllowed: licenseManager
                    .snapshot()
                    .allows(.voiceModes)
            )
        state = .processing
        statusMenu?.update(state: .processing, detail: L10n.text("Requesting microphone"))
        overlay.showProcessing()

        startRecordingTask?.cancel()
        startRecordingTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                if self.config.transcription.provider == .chatGPTManagedAuth {
                    self.statusMenu?.update(
                        state: .processing,
                        detail: L10n.text("Checking provider safety")
                    )
                    try await self.providerCapabilityPolicy.require(
                        .managedTranscription
                    )
                    guard self.shouldContinue(sessionID: sessionID) else { return }
                }

                self.statusMenu?.update(
                    state: .processing,
                    detail: L10n.text("Requesting microphone")
                )
                try await self.requestMicrophoneAccess()
                guard self.shouldContinue(sessionID: sessionID) else { return }
                logger.info("Microphone access stage completed")

                let issues = RuntimePreflight.issues(
                    for: self.config,
                    authSnapshotProvider: { self.authManager.authSnapshot() },
                    recoveryCredentialAvailable: {
                        try self.recoveryCredentialStore.hasAPIKey()
                    }
                )
                if let message = RuntimePreflight.summary(for: issues) {
                    logger.error("Runtime preflight blocked recording with \(issues.count, privacy: .public) issue(s): \(message, privacy: .public)")
                    self.stopRecordingLevelUpdates()
                    self.state = .idle
                    self.activeSessionID = nil
                    self.recordingTranscriptionConfig = nil
                    self.recordingPreparedContext =
                        PreparedSkillContext()
                    self.statusMenu?.update(state: .setupRequired, detail: message)
                    self.overlay.showError(message)
                    self.notifier.notify(title: L10n.text("OpenWhisper setup required"), body: message)
                    self.recordProductMetric(
                        event: .dictationFailed,
                        provider: self.config.transcription.provider,
                        failureCategory: .setup
                    )
                    self.openSettings()
                    return
                }

                let resolvedPlan =
                    self.recordingTranscriptionConfig?
                        .resolvedSkillPlan
                    ?? .direct
                self.statusMenu?.update(
                    state: .processing,
                    detail: L10n.text(
                        "Checking selected text access"
                    )
                )
                let preparedContext =
                    await self.contextBroker.prepare(
                        plan: resolvedPlan,
                        launchAppContext:
                            self.launchAppContext,
                        contextConfig:
                            self.config.context,
                        privacyConfig:
                            self.config.privacy,
                        permissionPrompter:
                            self.contextPermissionPrompter
                    )
                guard
                    self.shouldContinue(
                        sessionID: sessionID
                    )
                else {
                    return
                }
                if preparedContext.shouldCancel {
                    self.cancelCurrentSession()
                    return
                }
                if
                    let grant =
                        preparedContext
                            .persistentGrant
                {
                    self.config.context.setScope(
                        grant.scope,
                        skillID:
                            grant.skillID,
                        capability:
                            grant.capability
                    )
                    if !self.snapshotPrivacyMode
                        .isEnabled
                    {
                        try? self.configStore
                            .save(self.config)
                    }
                }
                self.recordingPreparedContext =
                    preparedContext
                if
                    var frozenConfig =
                        self.recordingTranscriptionConfig
                {
                    frozenConfig
                        .skillPromptContext =
                        preparedContext
                            .promptContext
                    self.recordingTranscriptionConfig =
                        frozenConfig
                }

                logger.info("Runtime preflight passed; starting recording session")
                if let audioRecorder = recorder as? AudioRecorder {
                    audioRecorder.configure(maxDurationSeconds: self.config.transcription.maxDurationSeconds)
                    audioRecorder.onMaximumDurationReached = { [weak self] in
                        guard let self, self.activeSessionID == sessionID, self.state == .recording else {
                            return
                        }
                        self.stopRecording()
                    }
                }
                try await recorder.startRecording()
                guard self.shouldContinue(sessionID: sessionID) else {
                    try? recorder.cancelRecording()
                    return
                }

                logger.info("Recording session \(sessionID.uuidString, privacy: .public) started successfully")
                self.recordingStartedAt = .now()
                self.state = .recording
                self.statusMenu?.update(
                    state: .recording,
                    detail: L10n.format(
                        "Recording — press %@ to transcribe",
                        self.activeDictationHotkey
                            .displayName
                    )
                )
                self.overlay.showRecording(elapsedText: "00:00")
                self.recordProductMetric(
                    event: .dictationStarted,
                    provider: self.config.transcription.provider
                )
                self.soundFeedback.play(.recordingStarted, enabled: self.config.transcription.feedbackSoundsEnabled)
                self.startRecordingLevelUpdates()
            } catch is CancellationError {
                self.cancelCurrentSession()
            } catch {
                guard self.shouldContinue(sessionID: sessionID) else { return }
                logger.error("Start recording failed: \(error.localizedDescription, privacy: .public)")
                self.stopRecordingLevelUpdates()
                self.state = .idle
                self.activeSessionID = nil
                self.recordingStartedAt = nil
                self.recordingTranscriptionConfig = nil
                self.recordingPreparedContext =
                    PreparedSkillContext()
                self.refreshReadyState(detailOverride: error.localizedDescription, state: .error)
                self.overlay.showError(error.localizedDescription)
                self.notifier.notify(title: "OpenWhisper", body: error.localizedDescription)
                self.launchAppContext = nil
                self.recordProductMetric(
                    event: .dictationFailed,
                    provider: self.config.transcription.provider,
                    failureCategory: .recording
                )
            }

            if self.activeSessionID == sessionID {
                self.startRecordingTask = nil
            }
        }
    }

    private func stopRecording() {
        guard let recorder, let sessionID = activeSessionID else {
            logger.error(
                "Dictation stop request ignored because no active recorder/session was available"
            )
            return
        }

        do {
            logger.info(
                "Stopping recording session \(sessionID.uuidString, privacy: .public) from dictation shortcut"
            )
            stopRecordingLevelUpdates()
            let audio = try recorder.stopRecording()
            let audioBytes = Self.audioFileSize(at: audio.fileURL)
            logger.info(
                "Recording stopped durationMs=\(audio.durationMs, privacy: .public) audioBytes=\(audioBytes, privacy: .public) file=\(audio.fileURL.lastPathComponent, privacy: .public)"
            )
            recordingStartedAt = nil
            state = .processing
            statusMenu?.update(state: .processing, detail: L10n.text("Processing"))
            overlay.showProcessing()
            soundFeedback.play(.recordingStopped, enabled: config.transcription.feedbackSoundsEnabled)

            let launchAppContext = self.launchAppContext
            let transcriptionConfig =
                recordingTranscriptionConfig
                ?? config.transcription.resolvingVoiceMode(
                    for: launchAppContext,
                    voiceModesAllowed: licenseManager
                        .snapshot()
                        .allows(.voiceModes)
                )
            recordingTranscriptionConfig = nil
            let preparedContext =
                recordingPreparedContext
            recordingPreparedContext =
                PreparedSkillContext()
            let injectionConfig = config.injection
            startProcessing(
                audio: audio,
                sessionID: sessionID,
                transcriptionConfig: transcriptionConfig,
                injectionConfig: injectionConfig,
                launchAppContext: launchAppContext,
                attemptPolicy: .automatic,
                deleteAudioWhenFinished: true,
                automaticPasteAllowed: true,
                preparedSkillContext:
                    preparedContext
            )
        } catch {
            logger.error("Stopping recording failed: \(error.localizedDescription, privacy: .public)")
            stopRecordingLevelUpdates()
            state = .idle
            activeSessionID = nil
            recordingStartedAt = nil
            recordingTranscriptionConfig = nil
            recordingPreparedContext =
                PreparedSkillContext()
            statusMenu?.update(state: .error, detail: error.localizedDescription)
            overlay.showError(error.localizedDescription)
            notifier.notify(title: "OpenWhisper", body: error.localizedDescription)
            recordProductMetric(
                event: .dictationFailed,
                provider: config.transcription.provider,
                failureCategory: .recording
            )
        }
    }

    private func retryPendingTranscription() {
        guard state == .idle, let pendingRetry else {
            NSSound.beep()
            return
        }
        guard pendingRetry.expiresAt > Date() else {
            clearPendingRetry()
            overlay.showError(L10n.text("The saved retry recording expired and was deleted."))
            return
        }

        let sessionID = UUID()
        activeSessionID = sessionID
        state = .processing
        statusMenu?.setRetryDictationAvailable(false)
        statusMenu?.update(state: .processing, detail: L10n.text("Retrying"))
        overlay.showProcessing()
        recordProductMetric(
            event: .retryStarted,
            provider: pendingRetry.transcriptionConfig.provider,
            audioDurationMs: pendingRetry.audio.durationMs
        )

        startProcessing(
            audio: pendingRetry.audio,
            sessionID: sessionID,
            transcriptionConfig: pendingRetry.transcriptionConfig,
            injectionConfig: pendingRetry.injectionConfig,
            launchAppContext: pendingRetry.launchAppContext,
            attemptPolicy: .manualRetry,
            deleteAudioWhenFinished: false,
            automaticPasteAllowed: false,
            preparedSkillContext:
                PreparedSkillContext()
        )
    }

    private func startProcessing(
        audio: RecordedAudio,
        sessionID: UUID,
        transcriptionConfig: TranscriptionConfig,
        injectionConfig: InjectionConfig,
        launchAppContext: LaunchAppContext?,
        attemptPolicy: TranscriptionAttemptPolicy,
        deleteAudioWhenFinished: Bool,
        automaticPasteAllowed: Bool,
        preparedSkillContext:
            PreparedSkillContext
    ) {
        let processingStarted = DispatchTime.now().uptimeNanoseconds
        let initialAudioBytes = Self.audioFileSize(at: audio.fileURL)
        logger.info(
            "Processing started session=\(sessionID.uuidString, privacy: .public) provider=\(transcriptionConfig.provider.rawValue, privacy: .public) skill=\(transcriptionConfig.resolvedSkillPlan?.skill.id ?? transcriptionConfig.skills.defaultSkillID, privacy: .public) durationMs=\(audio.durationMs, privacy: .public) audioBytes=\(initialAudioBytes, privacy: .public) cloudflareAttempts=\(attemptPolicy.cloudflareChallengeMaxAttempts, privacy: .public)"
        )

        processingTask?.cancel()
        activeProcessingAudio = ActiveProcessingAudio(
            fileURL: audio.fileURL,
            deleteWhenFinished: deleteAudioWhenFinished
        )
        processingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if deleteAudioWhenFinished {
                    try? FileManager.default.removeItem(at: audio.fileURL)
                    self.logger.debug("Removed temporary recording \(audio.fileURL.lastPathComponent, privacy: .public)")
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.activeProcessingAudio?.fileURL == audio.fileURL {
                        self.activeProcessingAudio = nil
                    }
                    if self.activeSessionID == sessionID || self.activeSessionID == nil {
                        self.processingTask = nil
                    }
                }
            }

            let pipeline = self.pipelineFactory(
                transcriptionConfig,
                self.authManager,
                attemptPolicy,
                self.providerCapabilityPolicy,
                self.recoveryCredentialStore
            )

            do {
                self.logger.info("Submitting recording to dictation pipeline")
                let prepared = try await pipeline.prepare(audio: audio)
                guard !Task.isCancelled else { return }
                self.logger.info(
                    "Dictation pipeline completed transcriptCharacters=\(prepared.rawText.count, privacy: .public) finalCharacters=\(prepared.finalText.count, privacy: .public) authMs=\(prepared.metrics.transcription.authMs, privacy: .public) transcribeMs=\(prepared.metrics.transcription.transcribeMs, privacy: .public) polishDecision=\(prepared.metrics.textPolishDecisionReason?.rawValue ?? "none", privacy: .public) polishMs=\(prepared.metrics.polishMs, privacy: .public)"
                )

                let canInject = await MainActor.run {
                    self.shouldContinue(sessionID: sessionID)
                }
                guard canInject else { return }

                let executionPlan =
                    transcriptionConfig
                        .resolvedSkillPlan
                    ?? SkillResolver().resolve(
                        config:
                            transcriptionConfig
                                .skills,
                        launchAppContext: nil
                    )
                let route =
                    await MainActor.run {
                        self.outputRouter.route(
                            plan:
                                executionPlan,
                            automaticPasteAllowed:
                                automaticPasteAllowed,
                            hasSelectionContext:
                                preparedSkillContext
                                    .selectionSnapshot
                                    != nil
                        )
                    }
                var deliveryAllowsAutomaticPaste =
                    route == .automatic
                var automaticFallbackReason:
                    ClipboardFallbackReason =
                        attemptPolicy
                            == .manualRetry
                            ? .retryRequiresManualPaste
                            : .deliveryRequiresManualPaste
                var expectedSelectionContext:
                    SelectionContextSnapshot?

                if route == .preview {
                    await MainActor.run {
                        self.overlay.hide()
                        self.statusMenu?.update(
                            state: .processing,
                            detail: L10n.text(
                                "Waiting for preview"
                            )
                        )
                    }
                    let decision =
                        await self.previewPresenter
                            .present(
                                PreviewRequest(
                                    skillID:
                                        executionPlan
                                            .skill.id,
                                    skillVersion:
                                        executionPlan
                                            .skill.version,
                                    skillName:
                                        executionPlan
                                            .skill
                                            .localizedName,
                                    originalTranscript:
                                        prepared.rawText,
                                    resultText:
                                        prepared.finalText,
                                    selectedText:
                                        preparedSkillContext
                                            .promptContext
                                            .selection,
                                    contextCapabilities:
                                        preparedSkillContext
                                            .grantedCapabilities,
                                    validationPassed:
                                        prepared.metrics
                                            .skillValidationIssueCodes
                                            .isEmpty,
                                    allowsSelectionReplacement:
                                        preparedSkillContext
                                            .selectionSnapshot
                                            != nil
                                )
                            )
                    guard !Task.isCancelled else {
                        return
                    }
                    switch decision {
                    case .replaceSelection:
                        deliveryAllowsAutomaticPaste =
                            true
                        expectedSelectionContext =
                            preparedSkillContext
                                .selectionSnapshot
                    case .pasteToTarget:
                        deliveryAllowsAutomaticPaste =
                            true
                    case .copy:
                        deliveryAllowsAutomaticPaste =
                            false
                        automaticFallbackReason =
                            .deliveryRequiresManualPaste
                    case .cancel:
                        await MainActor.run {
                            guard
                                self.shouldContinue(
                                    sessionID:
                                        sessionID
                                )
                            else {
                                return
                            }
                            let totalProcessingMs =
                                self.elapsedMilliseconds(
                                    since:
                                        processingStarted
                                )
                            self.recordLatency(
                                prepared: prepared,
                                outcome: nil,
                                injectMs: 0,
                                totalProcessingMs:
                                    totalProcessingMs,
                                errorCategory:
                                    "preview_cancelled"
                            )
                            self.recordProductMetric(
                                event:
                                    .dictationDiscarded,
                                provider:
                                    prepared.metrics
                                        .transcription
                                        .provider,
                                audioDurationMs:
                                    prepared.metrics
                                        .transcription
                                        .audioDurationMs,
                                totalProcessingMs:
                                    totalProcessingMs
                            )
                            self.clearPendingRetry()
                            self.state = .idle
                            self.activeSessionID =
                                nil
                            self.statusMenu?.update(
                                state: .ready,
                                detail: L10n.text(
                                    "Preview cancelled"
                                )
                            )
                            self.overlay.hide()
                            self.launchAppContext =
                                nil
                        }
                        return
                    }
                } else if route == .copyOnly {
                    deliveryAllowsAutomaticPaste =
                        false
                }

                let injectStarted = DispatchTime.now().uptimeNanoseconds
                let outcome: InjectionOutcome
                do {
                    outcome = try await self.injector.inject(
                        text: prepared.finalText,
                        preserveClipboard: injectionConfig.preserveClipboard,
                        restoreDelayMilliseconds: injectionConfig.restoreDelayMilliseconds,
                        launchAppContext: launchAppContext,
                        automaticPasteAllowed:
                            deliveryAllowsAutomaticPaste,
                        automaticPasteFallbackReason:
                            automaticFallbackReason,
                        expectedSelectionContext:
                            expectedSelectionContext
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    self.logger.error("Transcript injection failed: \(error.localizedDescription, privacy: .public)")
                    await MainActor.run {
                        guard self.shouldContinue(sessionID: sessionID) else { return }
                        let totalProcessingMs = self.elapsedMilliseconds(since: processingStarted)
                        self.recordLatency(
                            prepared: prepared,
                            outcome: nil,
                            injectMs: 0,
                            totalProcessingMs: totalProcessingMs,
                            errorCategory: "inject"
                        )
                        self.recordProductMetric(
                            event: attemptPolicy == .manualRetry
                                ? .retryFailed
                                : .dictationFailed,
                            provider:
                                prepared.metrics.transcription.provider,
                            audioDurationMs:
                                prepared.metrics.transcription
                                    .audioDurationMs,
                            totalProcessingMs: totalProcessingMs,
                            failureCategory: .injection
                        )
                        self.clearPendingRetry()
                        self.state = .idle
                        self.activeSessionID = nil
                        self.statusMenu?.update(state: .error, detail: error.localizedDescription)
                        self.overlay.showError(error.localizedDescription)
                        self.notifier.notify(title: "OpenWhisper", body: error.localizedDescription)
                        self.launchAppContext = nil
                    }
                    return
                }

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.shouldContinue(sessionID: sessionID) else { return }
                    let injectMs = self.elapsedMilliseconds(since: injectStarted)
                    let totalProcessingMs = self.elapsedMilliseconds(since: processingStarted)
                    self.recordLatency(
                        prepared: prepared,
                        outcome: outcome,
                        injectMs: injectMs,
                        totalProcessingMs: totalProcessingMs,
                        errorCategory: nil
                    )
                    self.recordHistory(
                        prepared: prepared,
                        outcome: outcome,
                        launchAppContext: launchAppContext
                    )
                    self.recordProductMetric(
                        event: attemptPolicy == .manualRetry
                            ? .retrySucceeded
                            : .dictationSucceeded,
                        provider:
                            prepared.metrics.transcription.provider,
                        audioDurationMs:
                            prepared.metrics.transcription.audioDurationMs,
                        totalProcessingMs: totalProcessingMs,
                        deliveryStatus:
                            ProductMetricDeliveryStatus(outcome)
                    )
                    self.clearPendingRetry()
                    self.state = .idle
                    self.activeSessionID = nil
                    self.statusMenu?.update(
                        state: .ready,
                        detail: self.statusDetail(for: outcome)
                    )
                    self.overlay.showResult(text: prepared.finalText, outcome: outcome)
                    if self.config.visualFeedback
                        .completionNotificationEnabled
                    {
                        self.notifier.notify(
                            title: L10n.text(
                                "OpenWhisper dictation complete"
                            ),
                            body: self.statusDetail(
                                for: outcome
                            )
                        )
                    }
                    self.launchAppContext = nil
                    self.logger.info(
                        "Dictation session \(sessionID.uuidString, privacy: .public) completed outcome=\(self.latencyResultStatus(for: outcome), privacy: .public)"
                    )
                }
            } catch is CancellationError {
                self.logger.info("Dictation processing task was cancelled")
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.logger.error("Dictation pipeline failed: \(error.localizedDescription, privacy: .public)")

                await MainActor.run {
                    guard self.shouldContinue(sessionID: sessionID) else { return }

                    let totalProcessingMs = self.elapsedMilliseconds(
                        since: processingStarted
                    )
                    self.recordTranscriptionFailure(
                        audio: audio,
                        transcriptionConfig: transcriptionConfig,
                        processingStarted: processingStarted,
                        error: error
                    )
                    self.recordProductMetric(
                        event: attemptPolicy == .manualRetry
                            ? .retryFailed
                            : .dictationFailed,
                        provider: transcriptionConfig.provider,
                        audioDurationMs: audio.durationMs,
                        totalProcessingMs: totalProcessingMs,
                        failureCategory:
                            self.productMetricFailureCategory(for: error)
                    )
                    self.recordRecoveryFailure(
                        audio: audio,
                        launchAppContext: launchAppContext,
                        error: error
                    )

                    if self.isRetryableTranscriptionError(error) {
                        do {
                            try self.storePendingRetry(
                                audio: audio,
                                launchAppContext: launchAppContext,
                                transcriptionConfig: transcriptionConfig,
                                injectionConfig: injectionConfig
                            )
                            self.state = .idle
                            self.activeSessionID = nil
                            self.statusMenu?.update(state: .error, detail: error.localizedDescription)
                            self.overlay.showRetryableError(error.localizedDescription)
                            self.notifier.notify(title: "OpenWhisper", body: error.localizedDescription)
                            self.launchAppContext = nil
                        } catch {
                            self.clearPendingRetry()
                            self.state = .idle
                            self.activeSessionID = nil
                            self.statusMenu?.update(state: .error, detail: error.localizedDescription)
                            self.overlay.showError(error.localizedDescription)
                            self.notifier.notify(title: "OpenWhisper", body: error.localizedDescription)
                            self.launchAppContext = nil
                        }
                    } else {
                        self.clearPendingRetry()
                        self.state = .idle
                        self.activeSessionID = nil
                        self.statusMenu?.update(state: .error, detail: error.localizedDescription)
                        self.overlay.showError(error.localizedDescription)
                        self.notifier.notify(title: "OpenWhisper", body: error.localizedDescription)
                        self.launchAppContext = nil
                    }
                }
            }
        }
    }

    private func openSettings(
        focusPane: SettingsPane? = nil
    ) {
        if focusPane != nil {
            preferencesWindowController = nil
        }

        if preferencesWindowController == nil {
            let presentationConfig = snapshotPrivacyMode.presentationConfig(
                liveConfig: config
            )
            let authManager = snapshotPrivacyMode.presentationAuthManager(
                liveAuthManager: self.authManager
            )
            let credentialStore = snapshotPrivacyMode.presentationCredentialStore(
                liveCredentialStore: recoveryCredentialStore
            )
            preferencesWindowController = PreferencesWindowController(
                config: presentationConfig,
                authManager: authManager,
                onSave: { [weak self] newConfig in
                    guard let self else {
                        return .failure(
                            NSError(
                                domain: "OpenWhisper.Preferences",
                                code: 2,
                                userInfo: [
                                    NSLocalizedDescriptionKey: L10n.text("OpenWhisper settings are no longer available."),
                                ]
                            )
                        )
                    }
                    if self.snapshotPrivacyMode.isEnabled {
                        return .success(())
                    }
                    return self.saveConfig(
                        newConfig,
                        successMessage: L10n.text("Settings saved automatically")
                    )
                },
                onImportTerminologyDictionary: { [weak self] currentConfig, fileURL in
                    guard let self else {
                        return .failure(
                            NSError(
                                domain: "OpenWhisper.Preferences",
                                code: 1,
                                userInfo: [
                                    NSLocalizedDescriptionKey: L10n.text("OpenWhisper settings are no longer available."),
                                ]
                            )
                        )
                    }

                    if self.snapshotPrivacyMode.isEnabled {
                        return .success(currentConfig)
                    }

                    do {
                        let imported = try TerminologyTextImporter().importEntries(from: fileURL)
                        var updatedConfig = currentConfig
                        updatedConfig.transcription.terminology.enabled = true
                        updatedConfig.transcription.terminology.entries = Self.mergedTerminologyEntries(
                            existing: updatedConfig.transcription.terminology.entries,
                            incoming: imported.entries
                        )
                        updatedConfig.transcription.terminology.lastImportedSource = fileURL.path
                        updatedConfig.transcription.terminology.lastImportedAt = imported.importedAt

                        try self.configStore.save(updatedConfig)
                        self.config = updatedConfig
                        self.refreshReadyState(
                            detailOverride: L10n.format(
                                "Imported %ld terminology terms",
                                imported.entries.count
                            ),
                            state: .ready
                        )

                        return .success(updatedConfig)
                    } catch {
                        return .failure(error)
                    }
                },
                onLoadRecentHistory: { [weak self] in
                    guard let self else {
                        return []
                    }
                    return self.snapshotPrivacyMode.loadPresentationRecords {
                        (try? self.historyRecorder.loadRecent(limit: 200)) ?? []
                    }
                },
                onLoadRecoveryHistory: { [weak self] in
                    guard let self else {
                        return []
                    }
                    return self.snapshotPrivacyMode.loadPresentationRecords {
                        (try? self.recoveryRecorder.loadRecent(limit: 10)) ?? []
                    }
                },
                onResolveRecoveryAudioURL: { [weak self] record in
                    guard let self else {
                        return .failure(RecoveryAudioError.missing)
                    }
                    if self.snapshotPrivacyMode.isEnabled {
                        return .failure(RecoveryAudioError.missing)
                    }
                    return Result {
                        try self.recoveryRecorder.resolveAudioURL(for: record)
                    }
                },
                onRetryRecoveryRecord: { [weak self] record in
                    guard self?.snapshotPrivacyMode.isEnabled == false else {
                        return
                    }
                    self?.retryRecoveryRecord(record)
                },
                onRequestMicrophoneAccess: { [weak self] in
                    guard let self else {
                        return .failure(
                            NSError(
                                domain: "OpenWhisper.Preferences",
                                code: 3,
                                userInfo: [
                                    NSLocalizedDescriptionKey: L10n.text(
                                        "OpenWhisper settings are no longer available."
                                    ),
                                ]
                            )
                        )
                    }
                    guard self.snapshotPrivacyMode.isEnabled == false else {
                        return .success(())
                    }

                    do {
                        try await self.requestMicrophoneAccess(
                            showExplanation: false
                        )
                        self.refreshReadyState()
                        return .success(())
                    } catch {
                        self.statusMenu?.update(
                            state: .setupRequired,
                            detail: error.localizedDescription
                        )
                        return .failure(error)
                    }
                },
                onOpenConfigFolder: { [weak self] in
                    guard self?.snapshotPrivacyMode.isEnabled == false else {
                        return
                    }
                    self?.openConfigFolder()
                },
                onExportSupportDiagnostics: { [weak self] destinationURL in
                    guard let self else {
                        return .failure(
                            NSError(
                                domain: "OpenWhisper.Diagnostics",
                                code: 1,
                                userInfo: [
                                    NSLocalizedDescriptionKey: L10n.text(
                                        "OpenWhisper settings are no longer available."
                                    ),
                                ]
                            )
                        )
                    }
                    if self.snapshotPrivacyMode.isEnabled {
                        return .failure(
                            NSError(
                                domain: "OpenWhisper.Diagnostics",
                                code: 2,
                                userInfo: [
                                    NSLocalizedDescriptionKey: L10n.text(
                                        "OpenWhisper settings are no longer available."
                                    ),
                                ]
                            )
                        )
                    }

                    return Result {
                        try SupportDiagnosticsExporter(
                            applicationSupportURL: self.configStore.directoryURL
                        ).export(
                            to: destinationURL,
                            config: self.config,
                            authSnapshot: self.authManager.authSnapshot(),
                            permissionSnapshot: .live(),
                            signatureState: AccessibilityPermission
                                .signatureState()
                        )
                    }
                },
                onExportProductMetrics: { [weak self] destinationURL in
                    guard let self else {
                        return .failure(
                            NSError(
                                domain: "OpenWhisper.ProductMetrics",
                                code: 1,
                                userInfo: [
                                    NSLocalizedDescriptionKey: L10n.text(
                                        "OpenWhisper settings are no longer available."
                                    ),
                                ]
                            )
                        )
                    }
                    if self.snapshotPrivacyMode.isEnabled {
                        return .failure(
                            NSError(
                                domain: "OpenWhisper.ProductMetrics",
                                code: 2,
                                userInfo: [
                                    NSLocalizedDescriptionKey: L10n.text(
                                        "OpenWhisper settings are no longer available."
                                    ),
                                ]
                            )
                        )
                    }

                    return Result {
                        try ProductMetricsExporter(
                            applicationSupportURL:
                                self.configStore.directoryURL
                        ).export(to: destinationURL)
                    }
                },
                providerCapabilityPolicy: providerCapabilityPolicy,
                recoveryCredentialStore: credentialStore,
                licenseManager: licenseManager,
                textPolishUsageDirectoryURL:
                    snapshotPrivacyMode.presentationDiagnosticsDirectoryURL(
                        liveDirectoryURL: configStore.directoryURL
                    ),
                softwareUpdateSnapshot: softwareUpdater.snapshot(),
                onCheckForUpdates: { [weak self] in
                    guard let self else {
                        return .failure(
                            .unavailable(
                                L10n.text(
                                    "OpenWhisper settings are no longer available."
                                )
                            )
                        )
                    }
                    if self.snapshotPrivacyMode.isEnabled {
                        return .failure(
                            .unavailable(
                                L10n.text(
                                    "OpenWhisper settings are no longer available."
                                )
                            )
                        )
                    }
                    return self.softwareUpdater.checkForUpdates()
                },
                onSetAutomaticallyChecksForUpdates: { [weak self] enabled in
                    guard let self else {
                        return .failure(
                            .unavailable(
                                L10n.text(
                                    "OpenWhisper settings are no longer available."
                                )
                            )
                        )
                    }
                    if self.snapshotPrivacyMode.isEnabled {
                        return .success(self.softwareUpdater.snapshot())
                    }
                    return self.softwareUpdater
                        .setAutomaticallyChecksForUpdates(enabled)
                },
                onDeleteAllData: { [weak self] in
                    guard let self else {
                        return .failure(
                            NSError(
                                domain: "OpenWhisper.Privacy",
                                code: 1,
                                userInfo: [
                                    NSLocalizedDescriptionKey: L10n.text("OpenWhisper settings are no longer available."),
                                ]
                            )
                        )
                    }
                    if self.snapshotPrivacyMode.isEnabled {
                        return .success(AppConfig())
                    }
                    return self.deleteAllUserData()
                },
                onOpenOnboarding: { [weak self] in
                    self?.openOnboarding()
                },
                onHotkeyCaptureChanged: {
                    [weak self] isCapturing in
                    self?.setHotkeyCaptureActive(
                        isCapturing
                    )
                },
                onPreviewVisualFeedback: {
                    [weak self] preview,
                    visualConfig in
                    self?.previewVisualFeedback(
                        preview,
                        config: visualConfig
                    )
                },
                focusPane: focusPane
            )
        }

        preferencesWindowController?.show()
    }

    private func openHistory() {
        if historyWindowController == nil {
            historyWindowController = HistoryWindowController(
                hotkeyBinding: activeDictationHotkey,
                onLoadTranscriptionHistory: { [weak self] in
                    guard let self else {
                        return []
                    }
                    return self.snapshotPrivacyMode.loadPresentationRecords {
                        (try? self.historyRecorder.loadRecent(limit: 500)) ?? []
                    }
                },
                onLoadRecoveryHistory: { [weak self] in
                    guard let self else {
                        return []
                    }
                    return self.snapshotPrivacyMode.loadPresentationRecords {
                        (try? self.recoveryRecorder.loadRecent(limit: 100)) ?? []
                    }
                },
                onResolveRecoveryAudioURL: { [weak self] record in
                    guard let self else {
                        return .failure(RecoveryAudioError.missing)
                    }
                    if self.snapshotPrivacyMode.isEnabled {
                        return .failure(RecoveryAudioError.missing)
                    }
                    return Result {
                        try self.recoveryRecorder.resolveAudioURL(for: record)
                    }
                },
                onRetryRecoveryRecord: { [weak self] record in
                    guard self?.snapshotPrivacyMode.isEnabled == false else {
                        return
                    }
                    self?.retryRecoveryRecord(record)
                },
                onDeleteTranscriptionRecord: { [weak self] id in
                    guard let self else {
                        return .failure(
                            NSError(
                                domain: "OpenWhisper.History",
                                code: 1,
                                userInfo: [
                                    NSLocalizedDescriptionKey: L10n.text(
                                        "OpenWhisper history is no longer available."
                                    ),
                                ]
                            )
                        )
                    }
                    if self.snapshotPrivacyMode.isEnabled {
                        return .success(())
                    }
                    return Result {
                        try self.historyRecorder.delete(id: id)
                    }
                },
                onDeleteRecoveryRecord: { [weak self] id in
                    guard let self else {
                        return .failure(
                            NSError(
                                domain: "OpenWhisper.History",
                                code: 2,
                                userInfo: [
                                    NSLocalizedDescriptionKey: L10n.text(
                                        "OpenWhisper history is no longer available."
                                    ),
                                ]
                            )
                        )
                    }
                    if self.snapshotPrivacyMode.isEnabled {
                        return .success(())
                    }
                    return Result {
                        try self.recoveryRecorder.delete(id: id)
                    }
                }
            )
        }
        historyWindowController?.show()
    }

    private func openQuickAdd() {
        guard licenseManager.snapshot().allows(.quickAdd) else {
            NSSound.beep()
            notifier.notify(
                title: L10n.text("OpenWhisper Pro required"),
                body: L10n.text(
                    "Quick Add is a Pro workflow. Core terminology management remains available in Community."
                )
            )
            openSettings(focusPane: .account)
            return
        }

        terminologyQuickAddWindowController?.close()
        terminologyQuickAddWindowController = TerminologyQuickAddWindowController(
            existingEntries: snapshotPrivacyMode.isEnabled
                ? []
                : config.transcription.terminology.entries,
            onSave: { [weak self] entry in
                guard let self else {
                    return .failure(
                        NSError(
                            domain: "OpenWhisper.Terminology",
                            code: 2,
                            userInfo: [
                                NSLocalizedDescriptionKey: L10n.text(
                                    "OpenWhisper terminology is no longer available."
                                ),
                            ]
                        )
                    )
                }
                if self.snapshotPrivacyMode.isEnabled {
                    return .success(())
                }

                guard !self.config.transcription.terminology.entries.contains(where: {
                    TerminologyLibrary.identityKey(for: $0)
                        == TerminologyLibrary.identityKey(for: entry)
                }) else {
                    return .failure(TerminologyQuickAddError.duplicate)
                }

                var newConfig = self.config
                newConfig.transcription.terminology.enabled = true
                newConfig.transcription.terminology.entries.append(entry)
                let result = self.saveConfig(
                    newConfig,
                    successMessage: L10n.text("Terminology entry saved.")
                )
                if case .success = result {
                    self.terminologyWindowController?.close()
                    self.terminologyWindowController = nil
                }
                return result
            }
        )
        terminologyQuickAddWindowController?.show()
    }

    private func openTerminology() {
        if terminologyWindowController == nil
            || terminologyWindowController?.window?.isVisible == false
        {
            terminologyWindowController = TerminologyWindowController(
                config: snapshotPrivacyMode.presentationConfig(
                    liveConfig: config
                ),
                onSave: { [weak self] newConfig in
                    guard let self else {
                        return .failure(
                            NSError(
                                domain: "OpenWhisper.Terminology",
                                code: 1,
                                userInfo: [
                                    NSLocalizedDescriptionKey: L10n.text(
                                        "OpenWhisper terminology is no longer available."
                                    ),
                                ]
                            )
                        )
                    }
                    if self.snapshotPrivacyMode.isEnabled {
                        return .success(())
                    }
                    return self.saveConfig(
                        newConfig,
                        successMessage: L10n.text("Terminology updated")
                    )
                }
            )
        }
        terminologyWindowController?.show()
    }

    private func saveConfig(
        _ newConfig: AppConfig,
        successMessage: String
    ) -> Result<Void, any Error> {
        do {
            let previousConfig = config
            if previousConfig.transcription.dictationHotkey
                != newConfig.transcription.dictationHotkey
            {
                try hotkeyRegistrationService.replace(
                    with:
                        newConfig.transcription
                            .dictationHotkey,
                    onPress: dictationHotkeyPressHandler()
                ) {
                    try configStore.save(newConfig)
                }
                hotkeyRegistrationIssue = nil
            } else {
                try configStore.save(newConfig)
            }
            config = newConfig
            overlay.updateVisualFeedbackConfiguration(
                newConfig.visualFeedback
            )
            applyActiveDictationHotkey(
                activeDictationHotkey
            )
            if previousConfig.transcription.dictationHotkey
                != newConfig.transcription.dictationHotkey
            {
                onboardingWindowController = nil
                historyWindowController = nil
            }
            refreshReadyState(detailOverride: successMessage, state: .ready)
            if previousConfig.privacy != newConfig.privacy {
                enforceStoragePolicies()
            }
            if previousConfig.auth != newConfig.auth
                || previousConfig.transcription.provider != newConfig.transcription.provider {
                prewarmAuthIfNeeded()
            }
            return .success(())
        } catch {
            overlay.showError(error.localizedDescription)
            notifier.notify(title: "OpenWhisper", body: error.localizedDescription)
            return .failure(error)
        }
    }

    private func openOnboarding(
        initialStep: OnboardingStep = .welcome
    ) {
        if onboardingWindowController == nil {
            let authManager = snapshotPrivacyMode.presentationAuthManager(
                liveAuthManager: self.authManager
            )
            onboardingWindowController = OnboardingWindowController(
                authManager: authManager,
                hotkeyBinding: activeDictationHotkey,
                initialStep: initialStep,
                persistCompletion: !snapshotPrivacyMode.isEnabled,
                onRequestMicrophoneAccess: { [weak self] in
                    guard let self else {
                        return .failure(
                            NSError(
                                domain: "OpenWhisper.Onboarding",
                                code: 1,
                                userInfo: [
                                    NSLocalizedDescriptionKey: L10n.text("OpenWhisper setup is no longer available."),
                                ]
                            )
                        )
                    }
                    if self.snapshotPrivacyMode.isEnabled {
                        return .success(())
                    }
                    do {
                        try await self.requestMicrophoneAccess(showExplanation: false)
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                },
                onStepCompleted: { [weak self] step in
                    self?.recordProductMetric(
                        event: .onboardingStepCompleted,
                        onboardingStep:
                            ProductMetricOnboardingStep(step)
                    )
                },
                onCompleted: { [weak self] in
                    self?.refreshReadyState()
                }
            )
        }
        onboardingWindowController?.show()
    }

    private func scheduleSettingsSnapshotIfRequested() {
        guard let outputURL = AppLaunchMode.settingsSnapshotOutputURL(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments
        ) else {
            return
        }

        if let size = AppLaunchMode.settingsSnapshotSize(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments
        ) {
            preferencesWindowController?.resizeForSnapshot(size)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else {
                return
            }
            do {
                guard let preferencesWindowController = self.preferencesWindowController else {
                    throw PreferencesSnapshotError.missingContentView
                }
                try preferencesWindowController.writeSnapshot(to: outputURL)
                NSApplication.shared.terminate(nil)
            } catch {
                print("OpenWhisper Settings self-capture failed: \(error.localizedDescription)")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            NSApplication.shared.terminate(nil)
        }
    }

    private func scheduleOnboardingSnapshotIfRequested() {
        guard let outputURL = AppLaunchMode.onboardingSnapshotOutputURL(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments
        ) else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else {
                return
            }
            do {
                guard let onboardingWindowController = self.onboardingWindowController else {
                    throw PreferencesSnapshotError.missingContentView
                }
                try onboardingWindowController.writeSnapshot(to: outputURL)
                NSApplication.shared.terminate(nil)
            } catch {
                print("OpenWhisper Onboarding self-capture failed: \(error.localizedDescription)")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            NSApplication.shared.terminate(nil)
        }
    }

    private func scheduleProductSurfaceSnapshotIfRequested(mode: AppLaunchMode) {
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        let writer: () throws -> Void

        switch mode {
        case .history:
            guard let outputURL = AppLaunchMode.historySnapshotOutputURL(
                environment: environment,
                arguments: arguments
            ) else {
                return
            }
            writer = { [weak self] in
                guard let controller = self?.historyWindowController else {
                    throw ProductSurfaceSnapshotError.missingContentView
                }
                try controller.writeSnapshot(to: outputURL)
            }
        case .terminology:
            guard let outputURL = AppLaunchMode.terminologySnapshotOutputURL(
                environment: environment,
                arguments: arguments
            ) else {
                return
            }
            writer = { [weak self] in
                guard let controller = self?.terminologyWindowController else {
                    throw ProductSurfaceSnapshotError.missingContentView
                }
                try controller.writeSnapshot(to: outputURL)
            }
        case .quickAdd:
            guard let outputURL = AppLaunchMode.quickAddSnapshotOutputURL(
                environment: environment,
                arguments: arguments
            ) else {
                return
            }
            writer = { [weak self] in
                guard let controller = self?.terminologyQuickAddWindowController else {
                    throw ProductSurfaceSnapshotError.missingContentView
                }
                try controller.writeSnapshot(to: outputURL)
            }
        default:
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            do {
                try writer()
                NSApplication.shared.terminate(nil)
            } catch {
                print("OpenWhisper product surface self-capture failed: \(error.localizedDescription)")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            NSApplication.shared.terminate(nil)
        }
    }

    private func scheduleAccessibilityAuditIfRequested(
        window: NSWindow?,
        surface: String
    ) {
        guard let outputURL = AppLaunchMode.accessibilityAuditOutputURL(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments
        ) else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            do {
                try AccessibilityAudit.write(
                    window: window,
                    surface: surface,
                    to: outputURL
                )
                NSApplication.shared.terminate(nil)
            } catch {
                print(
                    "OpenWhisper accessibility audit failed: \(error.localizedDescription)"
                )
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            NSApplication.shared.terminate(nil)
        }
    }

    private func retryRecoveryRecord(_ record: RecoveryRecord) {
        guard state == .idle else {
            NSSound.beep()
            return
        }

        let audioURL: URL
        do {
            audioURL = try recoveryRecorder.resolveAudioURL(for: record)
        } catch {
            overlay.showError(error.localizedDescription)
            return
        }

        let sessionID = UUID()
        activeSessionID = sessionID
        state = .processing
        let audio = RecordedAudio(fileURL: audioURL, durationMs: record.audioDurationMs)
        statusMenu?.update(state: .processing, detail: L10n.text("Retrying saved audio"))
        overlay.showProcessing()
        let launchAppContext = launchAppContextProvider()
        startProcessing(
            audio: audio,
            sessionID: sessionID,
            transcriptionConfig: config.transcription.resolvingVoiceMode(
                for: launchAppContext,
                voiceModesAllowed: licenseManager
                    .snapshot()
                    .allows(.voiceModes)
            ),
            injectionConfig: config.injection,
            launchAppContext: launchAppContext,
            attemptPolicy: .manualRetry,
            deleteAudioWhenFinished: false,
            automaticPasteAllowed: false,
            preparedSkillContext:
                PreparedSkillContext()
        )
    }

    private func openConfigFolder() {
        let directoryURL = configStore.directoryURL
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directoryURL)
    }

    func checkLaunchLoginState() {
        guard config.transcription.provider == .chatGPTManagedAuth else {
            return
        }

        let snapshot = authManager.authSnapshot()
        guard snapshot.state != .ready else {
            return
        }

        statusMenu?.update(state: .setupRequired, detail: snapshot.detail)
        notifier.notify(title: L10n.text("OpenWhisper setup required"), body: snapshot.detail)
    }

    private static func mergedTerminologyEntries(
        existing: [TerminologyEntry],
        incoming: [TerminologyEntry]
    ) -> [TerminologyEntry] {
        TerminologyLibrary.merge(existing: existing, incoming: incoming)
    }

    private func showInstallRequiredAlert(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("Install OpenWhisper to /Applications first")
        alert.informativeText = message
        alert.addButton(withTitle: L10n.text("OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func checkForUpdates() {
        switch softwareUpdater.checkForUpdates() {
        case .success:
            break
        case .failure(let error):
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = L10n.text("Software Update")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: L10n.text("OK"))
            alert.runModal()
        }
    }

    private func requestMicrophoneAccess(showExplanation: Bool = true) async throws {
        guard let recorder else {
            throw RecorderError.noActiveRecording
        }
        let status = recorder.recordingPermissionState()
        let app = NSApplication.shared
        let previousActivationPolicy = app.activationPolicy()

        logger.info(
            "Preparing microphone request with status=\(String(describing: status), privacy: .public) activationPolicy=\(String(describing: previousActivationPolicy), privacy: .public)"
        )

        if status == .undetermined {
            if previousActivationPolicy != .regular {
                logger.info("Temporarily switching activation policy to regular for first-run microphone prompt")
                _ = app.setActivationPolicy(.regular)
            }

            if showExplanation {
                let controller = microphonePermissionWindowController ?? MicrophonePermissionWindowController()
                microphonePermissionWindowController = controller
                logger.info("Presenting first-run microphone permission window")
                let shouldContinue = await controller.present()
                logger.info("First-run microphone permission window returned shouldContinue=\(shouldContinue, privacy: .public)")
                guard shouldContinue else {
                    if previousActivationPolicy != .regular {
                        _ = app.setActivationPolicy(previousActivationPolicy)
                    }
                    logger.error("User cancelled first-run microphone permission window")
                    throw RecorderError.microphoneDenied
                }
            }
        }

        defer {
            if previousActivationPolicy != .regular {
                logger.info("Restoring activation policy to \(String(describing: previousActivationPolicy), privacy: .public)")
                _ = app.setActivationPolicy(previousActivationPolicy)
            }
        }

        logger.info("Calling microphone access request helper")
        try await recorder.ensureRecordingPermission()
    }

    private func runPreviewDemo() {
        let request = PreviewRequest(
            skillID:
                SkillRegistry
                    .contextRewriteSkillID,
            skillVersion: "1.0.0",
            skillName: L10n.text(
                "Context Rewrite"
            ),
            originalTranscript:
                L10n.text(
                    "Keep the same tone, shorten it, and preserve the release date and API version."
                ),
            resultText:
                """
                Ship the macOS release on July 14, 2026.

                Preserve API v2 compatibility and keep the existing security review gate.
                """,
            selectedText:
                """
                We are planning to ship the macOS release on July 14, 2026. Please make sure API v2 remains compatible, and do not remove the existing security review gate.
                """,
            contextCapabilities: [
                .selection,
            ],
            validationPassed: true,
            allowsSelectionReplacement:
                true
        )
        previewDemoTask?.cancel()
        previewDemoTask =
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                _ = await self.previewPresenter
                    .present(request)
            }

        guard
            let outputURL =
                AppLaunchMode
                    .previewSnapshotOutputURL(
                        environment:
                            ProcessInfo
                                .processInfo
                                .environment,
                        arguments:
                            ProcessInfo
                                .processInfo
                                .arguments
                    )
        else {
            return
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1
        ) { [weak self] in
            do {
                guard
                    let snapshotter =
                        self?
                            .previewPresenter
                            as? any PreviewSnapshotCapturing
                else {
                    throw ProductSurfaceSnapshotError
                        .missingContentView
                }
                try snapshotter
                    .writePreviewSnapshot(
                        to: outputURL
                    )
                NSApplication.shared
                    .terminate(nil)
            } catch {
                print(
                    "OpenWhisper Preview self-capture failed: "
                        + error.localizedDescription
                )
            }
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 10
        ) {
            NSApplication.shared
                .terminate(nil)
        }
    }

    private func runOverlayDemo() {
        let demoLevels: [CGFloat] = [0.14, 0.28, 0.46, 0.72, 0.54, 0.32, 0.18, 0.64]

        state = .processing
        statusMenu?.update(state: .demo, detail: L10n.text("Overlay demo"))
        overlay.showRecording(elapsedText: "00:00")
        overlayDemoFrameIndex = 0

        recordingLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let level = demoLevels[self.overlayDemoFrameIndex % demoLevels.count]
                self.overlayDemoFrameIndex += 1
                self.overlay.updateRecording(level: level, elapsedText: self.demoElapsedText())
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: 1_400_000_000)
            self.stopRecordingLevelUpdates()
            self.overlay.showProcessing()

            try? await Task.sleep(nanoseconds: 1_300_000_000)
            self.overlay.showResult(
                text: L10n.text("Demo"),
                outcome: .insertedAndVerified
            )

            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.overlay.showResult(
                text: L10n.text("Demo"),
                outcome: .pasteDispatchedClipboardRetained
            )

            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.overlay.showResult(
                text: L10n.text("Demo"),
                outcome: .copiedToClipboard(reason: .noEditableTarget)
            )

            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.overlay.showError(L10n.text("Clipboard only"))

            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.overlay.showRetryableError(L10n.text("403 after 3 tries"))

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            NSApplication.shared.terminate(nil)
        }
    }

    private func runOverlayDemoState(_ demoState: OverlayDemoState) {
        state = .processing
        statusMenu?.update(state: .demo, detail: L10n.text("Overlay demo"))

        switch demoState {
        case .recording:
            overlay.showRecording(elapsedText: "00:07")
            overlay.updateRecording(level: 0.72, elapsedText: "00:07")
        case .processing:
            overlay.showProcessing()
        case .result:
            overlay.showResult(
                text: L10n.text("Demo"),
                outcome: .insertedAndVerified
            )
        case .pasteSent:
            overlay.showResult(
                text: L10n.text("Demo"),
                outcome: .pasteDispatchedClipboardRetained
            )
        case .copied:
            overlay.showResult(
                text: L10n.text("Demo"),
                outcome: .copiedToClipboard(reason: .noEditableTarget)
            )
        case .error:
            overlay.showError(L10n.text("Clipboard only"))
        case .retryableError:
            overlay.showRetryableError(L10n.text("403 after 3 tries"))
        }

        let snapshotOutputURL = Self.visualAcceptanceSnapshotOutputURL()
        let followupSnapshotOutputURL =
            Self.visualAcceptanceFollowupSnapshotOutputURL()
        let feedbackDebugOutputURL =
            Self.feedbackSurfaceDebugOutputURL()
        if let feedbackDebugOutputURL {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.25
            ) { [overlay] in
                do {
                    guard
                        let feedback =
                            overlay
                                as? FeedbackSurfaceController
                    else {
                        throw OverlaySnapshotError
                            .bitmapUnavailable
                    }
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [
                        .prettyPrinted,
                        .sortedKeys,
                    ]
                    try encoder.encode(
                        feedback.debugSnapshot
                    ).write(
                        to: feedbackDebugOutputURL,
                        options: [.atomic]
                    )
                    if snapshotOutputURL == nil
                        && followupSnapshotOutputURL
                            == nil
                    {
                        NSApplication.shared
                            .terminate(nil)
                    }
                } catch {
                    print(
                        "OpenWhisper feedback debug capture failed: "
                            + error.localizedDescription
                    )
                }
            }
        }
        if let snapshotOutputURL {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [overlay] in
                do {
                    guard let snapshotter = overlay as? any OverlaySnapshotCapturing else {
                        throw OverlaySnapshotError.bitmapUnavailable
                    }
                    try snapshotter.writeSnapshot(to: snapshotOutputURL)
                    if followupSnapshotOutputURL == nil {
                        NSApplication.shared.terminate(nil)
                        return
                    }
                } catch {
                    print("OpenWhisper HUD self-capture failed: \(error.localizedDescription)")
                }
            }
        }
        if let followupSnapshotOutputURL {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [overlay] in
                do {
                    guard let snapshotter = overlay as? any OverlaySnapshotCapturing else {
                        throw OverlaySnapshotError.bitmapUnavailable
                    }
                    try snapshotter.writeSnapshot(to: followupSnapshotOutputURL)
                    NSApplication.shared.terminate(nil)
                    return
                } catch {
                    print(
                        "OpenWhisper HUD follow-up self-capture failed: "
                            + error.localizedDescription
                    )
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            NSApplication.shared.terminate(nil)
        }
    }

    private func runPasteAcceptance() {
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let outputURL = AppLaunchMode.pasteAcceptanceOutputURL(
                environment: environment,
                arguments: arguments
            ),
            let target = AppLaunchMode.pasteAcceptanceTarget(
                environment: environment,
                arguments: arguments
            )
        else {
            print(
                "Paste acceptance failed: missing output or invalid target"
            )
            NSApplication.shared.terminate(nil)
            return
        }

        Task { @MainActor [injector] in
            await PasteAcceptanceRunner.run(
                injector: injector,
                target: target,
                outputURL: outputURL
            )
            NSApplication.shared.terminate(nil)
        }
    }

    private static func visualAcceptanceSnapshotOutputURL() -> URL? {
        AppLaunchMode.visualAcceptanceOutputURL(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments
        )
    }

    private static func visualAcceptanceFollowupSnapshotOutputURL() -> URL? {
        AppLaunchMode.visualAcceptanceFollowupOutputURL(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments
        )
    }

    private static func feedbackSurfaceDebugOutputURL()
        -> URL?
    {
        AppLaunchMode
            .feedbackSurfaceDebugOutputURL(
                environment:
                    ProcessInfo.processInfo
                        .environment,
                arguments:
                    ProcessInfo.processInfo
                        .arguments
            )
    }

    private func startRecordingLevelUpdates() {
        stopRecordingLevelUpdates()
        overlay.showRecording(elapsedText: elapsedRecordingText())

        recordingLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let level = self.recorder?.currentLevel() else {
                    return
                }
                self.overlay.updateRecording(level: level, elapsedText: self.elapsedRecordingText())
            }
        }
    }

    private func stopRecordingLevelUpdates() {
        recordingLevelTimer?.invalidate()
        recordingLevelTimer = nil
    }

    private func elapsedRecordingText() -> String {
        guard let recordingStartedAt else {
            return "00:00"
        }
        let elapsedSeconds = Int((DispatchTime.now().uptimeNanoseconds - recordingStartedAt.uptimeNanoseconds) / 1_000_000_000)
        return Self.formatElapsed(seconds: elapsedSeconds)
    }

    private func demoElapsedText() -> String {
        Self.formatElapsed(seconds: overlayDemoFrameIndex / 12)
    }

    private static func formatElapsed(seconds: Int) -> String {
        let boundedSeconds = max(0, seconds)
        return String(format: "%02d:%02d", boundedSeconds / 60, boundedSeconds % 60)
    }

    private func statusDetail(for outcome: InjectionOutcome) -> String {
        switch outcome {
        case .insertedAndVerified:
            return L10n.text("Transcript insertion verified")
        case .pasteDispatchedClipboardRetained:
            return L10n.text("Paste sent. Transcript kept in clipboard.")
        case .copiedToClipboard(let reason):
            return reason.statusDetail
        }
    }

    private func prewarmAuthIfNeeded() {
        guard config.transcription.provider == .chatGPTManagedAuth else {
            return
        }

        let authManager = self.authManager
        Task.detached(priority: .utility) {
            await authManager.prewarmSession()
        }
    }

    private func storePendingRetry(
        audio: RecordedAudio,
        launchAppContext: LaunchAppContext?,
        transcriptionConfig: TranscriptionConfig,
        injectionConfig: InjectionConfig
    ) throws {
        var retryTranscriptionConfig =
            transcriptionConfig
        retryTranscriptionConfig
            .skillPromptContext =
            SkillPromptContext()
        let expiration = Date().addingTimeInterval(
            TimeInterval(max(1, config.privacy.failedAudioRetentionHours)) * 60 * 60
        )
        if pendingRetry?.audio.fileURL == audio.fileURL {
            let retry = PendingRetry(
                id: UUID(),
                audio: audio,
                launchAppContext: launchAppContext,
                transcriptionConfig:
                    retryTranscriptionConfig,
                injectionConfig: injectionConfig,
                expiresAt: expiration
            )
            pendingRetry = retry
            statusMenu?.setRetryDictationAvailable(
                true
            )
            schedulePendingRetryExpiry(for: retry)
            return
        }

        clearPendingRetry()
        let retryDirectory = configStore.directoryURL.appendingPathComponent("Retry", isDirectory: true)
        try FileManager.default.createDirectory(at: retryDirectory, withIntermediateDirectories: true)
        let retryURL = retryDirectory.appendingPathComponent("retry-\(UUID().uuidString).wav")
        try FileManager.default.copyItem(at: audio.fileURL, to: retryURL)
        let retry = PendingRetry(
            id: UUID(),
            audio: RecordedAudio(fileURL: retryURL, durationMs: audio.durationMs),
            launchAppContext: launchAppContext,
            transcriptionConfig:
                retryTranscriptionConfig,
            injectionConfig: injectionConfig,
            expiresAt: expiration
        )
        pendingRetry = retry
        statusMenu?.setRetryDictationAvailable(true)
        schedulePendingRetryExpiry(for: retry)
    }

    private func clearPendingRetry() {
        pendingRetryExpiryTask?.cancel()
        pendingRetryExpiryTask = nil
        if let pendingRetry {
            try? FileManager.default.removeItem(at: pendingRetry.audio.fileURL)
        }
        pendingRetry = nil
        statusMenu?.setRetryDictationAvailable(false)
    }

    private func schedulePendingRetryExpiry(for retry: PendingRetry) {
        pendingRetryExpiryTask?.cancel()
        let delay = max(0, retry.expiresAt.timeIntervalSinceNow)
        pendingRetryExpiryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self, self.pendingRetry?.id == retry.id else {
                return
            }
            self.clearPendingRetry()
            self.logger.info("Expired pending retry audio was deleted")
        }
    }

    private func isRetryableTranscriptionError(_ error: Error) -> Bool {
        if case TranscriptionError.retryableCloudflareChallenge = error {
            return true
        }
        if let failure = error as? ProviderRequestFailure {
            return failure.isRetryableByUser
        }
        return false
    }

    private func recordTranscriptionFailure(
        audio: RecordedAudio,
        transcriptionConfig: TranscriptionConfig,
        processingStarted: UInt64,
        error: Error
    ) {
        guard config.privacy.diagnosticsEnabled else {
            return
        }
        let sample = LatencySample(
            timestamp: Date(),
            audioDurationMs: audio.durationMs,
            audioBytes: Self.audioFileSize(at: audio.fileURL),
            provider: transcriptionConfig.provider.rawValue,
            authMs: 0,
            transcribeMs: 0,
            normalizationMs: 0,
            polishMs: 0,
            textPolishDecisionReason: nil,
            skillID:
                transcriptionConfig
                    .resolvedSkillPlan?
                    .skill.id
                ?? transcriptionConfig
                    .skills.defaultSkillID,
            skillVersion:
                transcriptionConfig
                    .resolvedSkillPlan?
                    .skill.version,
            contextCapabilityCodes:
                transcriptionConfig
                    .skillPromptContext
                    .selection == nil
                    ? []
                    : [
                        SkillCapability
                            .selection
                            .rawValue,
                    ],
            selectionCharacterCount:
                transcriptionConfig
                    .skillPromptContext
                    .selection?
                    .count ?? 0,
            estimatedPolishInputTokens: 0,
            estimatedPolishOutputTokens: 0,
            injectMs: 0,
            totalProcessingMs: elapsedMilliseconds(since: processingStarted),
            resultStatus: "error",
            errorCategory: latencyFailureCategory(for: error)
        )
        try? latencyRecorder.record(
            sample,
            retention: config.privacy.diagnosticsRetentionPolicy()
        )
    }

    private func latencyFailureCategory(for error: Error) -> String {
        if case TranscriptionError.retryableCloudflareChallenge = error {
            return "transcribe.challenge"
        }
        guard let failure = error as? ProviderRequestFailure else {
            return "transcribe"
        }
        return "transcribe.\(failure.category.rawValue)"
    }

    private func productMetricFailureCategory(
        for error: Error
    ) -> ProductMetricFailureCategory {
        if case TranscriptionError.retryableCloudflareChallenge = error {
            return .transcriptionChallenge
        }
        guard let failure = error as? ProviderRequestFailure else {
            return .transcription
        }
        switch failure.category {
        case .authentication:
            return .transcriptionAuthentication
        case .challenge:
            return .transcriptionChallenge
        case .rateLimited:
            return .transcriptionRateLimited
        case .contractChanged:
            return .transcriptionContractChanged
        case .serviceUnavailable:
            return .transcriptionServiceUnavailable
        case .network:
            return .transcriptionNetwork
        case .invalidResponse:
            return .transcriptionInvalidResponse
        case .requestRejected, .unknown:
            return .transcription
        }
    }

    private func recordLatency(
        prepared: PreparedDictation,
        outcome: InjectionOutcome?,
        injectMs: Int,
        totalProcessingMs: Int,
        errorCategory: String?
    ) {
        guard config.privacy.diagnosticsEnabled else {
            return
        }
        let sample = LatencySample(
            timestamp: Date(),
            audioDurationMs: prepared.metrics.transcription.audioDurationMs,
            audioBytes: prepared.metrics.transcription.audioBytes,
            provider: prepared.metrics.transcription.provider.rawValue,
            textPolishProvider: prepared.metrics.textPolishProvider?.rawValue,
            authMs: prepared.metrics.transcription.authMs,
            transcribeMs: prepared.metrics.transcription.transcribeMs,
            normalizationMs: prepared.metrics.normalizationMs,
            polishMs: prepared.metrics.polishMs,
            textPolishAttempted: prepared.metrics.textPolishAttempted,
            textPolishDecisionReason:
                prepared.metrics.textPolishDecisionReason?.rawValue,
            textPolishError: prepared.metrics.textPolishErrorMessage,
            skillID:
                prepared.metrics.skillID,
            skillVersion:
                prepared.metrics.skillVersion,
            skillValidationIssueCodes:
                prepared.metrics
                    .skillValidationIssueCodes,
            contextCapabilityCodes:
                prepared.metrics
                    .contextCapabilityCodes,
            selectionCharacterCount:
                prepared.metrics
                    .selectionCharacterCount,
            estimatedPolishInputTokens: prepared.metrics.estimatedPolishInputTokens,
            estimatedPolishOutputTokens: prepared.metrics.estimatedPolishOutputTokens,
            injectMs: injectMs,
            totalProcessingMs: totalProcessingMs,
            resultStatus: latencyResultStatus(for: outcome),
            errorCategory: errorCategory
        )
        try? latencyRecorder.record(
            sample,
            retention: config.privacy.diagnosticsRetentionPolicy()
        )
    }

    private func recordProductMetric(
        event: ProductMetricEvent,
        onboardingStep: ProductMetricOnboardingStep? = nil,
        provider: TranscriptionProvider? = nil,
        audioDurationMs: Int? = nil,
        totalProcessingMs: Int? = nil,
        deliveryStatus: ProductMetricDeliveryStatus? = nil,
        failureCategory: ProductMetricFailureCategory? = nil
    ) {
        guard config.privacy.productMetricsEnabled else {
            return
        }
        try? productMetricsRecorder.record(
            ProductMetricSample(
                event: event,
                onboardingStep: onboardingStep,
                provider: provider,
                audioDurationMs: audioDurationMs,
                totalProcessingMs: totalProcessingMs,
                deliveryStatus: deliveryStatus,
                failureCategory: failureCategory
            ),
            retention: config.privacy.productMetricsRetentionPolicy()
        )
    }

    private func recordHistory(
        prepared: PreparedDictation,
        outcome: InjectionOutcome,
        launchAppContext: LaunchAppContext?
    ) {
        guard config.privacy.historyEnabled else {
            return
        }
        guard SensitiveAppPolicy.permitsPersistence(
            bundleIdentifier: launchAppContext?.bundleIdentifier,
            privacy: config.privacy
        ) else {
            logger.info("Skipped transcript history for a sensitive target application")
            return
        }

        try? historyRecorder.record(
            TranscriptionHistoryRecord(
                timestamp: Date(),
                rawText: config.privacy.storeRawTranscripts ? prepared.rawText : nil,
                finalText: prepared.finalText,
                appName: launchAppContext?.localizedName,
                appBundleIdentifier: launchAppContext?.bundleIdentifier,
                outcome: latencyResultStatus(for: outcome),
                textPolishProvider: prepared.metrics.textPolishProvider?.rawValue,
                skillID:
                    prepared.metrics.skillID,
                skillVersion:
                    prepared.metrics
                        .skillVersion
            ),
            retention: config.privacy.historyRetentionPolicy()
        )
    }

    private func recordRecoveryFailure(
        audio: RecordedAudio,
        launchAppContext: LaunchAppContext?,
        error: any Error
    ) {
        guard config.privacy.failedAudioRecoveryEnabled else {
            return
        }
        guard SensitiveAppPolicy.permitsPersistence(
            bundleIdentifier: launchAppContext?.bundleIdentifier,
            privacy: config.privacy
        ) else {
            logger.info("Skipped failed-audio recovery for a sensitive target application")
            return
        }

        try? recoveryRecorder.record(
            RecoveryRecordInput(
                timestamp: Date(),
                sourceAudioURL: audio.fileURL,
                durationMs: audio.durationMs,
                asrText: nil,
                polishText: nil,
                appName: launchAppContext?.localizedName,
                appBundleIdentifier: launchAppContext?.bundleIdentifier,
                outcome: "error",
                errorMessage: error.localizedDescription
            ),
            retention: config.privacy.recoveryRetentionPolicy()
        )
    }

    private func enforceStoragePolicies() {
        do {
            let cleanup = StorageCleanupService(applicationSupportURL: configStore.directoryURL)
            try cleanup.clearRetryOrphans()
            try historyRecorder.prune(retention: config.privacy.historyRetentionPolicy())
            try recoveryRecorder.prune(retention: config.privacy.recoveryRetentionPolicy())
            try latencyRecorder.prune(retention: config.privacy.diagnosticsRetentionPolicy())
            try productMetricsRecorder.prune(
                retention: config.privacy
                    .productMetricsRetentionPolicy()
            )
        } catch {
            logger.error("Storage retention cleanup failed: \(error.localizedDescription, privacy: .public)")
        }
        let temporaryCleanup = TemporaryArtifactCleanupService().cleanupOrphans()
        if !temporaryCleanup.failedFileNames.isEmpty {
            logger.error(
                "Temporary artifact cleanup failed for \(temporaryCleanup.failedFileNames.count, privacy: .public) item(s)"
            )
        }
    }

    func deleteAllUserData() -> Result<AppConfig, any Error> {
        if state != .idle || activeSessionID != nil || processingTask != nil || startRecordingTask != nil {
            cancelCurrentSession()
        } else {
            clearPendingRetry()
        }

        var firstError: (any Error)?
        do {
            try authManager.signOut()
        } catch {
            firstError = error
        }

        do {
            try recoveryCredentialStore.deleteAPIKey()
        } catch {
            if firstError == nil {
                firstError = error
            }
        }

        do {
            try licenseManager.reset()
        } catch {
            if firstError == nil {
                firstError = error
            }
        }

        do {
            try StorageCleanupService(applicationSupportURL: configStore.directoryURL).deleteAllData()
        } catch {
            if firstError == nil {
                firstError = error
            }
        }

        let freshConfig = AppConfig()
        do {
            try hotkeyRegistrationService.replace(
                with:
                    freshConfig.transcription
                        .dictationHotkey,
                onPress: dictationHotkeyPressHandler()
            ) {
                try configStore.save(freshConfig)
            }
            config = freshConfig
            hotkeyRegistrationIssue = nil
            overlay.updateVisualFeedbackConfiguration(
                freshConfig.visualFeedback
            )
            applyActiveDictationHotkey(
                freshConfig.transcription
                    .dictationHotkey
            )
            recorder?.configure(maxDurationSeconds: freshConfig.transcription.maxDurationSeconds)
            refreshReadyState(
                detailOverride: L10n.text("All OpenWhisper data was deleted. Connect ChatGPT again to continue."),
                state: .setupRequired
            )
        } catch {
            if firstError == nil {
                firstError = error
            }
        }

        if let firstError {
            return .failure(firstError)
        }
        return .success(freshConfig)
    }

    private func latencyResultStatus(for outcome: InjectionOutcome?) -> String {
        guard let outcome else {
            return TextDeliveryStatus.error
        }
        return outcome.resultStatus
    }

    private func elapsedMilliseconds(since start: UInt64) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }

    private nonisolated static func audioFileSize(at url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    private func shouldContinue(sessionID: UUID) -> Bool {
        activeSessionID == sessionID
    }

    private func refreshReadyState(detailOverride: String? = nil, state: StatusMenuVisualState = .ready) {
        let issues = RuntimePreflight.issues(
            for: config,
            authSnapshotProvider: { self.authManager.authSnapshot() },
            recoveryCredentialAvailable: {
                try self.recoveryCredentialStore.hasAPIKey()
            }
        )
        if let detailOverride {
            statusMenu?.update(state: state, detail: detailOverride)
        } else if let hotkeyRegistrationIssue {
            statusMenu?.update(
                state: .setupRequired,
                detail: hotkeyRegistrationIssue
            )
        } else if let summary = RuntimePreflight.summary(for: issues) {
            statusMenu?.update(state: .setupRequired, detail: summary)
        } else {
            statusMenu?.update(
                state: state,
                detail: L10n.format(
                    "Ready. Press %@ to dictate",
                    activeDictationHotkey.displayName
                )
            )
        }
    }
}
