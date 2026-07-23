import AVFoundation
import AVFAudio
import CoreGraphics
import Foundation
import OSLog

struct RecordedAudio: Sendable {
    let fileURL: URL
    let durationMs: Int
}

protocol RecordingSessionControlling: AnyObject, Sendable {
    func prepareToRecord() -> Bool
    func record() -> Bool
    func stop()
    func updateMeters()
    func averagePower(forChannel channelNumber: Int) -> Float
    var currentTime: TimeInterval { get }
}

@MainActor
protocol RecordingControlling: AnyObject {
    func startRecording() async throws
    func stopRecording() throws -> RecordedAudio
    func cancelRecording() throws
    func currentLevel() -> CGFloat?
    func configure(maxDurationSeconds: Int)
    func recordingPermissionState() -> MicrophonePermissionState
    func ensureRecordingPermission() async throws
}

extension RecordingControlling {
    func configure(maxDurationSeconds _: Int) {}
    func recordingPermissionState() -> MicrophonePermissionState { .granted }
    func ensureRecordingPermission() async throws {}
}

enum MicrophonePermissionState: Sendable, Equatable {
    case granted
    case undetermined
    case denied
}

enum RecorderError: LocalizedError {
    case microphoneDenied
    case recorderInitFailed
    case recorderStartFailed
    case noActiveRecording
    case invalidMaximumDuration

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return L10n.text("Microphone access is required to start recording.")
        case .recorderInitFailed:
            return L10n.text("Could not initialize the audio recorder.")
        case .recorderStartFailed:
            return L10n.text("Could not start audio recording.")
        case .noActiveRecording:
            return L10n.text("There is no active recording session.")
        case .invalidMaximumDuration:
            return L10n.text("The maximum recording duration is invalid.")
        }
    }
}

@MainActor
final class AudioRecorder: RecordingControlling {
    typealias PermissionProvider = @Sendable () -> MicrophonePermissionState
    typealias PermissionRequester = @Sendable () async -> Bool
    typealias SessionFactory = @Sendable (URL, [String: Any]) throws -> any RecordingSessionControlling
    typealias TemporaryFileURLFactory = @Sendable () -> URL

    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? ProductIdentity.defaultBundleIdentifier,
        category: "AudioRecorder"
    )

    private let sampleRateHz: Int
    private let permissionProvider: PermissionProvider
    private let permissionRequester: PermissionRequester
    private let sessionFactory: SessionFactory
    private let temporaryFileURLFactory: TemporaryFileURLFactory
    private let fileManager: FileManager
    private var recorder: (any RecordingSessionControlling)?
    private var fileURL: URL?
    private var deadlineTask: Task<Void, Never>?
    private var deadlineDurationMs: Int?
    private(set) var maxDurationSeconds: Int
    var onMaximumDurationReached: (@MainActor () -> Void)?

    init(
        sampleRateHz: Int,
        permissionProvider: @escaping PermissionProvider = { microphonePermissionState() },
        permissionRequester: @escaping PermissionRequester = {
            if #available(macOS 14.0, *) {
                return await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }

            return await AVCaptureDevice.requestAccess(for: .audio)
        },
        sessionFactory: @escaping SessionFactory = { url, settings in
            try AVAudioRecorderSession(url: url, settings: settings)
        },
        temporaryFileURLFactory: @escaping TemporaryFileURLFactory = {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("vibewhisper-\(UUID().uuidString).wav")
        },
        fileManager: FileManager = .default,
        maxDurationSeconds: Int = 120
    ) {
        self.sampleRateHz = sampleRateHz
        self.permissionProvider = permissionProvider
        self.permissionRequester = permissionRequester
        self.sessionFactory = sessionFactory
        self.temporaryFileURLFactory = temporaryFileURLFactory
        self.fileManager = fileManager
        self.maxDurationSeconds = maxDurationSeconds
    }

    nonisolated static func microphonePermissionState() -> MicrophonePermissionState {
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return .granted
            case .undetermined:
                return .undetermined
            case .denied:
                return .denied
            @unknown default:
                return .denied
            }
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .notDetermined:
            return .undetermined
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    nonisolated static func repairActions(for state: MicrophonePermissionState) -> [PermissionRepairAction] {
        switch state {
        case .granted:
            return []
        case .undetermined:
            return [
                PermissionRepairAction(
                    title: L10n.text("Allow Microphone Access"),
                    kind: .requestMicrophoneAccess,
                    prominence: .primary
                ),
                PermissionRepairAction(
                    title: L10n.text("Refresh Status"),
                    kind: .refreshStatus,
                    prominence: .utility
                ),
            ]
        case .denied:
            return [
                PermissionRepairAction(
                    title: L10n.text("Open Microphone Settings"),
                    kind: .openSettings(.microphone),
                    prominence: .secondary
                ),
                PermissionRepairAction(
                    title: L10n.text("Refresh Status"),
                    kind: .refreshStatus,
                    prominence: .utility
                ),
            ]
        }
    }

    nonisolated static func ensureMicrophoneAccess(
        permissionProvider: PermissionProvider = { microphonePermissionState() },
        requestPermission: @escaping PermissionRequester = {
            if #available(macOS 14.0, *) {
                return await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }

            return await AVCaptureDevice.requestAccess(for: .audio)
        }
    ) async throws {
        let status = permissionProvider()
        logger.info("Microphone access check started with status: \(String(describing: status), privacy: .public)")

        switch status {
        case .granted:
            logger.info("Microphone access already authorized")
            return
        case .undetermined:
            logger.info("Microphone access not determined; requesting system prompt")
            let granted = await requestPermission()
            logger.info("Microphone access request returned granted=\(granted, privacy: .public)")
            guard granted else {
                throw RecorderError.microphoneDenied
            }
        case .denied:
            logger.error("Microphone access unavailable with status: \(String(describing: status), privacy: .public)")
            throw RecorderError.microphoneDenied
        @unknown default:
            logger.error("Microphone access hit unknown authorization status")
            throw RecorderError.microphoneDenied
        }
    }

    func startRecording() async throws {
        guard maxDurationSeconds > 0 else {
            throw RecorderError.invalidMaximumDuration
        }

        try await Self.ensureMicrophoneAccess(
            permissionProvider: permissionProvider,
            requestPermission: permissionRequester
        )

        let tempURL = temporaryFileURLFactory()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRateHz,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]

        let recorder: any RecordingSessionControlling
        do {
            recorder = try sessionFactory(tempURL, settings)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }
        guard recorder.prepareToRecord(), recorder.record() else {
            recorder.stop()
            try? fileManager.removeItem(at: tempURL)
            throw RecorderError.recorderStartFailed
        }

        self.recorder = recorder
        self.fileURL = tempURL
        self.deadlineDurationMs = nil
        deadlineTask?.cancel()
        let (durationNanoseconds, overflow) = UInt64(maxDurationSeconds)
            .multipliedReportingOverflow(by: 1_000_000_000)
        guard !overflow else {
            self.recorder = nil
            self.fileURL = nil
            recorder.stop()
            try? fileManager.removeItem(at: tempURL)
            throw RecorderError.invalidMaximumDuration
        }
        deadlineTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: durationNanoseconds)
            } catch {
                return
            }
            guard let self, let recorder = self.recorder else {
                return
            }
            self.deadlineDurationMs = Int((recorder.currentTime * 1000).rounded())
            recorder.stop()
            Self.logger.info(
                "Recorder reached maximum duration seconds=\(self.maxDurationSeconds, privacy: .public)"
            )
            self.onMaximumDurationReached?()
        }
        Self.logger.info(
            "Recorder started sampleRateHz=\(self.sampleRateHz, privacy: .public) file=\(tempURL.lastPathComponent, privacy: .public)"
        )
    }

    func recordingPermissionState() -> MicrophonePermissionState {
        permissionProvider()
    }

    func ensureRecordingPermission() async throws {
        try await Self.ensureMicrophoneAccess(
            permissionProvider: permissionProvider,
            requestPermission: permissionRequester
        )
    }

    func stopRecording() throws -> RecordedAudio {
        guard let recorder, let fileURL else {
            throw RecorderError.noActiveRecording
        }

        let durationMs = deadlineDurationMs ?? Int((recorder.currentTime * 1000).rounded())
        recorder.stop()
        deadlineTask?.cancel()
        deadlineTask = nil
        self.recorder = nil
        self.fileURL = nil
        deadlineDurationMs = nil
        let audioBytes = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        Self.logger.info(
            "Recorder stopped durationMs=\(durationMs, privacy: .public) audioBytes=\(audioBytes, privacy: .public) file=\(fileURL.lastPathComponent, privacy: .public)"
        )

        return RecordedAudio(
            fileURL: fileURL,
            durationMs: durationMs
        )
    }

    func cancelRecording() throws {
        guard let recorder, let fileURL else {
            throw RecorderError.noActiveRecording
        }

        recorder.stop()
        deadlineTask?.cancel()
        deadlineTask = nil
        self.recorder = nil
        self.fileURL = nil
        deadlineDurationMs = nil
        try? fileManager.removeItem(at: fileURL)
        Self.logger.info("Recorder cancelled and discarded file=\(fileURL.lastPathComponent, privacy: .public)")
    }

    func currentLevel() -> CGFloat? {
        guard let recorder else {
            return nil
        }

        recorder.updateMeters()
        return WaveformNormalizer.normalizedLevel(
            fromAveragePower: recorder.averagePower(forChannel: 0)
        )
    }

    func configure(maxDurationSeconds: Int) {
        self.maxDurationSeconds = maxDurationSeconds
    }
}

private final class AVAudioRecorderSession: RecordingSessionControlling, @unchecked Sendable {
    private let recorder: AVAudioRecorder

    init(url: URL, settings: [String: Any]) throws {
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        self.recorder = recorder
    }

    func prepareToRecord() -> Bool {
        recorder.prepareToRecord()
    }

    func record() -> Bool {
        recorder.record()
    }

    func stop() {
        recorder.stop()
    }

    func updateMeters() {
        recorder.updateMeters()
    }

    func averagePower(forChannel channelNumber: Int) -> Float {
        recorder.averagePower(forChannel: channelNumber)
    }

    var currentTime: TimeInterval {
        recorder.currentTime
    }
}
