import AppKit
import AVFoundation
import Foundation
import OSLog

struct TranscriptionAttemptPolicy: Sendable, Equatable {
    let cloudflareChallengeMaxAttempts: Int

    static let automatic = TranscriptionAttemptPolicy(cloudflareChallengeMaxAttempts: 3)
    static let manualRetry = TranscriptionAttemptPolicy(cloudflareChallengeMaxAttempts: 1)
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
    let historyRecorder: any TranscriptionHistoryRecording
    let recoveryRecorder: any RecoveryRecording
    let soundFeedback: any SoundFeedbackPlaying
    let softwareUpdater: any SoftwareUpdating
    let providerCapabilityPolicy: any ProviderCapabilityChecking
    let recoveryCredentialStore: any OpenAICompatibleCredentialPersisting
    let recorderFactory: RecorderFactory
    let statusMenuFactory: StatusMenuFactory
    let pipelineFactory: PipelineFactory
    let launchAppContextProvider: LaunchAppContextProvider
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? ProductIdentity.defaultBundleIdentifier,
        category: "AppCoordinator"
    )

    var config: AppConfig
    private var hotkeyMonitor: HotkeyMonitor?
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
    private var pendingRetry: PendingRetry?
    private var pendingRetryExpiryTask: Task<Void, Never>?
    private var authStateObserver: NSObjectProtocol?
    private var activeProcessingAudio: ActiveProcessingAudio?

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
        historyRecorder: (any TranscriptionHistoryRecording)? = nil,
        recoveryRecorder: (any RecoveryRecording)? = nil,
        soundFeedback: any SoundFeedbackPlaying = SoundFeedbackService(),
        recoveryCredentialStore: any OpenAICompatibleCredentialPersisting =
            KeychainOpenAICompatibleCredentialStore(),
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
        pipelineFactory: @escaping PipelineFactory = {
            transcriptionConfig,
            authManager,
            attemptPolicy,
            providerCapabilityPolicy,
            recoveryCredentialStore in
            DictationPipeline(
                transcriber: ChatGPTTranscriber(
                    authManager: authManager,
                    config: transcriptionConfig,
                    providerCapabilityPolicy: providerCapabilityPolicy,
                    recoveryCredentialStore: recoveryCredentialStore,
                    cloudflareChallengeMaxAttempts: attemptPolicy.cloudflareChallengeMaxAttempts
                ),
                normalizer: TerminologyNormalizer(
                    languagePreference: transcriptionConfig.languagePreference,
                    punctuationPreference: transcriptionConfig.punctuationPreference
                ),
                importedEntries: transcriptionConfig.activeDictionaryEntries,
                hintTerms: transcriptionConfig.hintTerms,
                textPolisher: OpenAICompatibleTextPolisher(
                    config: transcriptionConfig.textPolish,
                    chatGPTAuthProvider: authManager,
                    chatGPTAuthAvailable: authManager.authSnapshot().state == .ready,
                    providerCapabilityPolicy: providerCapabilityPolicy
                )
            )
        },
        launchAppContextProvider: @escaping LaunchAppContextProvider = { LaunchAppContext.current() }
    ) {
        self.configStore = configStore
        self.config = config
        self.notifier = notifier
        self.injector = injector
        let resolvedOverlay = overlay ?? OverlayController()
        self.overlay = resolvedOverlay
        self.authManager = authManager
        self.latencyRecorder = latencyRecorder ?? LatencyRecorder(directoryURL: configStore.directoryURL)
        self.historyRecorder = historyRecorder ?? TranscriptionHistoryRecorder(directoryURL: configStore.directoryURL)
        self.recoveryRecorder = recoveryRecorder ?? RecoveryStore(
            directoryURL: configStore.directoryURL.appendingPathComponent("Recovery", isDirectory: true)
        )
        self.soundFeedback = soundFeedback
        self.softwareUpdater = softwareUpdater ?? SparkleSoftwareUpdater()
        self.providerCapabilityPolicy = providerCapabilityPolicy
        self.recoveryCredentialStore = recoveryCredentialStore
        self.recorderFactory = recorderFactory
        self.statusMenuFactory = statusMenuFactory
        self.pipelineFactory = pipelineFactory
        self.launchAppContextProvider = launchAppContextProvider
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
                config = try configStore.load()
                enforceStoragePolicies()
                Task { [providerCapabilityPolicy] in
                    _ = await providerCapabilityPolicy.refresh(force: false)
                }
                recorder = recorderFactory(config.transcription.sampleRateHz)
                recorder?.configure(maxDurationSeconds: config.transcription.maxDurationSeconds)
                refreshReadyState()
                checkLaunchLoginState()
                prewarmAuthIfNeeded()

                hotkeyMonitor = try HotkeyMonitor(keyCode: config.transcription.hotkeyKeyCode) { [weak self] in
                    Task { @MainActor in
                        self?.handleHotkeyPress()
                    }
                }
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
                        nil
                    }
                    openSettings(focusPane: focusedPane)
                    scheduleSettingsSnapshotIfRequested()
                }
                if launchMode == .accessibilityGuide {
                    DispatchQueue.main.async {
                        AccessibilityPermission.guideAccess()
                    }
                }
                if launchMode == .onboarding {
                    openOnboarding()
                    scheduleOnboardingSnapshotIfRequested()
                }
                if launchMode == .history {
                    openHistory()
                    scheduleProductSurfaceSnapshotIfRequested(mode: .history)
                }
                if launchMode == .terminology {
                    openTerminology()
                    scheduleProductSurfaceSnapshotIfRequested(mode: .terminology)
                }
                if launchMode == .quickAdd {
                    openQuickAdd()
                    scheduleProductSurfaceSnapshotIfRequested(mode: .quickAdd)
                }
                if launchMode == .normal, OnboardingStateStore().shouldPresent() {
                    DispatchQueue.main.async { [weak self] in
                        self?.openOnboarding()
                    }
                }
            case .overlayDemo:
                config = (try? configStore.load()) ?? config
                runOverlayDemo()
                return
            case .overlayDemoState(let demoState):
                config = (try? configStore.load()) ?? config
                runOverlayDemoState(demoState)
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

    func handleHotkeyPress() {
        logger.info("F5 received while state=\(String(describing: self.state), privacy: .public)")
        switch state {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .processing:
            NSSound.beep()
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

        startRecordingTask?.cancel()
        startRecordingTask = nil
        processingTask?.cancel()
        processingTask = nil
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
        launchAppContext = nil
        overlay.hide()
        refreshReadyState()
        logger.info("Cancellation completed; state returned to idle")
    }

    func shutdown() {
        startRecordingTask?.cancel()
        startRecordingTask = nil
        processingTask?.cancel()
        processingTask = nil
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
                    self.statusMenu?.update(state: .setupRequired, detail: message)
                    self.overlay.showError(message)
                    self.notifier.notify(title: L10n.text("OpenWhisper setup required"), body: message)
                    self.openSettings()
                    return
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
                self.statusMenu?.update(state: .recording, detail: L10n.text("Recording on F5"))
                self.overlay.showRecording(elapsedText: "00:00")
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
                self.refreshReadyState(detailOverride: error.localizedDescription, state: .error)
                self.overlay.showError(error.localizedDescription)
                self.notifier.notify(title: "OpenWhisper", body: error.localizedDescription)
                self.launchAppContext = nil
            }

            if self.activeSessionID == sessionID {
                self.startRecordingTask = nil
            }
        }
    }

    private func stopRecording() {
        guard let recorder, let sessionID = activeSessionID else {
            logger.error("F5 stop request ignored because no active recorder/session was available")
            return
        }

        do {
            logger.info("Stopping recording session \(sessionID.uuidString, privacy: .public) from F5")
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

            let transcriptionConfig = config.transcription
            let injectionConfig = config.injection
            let launchAppContext = self.launchAppContext
            startProcessing(
                audio: audio,
                sessionID: sessionID,
                transcriptionConfig: transcriptionConfig,
                injectionConfig: injectionConfig,
                launchAppContext: launchAppContext,
                attemptPolicy: .automatic,
                deleteAudioWhenFinished: true,
                automaticPasteAllowed: true
            )
        } catch {
            logger.error("Stopping recording failed: \(error.localizedDescription, privacy: .public)")
            stopRecordingLevelUpdates()
            state = .idle
            activeSessionID = nil
            recordingStartedAt = nil
            statusMenu?.update(state: .error, detail: error.localizedDescription)
            overlay.showError(error.localizedDescription)
            notifier.notify(title: "OpenWhisper", body: error.localizedDescription)
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
        statusMenu?.update(state: .processing, detail: L10n.text("Retrying"))
        overlay.showProcessing()

        startProcessing(
            audio: pendingRetry.audio,
            sessionID: sessionID,
            transcriptionConfig: pendingRetry.transcriptionConfig,
            injectionConfig: pendingRetry.injectionConfig,
            launchAppContext: pendingRetry.launchAppContext,
            attemptPolicy: .manualRetry,
            deleteAudioWhenFinished: false,
            automaticPasteAllowed: false
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
        automaticPasteAllowed: Bool
    ) {
        let processingStarted = DispatchTime.now().uptimeNanoseconds
        let initialAudioBytes = Self.audioFileSize(at: audio.fileURL)
        logger.info(
            "Processing started session=\(sessionID.uuidString, privacy: .public) provider=\(transcriptionConfig.provider.rawValue, privacy: .public) durationMs=\(audio.durationMs, privacy: .public) audioBytes=\(initialAudioBytes, privacy: .public) cloudflareAttempts=\(attemptPolicy.cloudflareChallengeMaxAttempts, privacy: .public)"
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
                    "Dictation pipeline completed transcriptCharacters=\(prepared.rawText.count, privacy: .public) finalCharacters=\(prepared.finalText.count, privacy: .public) authMs=\(prepared.metrics.transcription.authMs, privacy: .public) transcribeMs=\(prepared.metrics.transcription.transcribeMs, privacy: .public)"
                )

                let canInject = await MainActor.run {
                    self.shouldContinue(sessionID: sessionID)
                }
                guard canInject else { return }

                let injectStarted = DispatchTime.now().uptimeNanoseconds
                let outcome: InjectionOutcome
                do {
                    outcome = try await self.injector.inject(
                        text: prepared.finalText,
                        preserveClipboard: injectionConfig.preserveClipboard,
                        restoreDelayMilliseconds: injectionConfig.restoreDelayMilliseconds,
                        launchAppContext: launchAppContext,
                        automaticPasteAllowed: automaticPasteAllowed
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
                    self.clearPendingRetry()
                    self.state = .idle
                    self.activeSessionID = nil
                    self.statusMenu?.update(
                        state: .ready,
                        detail: self.statusDetail(for: outcome)
                    )
                    self.overlay.showResult(text: prepared.finalText, outcome: outcome)
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

                    self.recordTranscriptionFailure(
                        audio: audio,
                        transcriptionConfig: transcriptionConfig,
                        processingStarted: processingStarted
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
            let authManager: ChatGPTAuthManager
            if let concrete = self.authManager as? ChatGPTAuthManager {
                authManager = concrete
            } else {
                authManager = ChatGPTAuthManager()
            }
            preferencesWindowController = PreferencesWindowController(
                config: config,
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
                    return (try? self.historyRecorder.loadRecent(limit: 200)) ?? []
                },
                onLoadRecoveryHistory: { [weak self] in
                    guard let self else {
                        return []
                    }
                    return (try? self.recoveryRecorder.loadRecent(limit: 10)) ?? []
                },
                onResolveRecoveryAudioURL: { [weak self] record in
                    guard let self else {
                        return .failure(RecoveryAudioError.missing)
                    }
                    return Result {
                        try self.recoveryRecorder.resolveAudioURL(for: record)
                    }
                },
                onRetryRecoveryRecord: { [weak self] record in
                    self?.retryRecoveryRecord(record)
                },
                onRequestMicrophoneAccess: { [weak self] in
                    self?.requestMicrophoneAccessFromSettings()
                },
                onOpenConfigFolder: { [weak self] in
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
                providerCapabilityPolicy: providerCapabilityPolicy,
                recoveryCredentialStore: recoveryCredentialStore,
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
                    return self.deleteAllUserData()
                },
                onOpenOnboarding: { [weak self] in
                    self?.openOnboarding()
                },
                focusPane: focusPane
            )
        }

        preferencesWindowController?.show()
    }

    private func openHistory() {
        if historyWindowController == nil {
            historyWindowController = HistoryWindowController(
                onLoadTranscriptionHistory: { [weak self] in
                    guard let self else {
                        return []
                    }
                    return (try? self.historyRecorder.loadRecent(limit: 500)) ?? []
                },
                onLoadRecoveryHistory: { [weak self] in
                    guard let self else {
                        return []
                    }
                    return (try? self.recoveryRecorder.loadRecent(limit: 100)) ?? []
                },
                onResolveRecoveryAudioURL: { [weak self] record in
                    guard let self else {
                        return .failure(RecoveryAudioError.missing)
                    }
                    return Result {
                        try self.recoveryRecorder.resolveAudioURL(for: record)
                    }
                },
                onRetryRecoveryRecord: { [weak self] record in
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
                    return Result {
                        try self.recoveryRecorder.delete(id: id)
                    }
                }
            )
        }
        historyWindowController?.show()
    }

    private func openQuickAdd() {
        terminologyQuickAddWindowController?.close()
        terminologyQuickAddWindowController = TerminologyQuickAddWindowController(
            existingEntries: config.transcription.terminology.entries,
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
                config: config,
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
            try configStore.save(newConfig)
            config = newConfig
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

    private func openOnboarding() {
        if onboardingWindowController == nil {
            let authManager: ChatGPTAuthManager
            if let concrete = self.authManager as? ChatGPTAuthManager {
                authManager = concrete
            } else {
                authManager = ChatGPTAuthManager()
            }
            onboardingWindowController = OnboardingWindowController(
                authManager: authManager,
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
                    do {
                        try await self.requestMicrophoneAccess(showExplanation: false)
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
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
        startProcessing(
            audio: audio,
            sessionID: sessionID,
            transcriptionConfig: config.transcription,
            injectionConfig: config.injection,
            launchAppContext: launchAppContextProvider(),
            attemptPolicy: .manualRetry,
            deleteAudioWhenFinished: false,
            automaticPasteAllowed: false
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

    private func requestMicrophoneAccessFromSettings() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                try await self.requestMicrophoneAccess(showExplanation: false)
                self.refreshReadyState()
            } catch {
                self.statusMenu?.update(state: .setupRequired, detail: error.localizedDescription)
            }
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
            self.overlay.showResult(text: L10n.text("Demo"), outcome: .pasted)

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
            overlay.showResult(text: L10n.text("Demo"), outcome: .pasted)
        case .error:
            overlay.showError(L10n.text("Clipboard only"))
        case .retryableError:
            overlay.showRetryableError(L10n.text("403 after 3 tries"))
        }

        let snapshotOutputURL = Self.visualAcceptanceSnapshotOutputURL()
        if let snapshotOutputURL {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [overlay] in
                do {
                    guard let snapshotter = overlay as? any OverlaySnapshotCapturing else {
                        throw OverlaySnapshotError.bitmapUnavailable
                    }
                    try snapshotter.writeSnapshot(to: snapshotOutputURL)
                    NSApplication.shared.terminate(nil)
                    return
                } catch {
                    print("OpenWhisper HUD self-capture failed: \(error.localizedDescription)")
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            NSApplication.shared.terminate(nil)
        }
    }

    private static func visualAcceptanceSnapshotOutputURL() -> URL? {
        AppLaunchMode.visualAcceptanceOutputURL(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments
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
        case .pasted:
            return L10n.text("Pasted transcript")
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
        let expiration = Date().addingTimeInterval(
            TimeInterval(max(1, config.privacy.failedAudioRetentionHours)) * 60 * 60
        )
        if pendingRetry?.audio.fileURL == audio.fileURL {
            let retry = PendingRetry(
                id: UUID(),
                audio: audio,
                launchAppContext: launchAppContext,
                transcriptionConfig: transcriptionConfig,
                injectionConfig: injectionConfig,
                expiresAt: expiration
            )
            pendingRetry = retry
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
            transcriptionConfig: transcriptionConfig,
            injectionConfig: injectionConfig,
            expiresAt: expiration
        )
        pendingRetry = retry
        schedulePendingRetryExpiry(for: retry)
    }

    private func clearPendingRetry() {
        pendingRetryExpiryTask?.cancel()
        pendingRetryExpiryTask = nil
        if let pendingRetry {
            try? FileManager.default.removeItem(at: pendingRetry.audio.fileURL)
        }
        pendingRetry = nil
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
        return false
    }

    private func recordTranscriptionFailure(
        audio: RecordedAudio,
        transcriptionConfig: TranscriptionConfig,
        processingStarted: UInt64
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
            estimatedPolishInputTokens: 0,
            estimatedPolishOutputTokens: 0,
            injectMs: 0,
            totalProcessingMs: elapsedMilliseconds(since: processingStarted),
            resultStatus: "error",
            errorCategory: "transcribe"
        )
        try? latencyRecorder.record(
            sample,
            retention: config.privacy.diagnosticsRetentionPolicy()
        )
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
            textPolishError: prepared.metrics.textPolishErrorMessage,
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
                textPolishProvider: prepared.metrics.textPolishProvider?.rawValue
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
            try StorageCleanupService(applicationSupportURL: configStore.directoryURL).deleteAllData()
        } catch {
            if firstError == nil {
                firstError = error
            }
        }

        let freshConfig = AppConfig()
        do {
            try configStore.save(freshConfig)
            config = freshConfig
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
            return "error"
        }

        switch outcome {
        case .pasted:
            return "pasted"
        case .copiedToClipboard:
            return "clipboard"
        }
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
        } else if let summary = RuntimePreflight.summary(for: issues) {
            statusMenu?.update(state: .setupRequired, detail: summary)
        } else {
            statusMenu?.update(state: state, detail: L10n.text("Ready. Press F5 to dictate"))
        }
    }
}
