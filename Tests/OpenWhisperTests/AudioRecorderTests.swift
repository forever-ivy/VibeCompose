import AVFoundation
import Testing
@testable import OpenWhisper

private final class FakeRecordingSession: RecordingSessionControlling, @unchecked Sendable {
    var prepareToRecordResult = true
    var recordResult = true
    private(set) var stopCallCount = 0
    var currentTime: TimeInterval = 1.25
    var averagePowerValue: Float = -30

    func prepareToRecord() -> Bool {
        prepareToRecordResult
    }

    func record() -> Bool {
        recordResult
    }

    func stop() {
        stopCallCount += 1
        currentTime = 0
    }

    func updateMeters() {}

    func averagePower(forChannel channelNumber: Int) -> Float {
        averagePowerValue
    }
}

private actor AccessRequestProbe {
    private var requested = false

    func markRequested() {
        requested = true
    }

    func wasRequested() -> Bool {
        requested
    }
}

struct AudioRecorderTests {
    @Test
    func microphoneRepairActionsOfferFirstRunPermissionRequest() {
        let actions = AudioRecorder.repairActions(for: .undetermined)

        #expect(actions.count == 1)
        #expect(actions[0].title == "Allow Microphone Access")
        #expect(actions[0].kind == .requestMicrophoneAccess)
        #expect(actions[0].prominence == .primary)
    }

    @Test
    func microphoneRepairActionsAppearOnlyWhenPermissionWasDenied() {
        #expect(AudioRecorder.repairActions(for: .granted).isEmpty)

        let actions = AudioRecorder.repairActions(for: .denied)
        #expect(actions.count == 1)
        #expect(actions[0].title == "Open Microphone Settings")
        #expect(
            actions[0].kind == .openSettings(
                PermissionSettingsDestination(
                    url: URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone")!,
                    paneIdentifier: "com.apple.settings.PrivacySecurity.extension",
                    anchor: "Privacy_Microphone"
                )
            )
        )
    }

    @Test
    func microphoneAccessRequestsSystemPromptWhenStatusIsUndetermined() async throws {
        let probe = AccessRequestProbe()

        try await AudioRecorder.ensureMicrophoneAccess(
            permissionProvider: { .undetermined },
            requestPermission: {
                await probe.markRequested()
                return true
            }
        )

        #expect(await probe.wasRequested())
    }

    @Test
    func microphoneAccessSkipsSystemPromptWhenAlreadyAuthorized() async throws {
        let probe = AccessRequestProbe()

        try await AudioRecorder.ensureMicrophoneAccess(
            permissionProvider: { .granted },
            requestPermission: {
                await probe.markRequested()
                return true
            }
        )

        #expect(!(await probe.wasRequested()))
    }

    @Test
    func microphoneAccessFailsImmediatelyWhenDenied() async {
        let probe = AccessRequestProbe()

        await #expect(throws: RecorderError.microphoneDenied) {
            try await AudioRecorder.ensureMicrophoneAccess(
                permissionProvider: { .denied },
                requestPermission: {
                    await probe.markRequested()
                    return false
                }
            )
        }

        #expect(!(await probe.wasRequested()))
    }

    @MainActor
    @Test
    func recorderInitializationWriteFailureRemovesPartialTemporaryFile() async {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-write-failure-\(UUID().uuidString).wav")
        let recorder = AudioRecorder(
            sampleRateHz: 16_000,
            permissionProvider: { .granted },
            permissionRequester: { true },
            sessionFactory: { url, _ in
                try Data("partial".utf8).write(to: url)
                throw CocoaError(.fileWriteOutOfSpace)
            },
            temporaryFileURLFactory: { fileURL },
            fileManager: .default
        )

        await #expect(throws: CocoaError.self) {
            try await recorder.startRecording()
        }
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @MainActor
    @Test
    func recorderStartFailureRemovesCreatedTemporaryFile() async {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-start-failure-\(UUID().uuidString).wav")
        let session = FakeRecordingSession()
        session.recordResult = false
        let recorder = AudioRecorder(
            sampleRateHz: 16_000,
            permissionProvider: { .granted },
            permissionRequester: { true },
            sessionFactory: { url, _ in
                try Data("partial".utf8).write(to: url)
                return session
            },
            temporaryFileURLFactory: { fileURL },
            fileManager: .default
        )

        await #expect(throws: RecorderError.recorderStartFailed) {
            try await recorder.startRecording()
        }
        #expect(session.stopCallCount == 1)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @MainActor
    @Test
    func cancelRecordingDiscardsActiveSessionAndDeletesTempFile() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("cancel-recording-test.wav")
        try Data("wave".utf8).write(to: fileURL)

        let session = FakeRecordingSession()
        let recorder = AudioRecorder(
            sampleRateHz: 16_000,
            permissionProvider: { .granted },
            permissionRequester: { true },
            sessionFactory: { _, _ in session },
            temporaryFileURLFactory: { fileURL },
            fileManager: .default
        )

        try await recorder.startRecording()
        try recorder.cancelRecording()

        #expect(session.stopCallCount == 1)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)

        #expect(throws: RecorderError.noActiveRecording) {
            try recorder.stopRecording()
        }
    }

    @MainActor
    @Test
    func stopRecordingCapturesDurationBeforeStoppingRecorder() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("duration-recording-test.wav")
        try Data("wave".utf8).write(to: fileURL)

        let session = FakeRecordingSession()
        session.currentTime = 3.45
        let recorder = AudioRecorder(
            sampleRateHz: 16_000,
            permissionProvider: { .granted },
            permissionRequester: { true },
            sessionFactory: { _, _ in session },
            temporaryFileURLFactory: { fileURL },
            fileManager: .default
        )

        try await recorder.startRecording()
        let audio = try recorder.stopRecording()

        #expect(audio.durationMs == 3_450)
        #expect(session.stopCallCount == 1)
        try? FileManager.default.removeItem(at: fileURL)
    }

    @MainActor
    @Test
    func recordingAutomaticallyStopsAtConfiguredMaximumDuration() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("max-duration-recording-test.wav")
        try Data("wave".utf8).write(to: fileURL)

        let session = FakeRecordingSession()
        session.currentTime = 0.05
        let recorder = AudioRecorder(
            sampleRateHz: 16_000,
            permissionProvider: { .granted },
            permissionRequester: { true },
            sessionFactory: { _, _ in session },
            temporaryFileURLFactory: { fileURL },
            fileManager: .default,
            maxDurationSeconds: 0
        )
        recorder.configure(maxDurationSeconds: 1)
        try await recorder.startRecording()

        try await Task.sleep(nanoseconds: 1_100_000_000)
        await Task.yield()
        await Task.yield()
        let audio = try recorder.stopRecording()

        #expect(session.stopCallCount >= 2)
        #expect(audio.durationMs >= 0)
        try? FileManager.default.removeItem(at: fileURL)
    }
}
