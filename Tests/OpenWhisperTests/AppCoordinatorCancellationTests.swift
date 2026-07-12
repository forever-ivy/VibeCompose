import CoreGraphics
import Foundation
import Testing
@testable import OpenWhisper

@MainActor
private final class FakeCoordinatorRecorder: RecordingControlling {
    private(set) var cancelRecordingCallCount = 0
    private(set) var stopRecordingCallCount = 0
    var onStartRecording: (@Sendable () async -> Void)?
    var startRecordingError: (any Error)?
    var nextAudio = RecordedAudio(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fake.wav"),
        durationMs: 1_000
    )

    func startRecording() async throws {
        await onStartRecording?()
        if let startRecordingError {
            throw startRecordingError
        }
    }

    func stopRecording() throws -> RecordedAudio {
        stopRecordingCallCount += 1
        return nextAudio
    }

    func cancelRecording() throws {
        cancelRecordingCallCount += 1
    }

    func currentLevel() -> CGFloat? {
        0.25
    }
}

@MainActor
private final class FakeCoordinatorOverlay: OverlayControlling {
    var onCancel: (@MainActor (OverlayCancelSource) -> Void)?
    var onRetry: (@MainActor () -> Void)?
    var onShowProcessing: (@MainActor () -> Void)?
    private(set) var hideCallCount = 0
    private(set) var recordingElapsedTexts: [String] = []
    private(set) var showProcessingCallCount = 0
    private(set) var retryableErrors: [String] = []

    func showRecording(elapsedText: String) {
        recordingElapsedTexts.append(elapsedText)
    }
    func updateRecording(level: CGFloat, elapsedText: String) {}
    func showProcessing() {
        showProcessingCallCount += 1
        onShowProcessing?()
    }
    func showResult(text: String, outcome: InjectionOutcome) {}
    func showError(_ message: String) {}
    func showRetryableError(_ message: String) {
        retryableErrors.append(message)
    }

    func hide() {
        hideCallCount += 1
    }
}

@MainActor
private final class FakeCoordinatorStatusMenu: StatusMenuUpdating {
    private(set) var updates: [(StatusMenuVisualState, String)] = []

    func update(state: StatusMenuVisualState, detail: String) {
        updates.append((state, detail))
    }
}

@MainActor
private final class FakeCoordinatorNotifier: NotificationDispatching {
    func ensureAuthorization() {}
    func notify(title: String, body: String) {}
}

@MainActor
private final class FakeSoundFeedback: SoundFeedbackPlaying {
    private(set) var events: [SoundFeedbackEvent] = []

    func play(_ event: SoundFeedbackEvent, enabled: Bool) {
        guard enabled else {
            return
        }
        events.append(event)
    }
}

@MainActor
private final class FakeCoordinatorInjector: TextInjecting {
    private(set) var injectCallCount = 0
    private(set) var launchContexts: [LaunchAppContext?] = []
    private(set) var automaticPastePermissions: [Bool] = []

    func inject(
        text: String,
        preserveClipboard: Bool,
        restoreDelayMilliseconds: UInt64,
        launchAppContext: LaunchAppContext?,
        automaticPasteAllowed: Bool
    ) async throws -> InjectionOutcome {
        injectCallCount += 1
        launchContexts.append(launchAppContext)
        automaticPastePermissions.append(automaticPasteAllowed)
        return automaticPasteAllowed
            ? .pasted
            : .copiedToClipboard(reason: .retryRequiresManualPaste)
    }
}

@MainActor
private final class BlockingCoordinatorInjector: TextInjecting {
    private(set) var didStart = false
    private(set) var didComplete = false

    func inject(
        text: String,
        preserveClipboard: Bool,
        restoreDelayMilliseconds: UInt64,
        launchAppContext: LaunchAppContext?,
        automaticPasteAllowed: Bool
    ) async throws -> InjectionOutcome {
        didStart = true
        try await Task.sleep(for: .seconds(5))
        didComplete = true
        return .pasted
    }
}

private func minimalCoordinatorWaveData() -> Data {
    Data("RIFF".utf8) + Data(repeating: 0, count: 4) + Data("WAVE".utf8)
}

private struct FakeCoordinatorPipeline: DictationPreparing {
    func prepare(audio: RecordedAudio) async throws -> PreparedDictation {
        try? Data().write(to: audio.fileURL)
        return PreparedDictation(
            rawText: "raw",
            finalText: "final",
            normalizationApplied: false,
            exactReplacementCount: 0,
            fuzzyReplacementCount: 0,
            metrics: DictationMetrics(
                transcription: TranscriptionMetrics(
                    provider: .chatGPTManagedAuth,
                    audioDurationMs: audio.durationMs,
                    audioBytes: 4,
                    authMs: 0,
                    transcribeMs: 0,
                    promptIncluded: false
                ),
                normalizationMs: 0
            )
        )
    }
}

private actor CoordinatorGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private struct BlockingCoordinatorPipeline: DictationPreparing {
    let gate: CoordinatorGate

    func prepare(audio: RecordedAudio) async throws -> PreparedDictation {
        try? Data().write(to: audio.fileURL)
        await gate.wait()
        return PreparedDictation(
            rawText: "raw",
            finalText: "final",
            normalizationApplied: false,
            exactReplacementCount: 0,
            fuzzyReplacementCount: 0,
            metrics: DictationMetrics(
                transcription: TranscriptionMetrics(
                    provider: .chatGPTManagedAuth,
                    audioDurationMs: audio.durationMs,
                    audioBytes: 4,
                    authMs: 0,
                    transcribeMs: 0,
                    promptIncluded: false
                ),
                normalizationMs: 0
            )
        )
    }
}

private final class FakeLatencyRecorder: LatencyRecording, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var samples: [LatencySample] = []

    func record(
        _ sample: LatencySample,
        retention _: DiagnosticsRetentionPolicy
    ) throws {
        lock.lock()
        samples.append(sample)
        lock.unlock()
    }

    func prune(retention _: DiagnosticsRetentionPolicy) throws {}
}

private enum ScriptedCoordinatorPipelineOutcome: Sendable {
    case success(String)
    case retryableCloudflare(Int)
}

private final class CoordinatorPipelineScript: @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [ScriptedCoordinatorPipelineOutcome]
    private(set) var policies: [TranscriptionAttemptPolicy] = []
    private(set) var audioPaths: [String] = []

    init(outcomes: [ScriptedCoordinatorPipelineOutcome]) {
        self.outcomes = outcomes
    }

    func makePipeline(policy: TranscriptionAttemptPolicy) -> any DictationPreparing {
        lock.lock()
        policies.append(policy)
        lock.unlock()
        return ScriptedCoordinatorPipeline(script: self)
    }

    func prepare(audio: RecordedAudio) throws -> PreparedDictation {
        lock.lock()
        audioPaths.append(audio.fileURL.path)
        let outcome = outcomes.isEmpty ? .success("final") : outcomes.removeFirst()
        lock.unlock()

        switch outcome {
        case .success(let text):
            return PreparedDictation(
                rawText: text,
                finalText: text,
                normalizationApplied: false,
                exactReplacementCount: 0,
                fuzzyReplacementCount: 0,
                metrics: DictationMetrics(
                    transcription: TranscriptionMetrics(
                        provider: .chatGPTManagedAuth,
                        audioDurationMs: audio.durationMs,
                        audioBytes: (try? Data(contentsOf: audio.fileURL).count) ?? 0,
                        authMs: 0,
                        transcribeMs: 1,
                        promptIncluded: true
                    ),
                    normalizationMs: 0
                )
            )
        case .retryableCloudflare(let attempts):
            throw TranscriptionError.retryableCloudflareChallenge(attempts: attempts)
        }
    }
}

private struct ScriptedCoordinatorPipeline: DictationPreparing {
    let script: CoordinatorPipelineScript

    func prepare(audio: RecordedAudio) async throws -> PreparedDictation {
        try script.prepare(audio: audio)
    }
}

@MainActor
private func waitForCoordinatorState(
    _ coordinator: AppCoordinator,
    toBecome expectedState: AppCoordinator.State,
    attempts: Int = 100
) async {
    for _ in 0..<attempts where coordinator.state != expectedState {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

@MainActor
private func waitForCondition(
    attempts: Int = 100,
    condition: @escaping @MainActor () -> Bool
) async {
    for _ in 0..<attempts where condition() == false {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

@MainActor
struct AppCoordinatorCancellationTests {
    @Test
    func cancelCurrentSessionDiscardsActiveRecordingAndResetsState() throws {
        let recorder = FakeCoordinatorRecorder()
        let overlay = FakeCoordinatorOverlay()
        let statusMenu = FakeCoordinatorStatusMenu()
        let coordinator = AppCoordinator(
            config: AppConfig(),
            notifier: FakeCoordinatorNotifier(),
            injector: FakeCoordinatorInjector(),
            overlay: overlay,
            authManager: FakeChatGPTAuthManager(),
            latencyRecorder: FakeLatencyRecorder(),
            recorderFactory: { _ in recorder },
            statusMenuFactory: { _, _, _, _, _ in statusMenu },
            pipelineFactory: { _, _, _ in FakeCoordinatorPipeline() }
        )

        coordinator.recorder = recorder
        coordinator.statusMenu = statusMenu
        coordinator.state = AppCoordinator.State.recording
        coordinator.launchAppContext = LaunchAppContext(
            bundleIdentifier: "com.example.editor",
            localizedName: "Editor",
            processIdentifier: 123
        )

        coordinator.cancelCurrentSession()

        #expect(recorder.cancelRecordingCallCount == 1)
        #expect(coordinator.state == AppCoordinator.State.idle)
        #expect(coordinator.launchAppContext == nil)
        #expect(overlay.hideCallCount == 1)
        #expect(statusMenu.updates.last?.0 == .ready)
    }

    @Test
    func cancelCurrentSessionCancelsProcessingTaskWithoutInjecting() async throws {
        let recorder = FakeCoordinatorRecorder()
        let overlay = FakeCoordinatorOverlay()
        let statusMenu = FakeCoordinatorStatusMenu()
        let injector = FakeCoordinatorInjector()
        let coordinator = AppCoordinator(
            config: AppConfig(),
            notifier: FakeCoordinatorNotifier(),
            injector: injector,
            overlay: overlay,
            authManager: FakeChatGPTAuthManager(),
            latencyRecorder: FakeLatencyRecorder(),
            recorderFactory: { _ in recorder },
            statusMenuFactory: { _, _, _, _, _ in statusMenu },
            pipelineFactory: { _, _, _ in FakeCoordinatorPipeline() }
        )

        let processingTask = Task<Void, Never> {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }

        coordinator.state = AppCoordinator.State.processing
        coordinator.statusMenu = statusMenu
        coordinator.processingTask = processingTask
        coordinator.launchAppContext = LaunchAppContext(
            bundleIdentifier: "com.example.editor",
            localizedName: "Editor",
            processIdentifier: 123
        )

        coordinator.cancelCurrentSession()
        await Task.yield()

        #expect(processingTask.isCancelled == true)
        #expect(injector.injectCallCount == 0)
        #expect(coordinator.state == AppCoordinator.State.idle)
        #expect(coordinator.processingTask == nil)
        #expect(coordinator.launchAppContext == nil)
        #expect(overlay.hideCallCount == 1)
        #expect(statusMenu.updates.last?.0 == .ready)
    }

    @Test
    func cancelCurrentSessionCancelsAsyncPasteWaitBeforeLateCompletion() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audioURL = root.appendingPathComponent("async-injection.wav")
        try minimalCoordinatorWaveData().write(to: audioURL)

        let recorder = FakeCoordinatorRecorder()
        recorder.nextAudio = RecordedAudio(fileURL: audioURL, durationMs: 1_000)
        let overlay = FakeCoordinatorOverlay()
        let statusMenu = FakeCoordinatorStatusMenu()
        let injector = BlockingCoordinatorInjector()
        let coordinator = AppCoordinator(
            configStore: ConfigStore(homeDirectoryURL: root),
            config: AppConfig(),
            notifier: FakeCoordinatorNotifier(),
            injector: injector,
            overlay: overlay,
            authManager: FakeChatGPTAuthManager(),
            latencyRecorder: FakeLatencyRecorder(),
            soundFeedback: FakeSoundFeedback(),
            recorderFactory: { _ in recorder },
            statusMenuFactory: { _, _, _, _, _ in statusMenu },
            pipelineFactory: { _, _, _ in FakeCoordinatorPipeline() }
        )
        coordinator.recorder = recorder
        coordinator.statusMenu = statusMenu

        coordinator.handleHotkeyPress()
        await waitForCoordinatorState(coordinator, toBecome: .recording)
        coordinator.handleHotkeyPress()
        await waitForCondition { injector.didStart }

        coordinator.cancelCurrentSession()
        try await Task.sleep(for: .milliseconds(30))

        #expect(coordinator.state == .idle)
        #expect(injector.didStart)
        #expect(injector.didComplete == false)
        #expect(overlay.hideCallCount == 1)
    }

    @Test
    func shutdownSynchronouslyRemovesOwnedProcessingAudio() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audioURL = root.appendingPathComponent("processing.wav")
        try minimalCoordinatorWaveData().write(to: audioURL)

        let gate = CoordinatorGate()
        let recorder = FakeCoordinatorRecorder()
        recorder.nextAudio = RecordedAudio(fileURL: audioURL, durationMs: 1_000)
        let overlay = FakeCoordinatorOverlay()
        let statusMenu = FakeCoordinatorStatusMenu()
        let coordinator = AppCoordinator(
            configStore: ConfigStore(homeDirectoryURL: root),
            config: AppConfig(),
            notifier: FakeCoordinatorNotifier(),
            injector: FakeCoordinatorInjector(),
            overlay: overlay,
            authManager: FakeChatGPTAuthManager(),
            latencyRecorder: FakeLatencyRecorder(),
            soundFeedback: FakeSoundFeedback(),
            recorderFactory: { _ in recorder },
            statusMenuFactory: { _, _, _, _, _ in statusMenu },
            pipelineFactory: { _, _, _ in BlockingCoordinatorPipeline(gate: gate) }
        )
        coordinator.recorder = recorder
        coordinator.statusMenu = statusMenu

        coordinator.handleHotkeyPress()
        await waitForCoordinatorState(coordinator, toBecome: .recording)
        coordinator.handleHotkeyPress()
        await waitForCoordinatorState(coordinator, toBecome: .processing)

        coordinator.shutdown()

        #expect(coordinator.state == .idle)
        #expect(!FileManager.default.fileExists(atPath: audioURL.path))
        #expect(overlay.hideCallCount == 1)
        await gate.resume()
    }

    @Test
    func startRecordingCapturesLaunchContextBeforeProcessingOverlay() async throws {
        let startGate = CoordinatorGate()
        let recorder = FakeCoordinatorRecorder()
        recorder.onStartRecording = {
            await startGate.wait()
        }
        let capturedContext = LaunchAppContext(
            bundleIdentifier: "com.example.editor",
            localizedName: "Editor",
            processIdentifier: 123
        )
        let overlay = FakeCoordinatorOverlay()
        let statusMenu = FakeCoordinatorStatusMenu()
        let soundFeedback = FakeSoundFeedback()
        var contextWhenProcessing: LaunchAppContext?
        let coordinator = AppCoordinator(
            config: AppConfig(),
            notifier: FakeCoordinatorNotifier(),
            injector: FakeCoordinatorInjector(),
            overlay: overlay,
            authManager: FakeChatGPTAuthManager(),
            latencyRecorder: FakeLatencyRecorder(),
            soundFeedback: soundFeedback,
            recorderFactory: { _ in recorder },
            statusMenuFactory: { _, _, _, _, _ in statusMenu },
            pipelineFactory: { _, _, _ in FakeCoordinatorPipeline() },
            launchAppContextProvider: { capturedContext }
        )
        overlay.onShowProcessing = {
            contextWhenProcessing = coordinator.launchAppContext
        }

        coordinator.recorder = recorder
        coordinator.statusMenu = statusMenu
        coordinator.handleHotkeyPress()

        #expect(contextWhenProcessing == capturedContext)
        #expect(overlay.showProcessingCallCount == 1)
        #expect(overlay.recordingElapsedTexts.isEmpty)
        #expect(soundFeedback.events.isEmpty)

        coordinator.cancelCurrentSession()
        await startGate.resume()
    }

    @Test
    func secondHotkeyTransitionsRecordingSessionIntoProcessing() async throws {
        let processingGate = CoordinatorGate()
        let recorder = FakeCoordinatorRecorder()
        let overlay = FakeCoordinatorOverlay()
        let statusMenu = FakeCoordinatorStatusMenu()
        let soundFeedback = FakeSoundFeedback()
        let coordinator = AppCoordinator(
            config: AppConfig(),
            notifier: FakeCoordinatorNotifier(),
            injector: FakeCoordinatorInjector(),
            overlay: overlay,
            authManager: FakeChatGPTAuthManager(),
            latencyRecorder: FakeLatencyRecorder(),
            soundFeedback: soundFeedback,
            recorderFactory: { _ in recorder },
            statusMenuFactory: { _, _, _, _, _ in statusMenu },
            pipelineFactory: { _, _, _ in BlockingCoordinatorPipeline(gate: processingGate) }
        )

        coordinator.recorder = recorder
        coordinator.statusMenu = statusMenu

        coordinator.handleHotkeyPress()
        await waitForCoordinatorState(coordinator, toBecome: .recording)

        coordinator.handleHotkeyPress()
        await Task.yield()

        #expect(recorder.stopRecordingCallCount == 1)
        #expect(coordinator.state == AppCoordinator.State.processing)
        #expect(overlay.showProcessingCallCount >= 1)
        #expect(statusMenu.updates.last?.0 == .processing)
        #expect(soundFeedback.events == [.recordingStarted, .recordingStopped])

        await processingGate.resume()
    }

    @Test
    func recordingStartSoundPlaysOnlyAfterRecorderStarts() async throws {
        let recorder = FakeCoordinatorRecorder()
        let overlay = FakeCoordinatorOverlay()
        let statusMenu = FakeCoordinatorStatusMenu()
        let soundFeedback = FakeSoundFeedback()
        let coordinator = AppCoordinator(
            config: AppConfig(),
            notifier: FakeCoordinatorNotifier(),
            injector: FakeCoordinatorInjector(),
            overlay: overlay,
            authManager: FakeChatGPTAuthManager(),
            latencyRecorder: FakeLatencyRecorder(),
            soundFeedback: soundFeedback,
            recorderFactory: { _ in recorder },
            statusMenuFactory: { _, _, _, _, _ in statusMenu },
            pipelineFactory: { _, _, _ in FakeCoordinatorPipeline() }
        )

        coordinator.recorder = recorder
        coordinator.statusMenu = statusMenu
        coordinator.handleHotkeyPress()
        await waitForCoordinatorState(coordinator, toBecome: .recording)

        #expect(soundFeedback.events == [.recordingStarted])

        coordinator.cancelCurrentSession()
    }

    @Test
    func recordingStartFailureDoesNotPlayFeedbackSound() async throws {
        let recorder = FakeCoordinatorRecorder()
        recorder.startRecordingError = NSError(
            domain: "OpenWhisperTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "recorder failed"]
        )
        let overlay = FakeCoordinatorOverlay()
        let statusMenu = FakeCoordinatorStatusMenu()
        let soundFeedback = FakeSoundFeedback()
        let coordinator = AppCoordinator(
            config: AppConfig(),
            notifier: FakeCoordinatorNotifier(),
            injector: FakeCoordinatorInjector(),
            overlay: overlay,
            authManager: FakeChatGPTAuthManager(),
            latencyRecorder: FakeLatencyRecorder(),
            soundFeedback: soundFeedback,
            recorderFactory: { _ in recorder },
            statusMenuFactory: { _, _, _, _, _ in statusMenu },
            pipelineFactory: { _, _, _ in FakeCoordinatorPipeline() }
        )

        coordinator.recorder = recorder
        coordinator.statusMenu = statusMenu
        coordinator.handleHotkeyPress()
        await waitForCoordinatorState(coordinator, toBecome: .idle)

        #expect(soundFeedback.events.isEmpty)
    }

    @Test
    func disabledFeedbackSoundSettingSuppressesRecordingSounds() async throws {
        let processingGate = CoordinatorGate()
        let recorder = FakeCoordinatorRecorder()
        let overlay = FakeCoordinatorOverlay()
        let statusMenu = FakeCoordinatorStatusMenu()
        let soundFeedback = FakeSoundFeedback()
        var config = AppConfig()
        config.transcription.feedbackSoundsEnabled = false
        let coordinator = AppCoordinator(
            config: config,
            notifier: FakeCoordinatorNotifier(),
            injector: FakeCoordinatorInjector(),
            overlay: overlay,
            authManager: FakeChatGPTAuthManager(),
            latencyRecorder: FakeLatencyRecorder(),
            soundFeedback: soundFeedback,
            recorderFactory: { _ in recorder },
            statusMenuFactory: { _, _, _, _, _ in statusMenu },
            pipelineFactory: { _, _, _ in BlockingCoordinatorPipeline(gate: processingGate) }
        )

        coordinator.recorder = recorder
        coordinator.statusMenu = statusMenu
        coordinator.handleHotkeyPress()
        await waitForCoordinatorState(coordinator, toBecome: .recording)
        coordinator.handleHotkeyPress()
        await Task.yield()

        #expect(soundFeedback.events.isEmpty)

        await processingGate.resume()
    }

    @Test
    func processingHotkeyDoesNotPlayRecordingFeedbackSound() {
        let recorder = FakeCoordinatorRecorder()
        let overlay = FakeCoordinatorOverlay()
        let statusMenu = FakeCoordinatorStatusMenu()
        let soundFeedback = FakeSoundFeedback()
        let coordinator = AppCoordinator(
            config: AppConfig(),
            notifier: FakeCoordinatorNotifier(),
            injector: FakeCoordinatorInjector(),
            overlay: overlay,
            authManager: FakeChatGPTAuthManager(),
            latencyRecorder: FakeLatencyRecorder(),
            soundFeedback: soundFeedback,
            recorderFactory: { _ in recorder },
            statusMenuFactory: { _, _, _, _, _ in statusMenu },
            pipelineFactory: { _, _, _ in FakeCoordinatorPipeline() }
        )

        coordinator.recorder = recorder
        coordinator.statusMenu = statusMenu
        coordinator.state = AppCoordinator.State.processing
        coordinator.handleHotkeyPress()

        #expect(soundFeedback.events.isEmpty)
    }

    @Test
    func retryableTranscriptionFailureCopiesAudioAndRetriesSavedRecordingOnce() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let originalAudioURL = root.appendingPathComponent("original.wav")
        try minimalCoordinatorWaveData().write(to: originalAudioURL)

        let recorder = FakeCoordinatorRecorder()
        recorder.nextAudio = RecordedAudio(fileURL: originalAudioURL, durationMs: 1_000)
        let overlay = FakeCoordinatorOverlay()
        let statusMenu = FakeCoordinatorStatusMenu()
        let injector = FakeCoordinatorInjector()
        let latencyRecorder = FakeLatencyRecorder()
        let capturedContext = LaunchAppContext(
            bundleIdentifier: "com.example.editor",
            localizedName: "Editor",
            processIdentifier: 123
        )
        let script = CoordinatorPipelineScript(outcomes: [
            .retryableCloudflare(3),
            .success("retry final"),
        ])
        let configStore = ConfigStore(fileManager: .default, homeDirectoryURL: root)
        let coordinator = AppCoordinator(
            configStore: configStore,
            config: AppConfig(),
            notifier: FakeCoordinatorNotifier(),
            injector: injector,
            overlay: overlay,
            authManager: FakeChatGPTAuthManager(),
            latencyRecorder: latencyRecorder,
            recorderFactory: { _ in recorder },
            statusMenuFactory: { _, _, _, _, _ in statusMenu },
            pipelineFactory: { _, _, policy in script.makePipeline(policy: policy) },
            launchAppContextProvider: { capturedContext }
        )

        coordinator.recorder = recorder
        coordinator.statusMenu = statusMenu
        coordinator.handleHotkeyPress()
        await waitForCoordinatorState(coordinator, toBecome: .recording)
        coordinator.handleHotkeyPress()
        await waitForCondition { overlay.retryableErrors.count == 1 }

        #expect(FileManager.default.fileExists(atPath: originalAudioURL.path) == false)
        #expect(script.policies == [.automatic])
        #expect(script.audioPaths.count == 1)

        overlay.onRetry?()
        await waitForCondition { injector.injectCallCount == 1 }

        #expect(script.audioPaths.count == 2)
        #expect(script.policies == [.automatic, .manualRetry])
        #expect(script.audioPaths[0] == originalAudioURL.path)
        #expect(script.audioPaths[1] != originalAudioURL.path)
        #expect(FileManager.default.fileExists(atPath: script.audioPaths[1]) == false)
        #expect(injector.launchContexts == [capturedContext])
        #expect(injector.automaticPastePermissions == [false])
        #expect(latencyRecorder.samples.map(\.resultStatus) == ["error", "clipboard"])

        let recoveryStore = RecoveryStore(
            directoryURL: configStore.directoryURL.appendingPathComponent("Recovery", isDirectory: true)
        )
        let recoveryRecords = try recoveryStore.loadRecent(limit: 10)
        #expect(recoveryRecords.map(\.outcome) == ["error"])
        #expect(RecoveryHistoryPreview.recentItems(from: recoveryRecords, kind: .audio, limit: 10).count == 1)
        #expect(RecoveryHistoryPreview.recentItems(from: recoveryRecords, kind: .asr, limit: 10).isEmpty)

        let history = try TranscriptionHistoryRecorder(directoryURL: configStore.directoryURL)
            .loadRecent(limit: 10)
        #expect(history.map(\.finalText) == ["retry final"])
        #expect(history.allSatisfy { $0.rawText == nil })
    }

    @Test
    func retryFailureKeepsSavedAudioAndRetryControlAvailable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let originalAudioURL = root.appendingPathComponent("original.wav")
        try minimalCoordinatorWaveData().write(to: originalAudioURL)

        let recorder = FakeCoordinatorRecorder()
        recorder.nextAudio = RecordedAudio(fileURL: originalAudioURL, durationMs: 1_000)
        let overlay = FakeCoordinatorOverlay()
        let statusMenu = FakeCoordinatorStatusMenu()
        let script = CoordinatorPipelineScript(outcomes: [
            .retryableCloudflare(3),
            .retryableCloudflare(1),
        ])
        let coordinator = AppCoordinator(
            configStore: ConfigStore(fileManager: .default, homeDirectoryURL: root),
            config: AppConfig(),
            notifier: FakeCoordinatorNotifier(),
            injector: FakeCoordinatorInjector(),
            overlay: overlay,
            authManager: FakeChatGPTAuthManager(),
            latencyRecorder: FakeLatencyRecorder(),
            recorderFactory: { _ in recorder },
            statusMenuFactory: { _, _, _, _, _ in statusMenu },
            pipelineFactory: { _, _, policy in script.makePipeline(policy: policy) }
        )

        coordinator.recorder = recorder
        coordinator.statusMenu = statusMenu
        coordinator.handleHotkeyPress()
        await waitForCoordinatorState(coordinator, toBecome: .recording)
        coordinator.handleHotkeyPress()
        await waitForCondition { overlay.retryableErrors.count == 1 }

        overlay.onRetry?()
        await waitForCondition { overlay.retryableErrors.count == 2 }

        #expect(script.policies == [.automatic, .manualRetry])
        #expect(script.audioPaths.count == 2)
        #expect(script.audioPaths[1] != originalAudioURL.path)
        #expect(FileManager.default.fileExists(atPath: script.audioPaths[1]) == true)
    }

    @Test
    func startingNewRecordingAfterRetryableFailureClearsSavedRetryAudio() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let originalAudioURL = root.appendingPathComponent("original.wav")
        try minimalCoordinatorWaveData().write(to: originalAudioURL)

        let recorder = FakeCoordinatorRecorder()
        recorder.nextAudio = RecordedAudio(fileURL: originalAudioURL, durationMs: 1_000)
        let overlay = FakeCoordinatorOverlay()
        let statusMenu = FakeCoordinatorStatusMenu()
        let script = CoordinatorPipelineScript(outcomes: [.retryableCloudflare(3)])
        let configStore = ConfigStore(fileManager: .default, homeDirectoryURL: root)
        let coordinator = AppCoordinator(
            configStore: configStore,
            config: AppConfig(),
            notifier: FakeCoordinatorNotifier(),
            injector: FakeCoordinatorInjector(),
            overlay: overlay,
            authManager: FakeChatGPTAuthManager(),
            latencyRecorder: FakeLatencyRecorder(),
            recorderFactory: { _ in recorder },
            statusMenuFactory: { _, _, _, _, _ in statusMenu },
            pipelineFactory: { _, _, policy in script.makePipeline(policy: policy) }
        )

        coordinator.recorder = recorder
        coordinator.statusMenu = statusMenu
        coordinator.handleHotkeyPress()
        await waitForCoordinatorState(coordinator, toBecome: .recording)
        coordinator.handleHotkeyPress()
        await waitForCondition { overlay.retryableErrors.count == 1 }

        let retryDirectory = configStore.directoryURL.appendingPathComponent("Retry", isDirectory: true)
        let savedRetryFiles = (try? FileManager.default.contentsOfDirectory(atPath: retryDirectory.path)) ?? []
        #expect(savedRetryFiles.count == 1)

        coordinator.handleHotkeyPress()
        let remainingRetryFiles = (try? FileManager.default.contentsOfDirectory(atPath: retryDirectory.path)) ?? []

        #expect(remainingRetryFiles.isEmpty)
        coordinator.cancelCurrentSession()
    }

    @Test
    func launchWithMissingChatGPTSessionShowsSetupStateWithoutLoginWindow() throws {
        let authManager = FakeChatGPTAuthManager(
            snapshot: ChatGPTAuthSnapshot(
                state: .signedOut,
                detail: "Sign in first",
                userEmail: nil
            )
        )
        let statusMenu = FakeCoordinatorStatusMenu()
        let coordinator = AppCoordinator(
            notifier: FakeCoordinatorNotifier(),
            injector: FakeCoordinatorInjector(),
            overlay: FakeCoordinatorOverlay(),
            authManager: authManager,
            latencyRecorder: FakeLatencyRecorder(),
            recorderFactory: { _ in FakeCoordinatorRecorder() },
            statusMenuFactory: { _, _, _, _, _ in statusMenu },
            pipelineFactory: { _, _, _ in FakeCoordinatorPipeline() }
        )
        coordinator.statusMenu = statusMenu

        coordinator.checkLaunchLoginState()

        #expect(statusMenu.updates.contains { $0.0 == .setupRequired && $0.1 == "Sign in first" })
    }
}
