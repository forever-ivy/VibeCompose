import Foundation
import OSLog
import Darwin

private enum TranscriptionUploadLimit {
    static let maxBytes = 25_000_000
    static let label = "25 MB"
}

private struct AudioUploadMetadata: Sendable, Equatable {
    let byteCount: Int
    let device: UInt64
    let inode: UInt64

    static func inspect(_ fileURL: URL) throws -> AudioUploadMetadata {
        let descriptor = try openAudioFile(fileURL)
        defer { Darwin.close(descriptor) }
        return try inspect(descriptor)
    }

    static func inspect(_ descriptor: Int32) throws -> AudioUploadMetadata {
        var fileStatus = stat()
        guard Darwin.fstat(descriptor, &fileStatus) == 0 else {
            throw TranscriptionError.invalidAudio
        }
        guard (fileStatus.st_mode & S_IFMT) == S_IFREG else {
            throw TranscriptionError.invalidAudio
        }
        guard fileStatus.st_size > 0 else {
            throw TranscriptionError.invalidAudio
        }
        guard fileStatus.st_size <= off_t(TranscriptionUploadLimit.maxBytes) else {
            throw TranscriptionError.payloadTooLarge
        }

        return AudioUploadMetadata(
            byteCount: Int(fileStatus.st_size),
            device: UInt64(fileStatus.st_dev),
            inode: UInt64(fileStatus.st_ino)
        )
    }

    private static func openAudioFile(_ fileURL: URL) throws -> Int32 {
        let descriptor = fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw TranscriptionError.invalidAudio
        }
        return descriptor
    }
}

private struct MultipartBodyFile: Sendable {
    let fileURL: URL
    let byteCount: Int

    static func create(
        audioFileURL: URL,
        expectedAudioMetadata: AudioUploadMetadata,
        boundary: String,
        extraFields: [String: String],
        temporaryDirectoryURL: URL
    ) async throws -> MultipartBodyFile {
        let worker = Task.detached(priority: .utility) {
            try createSynchronously(
                audioFileURL: audioFileURL,
                expectedAudioMetadata: expectedAudioMetadata,
                boundary: boundary,
                extraFields: extraFields,
                temporaryDirectoryURL: temporaryDirectoryURL
            )
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func createSynchronously(
        audioFileURL: URL,
        expectedAudioMetadata: AudioUploadMetadata,
        boundary: String,
        extraFields: [String: String],
        temporaryDirectoryURL: URL
    ) throws -> MultipartBodyFile {
        let inputDescriptor = try openAudioFile(audioFileURL)
        defer { Darwin.close(inputDescriptor) }

        let currentMetadata = try AudioUploadMetadata.inspect(inputDescriptor)
        guard currentMetadata == expectedAudioMetadata else {
            throw TranscriptionError.invalidAudio
        }

        let bodyFileURL = temporaryDirectoryURL
            .appendingPathComponent("vibewhisper-upload-\(UUID().uuidString).multipart")
        let outputDescriptor = try createPrivateOutputFile(bodyFileURL)
        var shouldDeleteOutput = true
        defer {
            Darwin.close(outputDescriptor)
            if shouldDeleteOutput {
                try? FileManager.default.removeItem(at: bodyFileURL)
            }
        }

        for (name, value) in extraFields.sorted(by: { $0.key < $1.key }) {
            try write(
                Data(
                    (
                        "--\(boundary)\r\n"
                            + "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
                            + "\(value)\r\n"
                    ).utf8
                ),
                to: outputDescriptor
            )
        }
        try write(
            Data(
                (
                    "--\(boundary)\r\n"
                        + "Content-Disposition: form-data; name=\"file\"; filename=\"voice.wav\"\r\n"
                        + "Content-Type: audio/wav\r\n\r\n"
                ).utf8
            ),
            to: outputDescriptor
        )
        try copyAudio(
            from: inputDescriptor,
            to: outputDescriptor,
            byteCount: expectedAudioMetadata.byteCount
        )
        try write(Data("\r\n--\(boundary)--\r\n".utf8), to: outputDescriptor)

        var outputStatus = stat()
        guard Darwin.fstat(outputDescriptor, &outputStatus) == 0, outputStatus.st_size > 0 else {
            throw CocoaError(.fileWriteUnknown)
        }

        shouldDeleteOutput = false
        return MultipartBodyFile(
            fileURL: bodyFileURL,
            byteCount: Int(outputStatus.st_size)
        )
    }

    private static func openAudioFile(_ fileURL: URL) throws -> Int32 {
        let descriptor = fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw TranscriptionError.invalidAudio
        }
        return descriptor
    }

    private static func createPrivateOutputFile(_ fileURL: URL) throws -> Int32 {
        let descriptor = fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(
                path,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        return descriptor
    }

    private static func copyAudio(
        from inputDescriptor: Int32,
        to outputDescriptor: Int32,
        byteCount: Int
    ) throws {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var remaining = byteCount

        while remaining > 0 {
            try Task.checkCancellation()
            let requested = min(remaining, buffer.count)
            let readCount = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(inputDescriptor, rawBuffer.baseAddress, requested)
            }
            if readCount < 0, errno == EINTR {
                continue
            }
            guard readCount > 0 else {
                throw TranscriptionError.invalidAudio
            }
            try buffer.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else {
                    throw TranscriptionError.invalidAudio
                }
                try write(
                    baseAddress: baseAddress,
                    byteCount: readCount,
                    to: outputDescriptor
                )
            }
            remaining -= readCount
        }
    }

    private static func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            try write(
                baseAddress: baseAddress,
                byteCount: rawBuffer.count,
                to: descriptor
            )
        }
    }

    private static func write(
        baseAddress: UnsafeRawPointer,
        byteCount: Int,
        to descriptor: Int32
    ) throws {
        var offset = 0
        while offset < byteCount {
            try Task.checkCancellation()
            let written = Darwin.write(
                descriptor,
                baseAddress.advanced(by: offset),
                byteCount - offset
            )
            if written < 0, errno == EINTR {
                continue
            }
            guard written > 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
            offset += written
        }
    }
}

private struct MultipartUpload: Sendable {
    let request: URLRequest
    let body: MultipartBodyFile
}

enum TranscriptionError: LocalizedError {
    case invalidAudio
    case payloadTooLarge
    case transcriptionFailed(String)
    case invalidResponse
    case missingRecoveryAPIKey
    case recoveryCredentialUnavailable(String)
    case retryableCloudflareChallenge(attempts: Int)
    case invalidEndpoint(String)

    var errorDescription: String? {
        switch self {
        case .invalidAudio:
            return L10n.text("The recording file is invalid.")
        case .payloadTooLarge:
            return L10n.format(
                "The recording exceeds %@, which is above the ChatGPT/OpenAI transcription upload limit. It was not sent.",
                TranscriptionUploadLimit.label
            )
        case .transcriptionFailed(let message):
            return L10n.format("ChatGPT transcription failed: %@", message)
        case .invalidResponse:
            return L10n.text("ChatGPT transcription returned empty text.")
        case .missingRecoveryAPIKey:
            return L10n.text(
                "OpenAI-Compatible Recovery needs an API key saved in Keychain."
            )
        case .recoveryCredentialUnavailable(let detail):
            return L10n.format(
                "VibeWhisper could not read the OpenAI-Compatible API key from Keychain: %@",
                detail
            )
        case .retryableCloudflareChallenge(let attempts):
            return L10n.format(
                "ChatGPT transcription encountered Cloudflare 403 %ld times. This is usually a temporary network issue. The recording was kept; click Retry to try once more.",
                attempts
            )
        case .invalidEndpoint(let message):
            return message
        }
    }
}

struct TranscriptionMetrics: Sendable, Equatable {
    let provider: TranscriptionProvider
    let audioDurationMs: Int
    let audioBytes: Int
    let authMs: Int
    let transcribeMs: Int
    let promptIncluded: Bool
}

struct TranscriptionResult: Sendable, Equatable {
    let text: String
    let metrics: TranscriptionMetrics
}

final class BridgePromptCapabilityStore: @unchecked Sendable {
    static let shared = BridgePromptCapabilityStore()

    private let lock = NSLock()
    private var supportsPrompt: Bool?

    func value() -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return supportsPrompt
    }

    func mark(_ value: Bool) {
        lock.lock()
        supportsPrompt = value
        lock.unlock()
    }
}

struct ChatGPTTranscriber: Sendable {
    typealias UploadLoader = @Sendable (
        URLRequest,
        URL
    ) async throws -> (Data, URLResponse)
    typealias RetrySleeper = @Sendable (Int) async throws -> Void
    typealias RetryJitter = @Sendable () -> Double

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? ProductIdentity.defaultBundleIdentifier,
        category: "Transcription"
    )

    let authManager: any ChatGPTAuthProviding
    let config: TranscriptionConfig
    let promptBuilder: TranscriptionPromptBuilder
    let bridgePromptCapability: BridgePromptCapabilityStore
    let providerCapabilityPolicy: any ProviderCapabilityChecking
    let providerHealthMonitor: any ProviderHealthMonitoring
    let recoveryCredentialStore: any OpenAICompatibleCredentialPersisting
    let cloudflareChallengeMaxAttempts: Int
    let transientFailureMaxAttempts: Int
    let retrySchedule: ProviderRetrySchedule
    let retrySleeper: RetrySleeper
    let retryJitter: RetryJitter
    let multipartTemporaryDirectoryURL: URL
    let uploadLoader: UploadLoader

    init(
        authManager: any ChatGPTAuthProviding,
        config: TranscriptionConfig,
        promptBuilder: TranscriptionPromptBuilder = .init(),
        bridgePromptCapability: BridgePromptCapabilityStore = .shared,
        providerCapabilityPolicy: any ProviderCapabilityChecking = ProviderCapabilityPolicyController.shared,
        providerHealthMonitor: any ProviderHealthMonitoring =
            ProviderHealthMonitor(),
        recoveryCredentialStore: any OpenAICompatibleCredentialPersisting = KeychainOpenAICompatibleCredentialStore(),
        cloudflareChallengeMaxAttempts: Int = 3,
        transientFailureMaxAttempts: Int = 3,
        retrySchedule: ProviderRetrySchedule = .default,
        retrySleeper: @escaping RetrySleeper = { delayMilliseconds in
            try await Task.sleep(
                for: .milliseconds(delayMilliseconds)
            )
        },
        retryJitter: @escaping RetryJitter = {
            Double.random(in: 0...1)
        },
        multipartTemporaryDirectoryURL: URL = FileManager.default.temporaryDirectory,
        uploadLoader: @escaping UploadLoader = { request, bodyFileURL in
            try await SecureHTTPClient.upload(for: request, fromFile: bodyFileURL)
        }
    ) {
        self.authManager = authManager
        self.config = config
        self.promptBuilder = promptBuilder
        self.bridgePromptCapability = bridgePromptCapability
        self.providerCapabilityPolicy = providerCapabilityPolicy
        self.providerHealthMonitor = providerHealthMonitor
        self.recoveryCredentialStore = recoveryCredentialStore
        self.cloudflareChallengeMaxAttempts = max(1, cloudflareChallengeMaxAttempts)
        self.transientFailureMaxAttempts = max(
            1,
            transientFailureMaxAttempts
        )
        self.retrySchedule = retrySchedule
        self.retrySleeper = retrySleeper
        self.retryJitter = retryJitter
        self.multipartTemporaryDirectoryURL = multipartTemporaryDirectoryURL
        self.uploadLoader = uploadLoader
    }

    func transcribe(_ audio: RecordedAudio) async throws -> TranscriptionResult {
        if config.provider == .chatGPTManagedAuth {
            try await providerCapabilityPolicy.require(.managedTranscription)
        }

        let audioMetadata = try await inspectAudioFile(at: audio.fileURL)
        Self.logger.info(
            "Transcription requested provider=\(config.provider.rawValue, privacy: .public) durationMs=\(audio.durationMs, privacy: .public) audioBytes=\(audioMetadata.byteCount, privacy: .public)"
        )

        let prompt = promptBuilder.buildPrompt(
            hintTerms: config.promptHintTerms,
            speechCleanupEnabled: config.speechCleanupEnabled,
            punctuationPreference: config.punctuationPreference
        )

        switch config.provider {
        case .chatGPTManagedAuth:
            do {
                return try await transcribeViaChatGPTManagedAuth(
                    audio: audio,
                    audioMetadata: audioMetadata,
                    prompt: prompt
                )
            } catch {
                if shouldFallbackToOpenAICompatible(after: error) {
                    Self.logger.info(
                        "ChatGPT transcription failed; attempting OpenAI-compatible fallback"
                    )
                    return try await transcribeViaOpenAICompatibleResult(
                        audio: audio,
                        audioMetadata: audioMetadata,
                        prompt: prompt
                    )
                }
                throw error
            }
        case .openAICompatible:
            return try await transcribeViaOpenAICompatibleResult(
                audio: audio,
                audioMetadata: audioMetadata,
                prompt: prompt
            )
        }
    }

    private func transcribeViaChatGPTManagedAuth(
        audio: RecordedAudio,
        audioMetadata: AudioUploadMetadata,
        prompt: String
    ) async throws -> TranscriptionResult {
        let authStarted = DispatchTime.now().uptimeNanoseconds
        var token = try await authManager.bestAvailableAccessToken()
        var authMs = elapsedMilliseconds(since: authStarted)
        Self.logger.info("ChatGPT access token resolved authMs=\(authMs, privacy: .public)")
        let transcribeStarted = DispatchTime.now().uptimeNanoseconds
        let response: (text: String, promptIncluded: Bool)
        do {
            response = try await transcribeViaChatGPTBridgeWithCloudflareRetries(
                audioFileURL: audio.fileURL,
                audioMetadata: audioMetadata,
                token: token,
                prompt: prompt
            )
        } catch let error as ProviderRequestFailure
            where error.shouldRefreshAuthentication
        {
            Self.logger.info(
                "ChatGPT transcription requested an access-token refresh after HTTP \(error.statusCode ?? 0, privacy: .public)"
            )
            let refreshStarted = DispatchTime.now().uptimeNanoseconds
            token = try await authManager.refreshAccessToken()
            authMs += elapsedMilliseconds(since: refreshStarted)
            response = try await transcribeViaChatGPTBridgeWithCloudflareRetries(
                audioFileURL: audio.fileURL,
                audioMetadata: audioMetadata,
                token: token,
                prompt: prompt
            )
        }
        let transcribeMs = elapsedMilliseconds(since: transcribeStarted)
        Self.logger.info(
            "ChatGPT transcription completed transcribeMs=\(transcribeMs, privacy: .public) transcriptCharacters=\(response.text.count, privacy: .public) promptIncluded=\(response.promptIncluded, privacy: .public)"
        )
        return TranscriptionResult(
            text: response.text,
            metrics: TranscriptionMetrics(
                provider: .chatGPTManagedAuth,
                audioDurationMs: audio.durationMs,
                audioBytes: audioMetadata.byteCount,
                authMs: authMs,
                transcribeMs: transcribeMs,
                promptIncluded: response.promptIncluded
            )
        )
    }

    private func transcribeViaOpenAICompatibleResult(
        audio: RecordedAudio,
        audioMetadata: AudioUploadMetadata,
        prompt: String
    ) async throws -> TranscriptionResult {
        let transcribeStarted = DispatchTime.now().uptimeNanoseconds
        let text = try await transcribeViaOpenAICompatible(
            audioFileURL: audio.fileURL,
            audioMetadata: audioMetadata,
            prompt: prompt
        )
        let transcribeMs = elapsedMilliseconds(since: transcribeStarted)
        Self.logger.info(
            "OpenAI-compatible transcription completed transcribeMs=\(transcribeMs, privacy: .public) transcriptCharacters=\(text.count, privacy: .public)"
        )
        return TranscriptionResult(
            text: text,
            metrics: TranscriptionMetrics(
                provider: .openAICompatible,
                audioDurationMs: audio.durationMs,
                audioBytes: audioMetadata.byteCount,
                authMs: 0,
                transcribeMs: transcribeMs,
                promptIncluded: true
            )
        )
    }

    /// Whether ChatGPT ASR failure may escalate to the user-owned OpenAI path.
    private func shouldFallbackToOpenAICompatible(after error: any Error) -> Bool {
        guard config.openAIFallbackEnabled else {
            return false
        }
        guard config.provider == .chatGPTManagedAuth else {
            return false
        }
        // Local / client errors must not silently switch providers.
        if error is TranscriptionError {
            return false
        }
        if error is CancellationError {
            return false
        }
        if let failure = error as? ProviderRequestFailure {
            switch failure.category {
            case .network,
                 .serviceUnavailable,
                 .rateLimited,
                 .challenge,
                 .authentication,
                 .unknown:
                break
            case .requestRejected, .contractChanged, .invalidResponse:
                return false
            }
        }
        // Credential check is best-effort; missing key fails inside openAI path.
        let hasKey = (try? recoveryCredentialStore.hasAPIKey()) ?? false
        return hasKey
    }

    private func transcribeViaChatGPTBridgeWithCloudflareRetries(
        audioFileURL: URL,
        audioMetadata: AudioUploadMetadata,
        token: String,
        prompt: String
    ) async throws -> (text: String, promptIncluded: Bool) {
        for attempt in 1...cloudflareChallengeMaxAttempts {
            do {
                Self.logger.info(
                    "ChatGPT transcription HTTP attempt \(attempt, privacy: .public)/\(cloudflareChallengeMaxAttempts, privacy: .public)"
                )
                return try await transcribeViaChatGPTBridge(
                    audioFileURL: audioFileURL,
                    audioMetadata: audioMetadata,
                    token: token,
                    prompt: prompt
                )
            } catch let error as ProviderRequestFailure
                where error.category == .challenge
            {
                Self.logger.error(
                    "ChatGPT transcription attempt \(attempt, privacy: .public) hit upstream challenge HTTP \(error.statusCode ?? 0, privacy: .public)"
                )
                if attempt == cloudflareChallengeMaxAttempts {
                    throw TranscriptionError.retryableCloudflareChallenge(
                        attempts: cloudflareChallengeMaxAttempts
                    )
                }
                try await sleepBeforeRetry(afterFailedAttempt: attempt)
            }
        }

        throw TranscriptionError.retryableCloudflareChallenge(
            attempts: cloudflareChallengeMaxAttempts
        )
    }

    private func transcribeViaChatGPTBridge(
        audioFileURL: URL,
        audioMetadata: AudioUploadMetadata,
        token: String,
        prompt: String
    ) async throws -> (text: String, promptIncluded: Bool) {
        let capability = bridgePromptCapability.value()
        if capability == false {
            let text = try await executeTranscriptionRequest(
                try await makeChatGPTBridgeUpload(
                    audioFileURL: audioFileURL,
                    audioMetadata: audioMetadata,
                    token: token,
                    prompt: nil
                ),
                providerLabel: "ChatGPT",
                route: .managedTranscription
            )
            return (text, false)
        }

        do {
            let text = try await executeTranscriptionRequest(
                try await makeChatGPTBridgeUpload(
                    audioFileURL: audioFileURL,
                    audioMetadata: audioMetadata,
                    token: token,
                    prompt: prompt
                ),
                providerLabel: "ChatGPT",
                route: .managedTranscription
            )
            bridgePromptCapability.mark(true)
            return (text, true)
        } catch let error as ProviderRequestFailure
            where error.shouldRefreshAuthentication
                || error.category == .challenge
        {
            throw error
        } catch let error as ProviderRequestFailure
            where !error.permitsPromptFallback
        {
            throw error
        } catch {
            let fallbackText = try await executeTranscriptionRequest(
                try await makeChatGPTBridgeUpload(
                    audioFileURL: audioFileURL,
                    audioMetadata: audioMetadata,
                    token: token,
                    prompt: nil
                ),
                providerLabel: "ChatGPT",
                route: .managedTranscription
            )
            bridgePromptCapability.mark(false)
            return (fallbackText, false)
        }
    }

    private func makeChatGPTBridgeUpload(
        audioFileURL: URL,
        audioMetadata: AudioUploadMetadata,
        token: String,
        prompt: String?
    ) async throws -> MultipartUpload {
        let url = try ManagedEndpointPolicy.validatedURL(
            ManagedEndpointPolicy.transcriptionURL,
            for: .transcription
        )
        let boundary = makeBoundary()
        let body = try await MultipartBodyFile.create(
            audioFileURL: audioFileURL,
            expectedAudioMetadata: audioMetadata,
            boundary: boundary,
            extraFields: prompt.map { ["prompt": $0] } ?? [:],
            temporaryDirectoryURL: multipartTemporaryDirectoryURL
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.byteCount), forHTTPHeaderField: "Content-Length")
        return MultipartUpload(request: request, body: body)
    }

    private func transcribeViaOpenAICompatible(
        audioFileURL: URL,
        audioMetadata: AudioUploadMetadata,
        prompt: String
    ) async throws -> String {
        let token = try openAICompatibleAuthToken()

        let boundary = makeBoundary()
        let endpoint: URL
        do {
            endpoint = try ManagedEndpointPolicy.validatedUserOwnedURL(config.openAITranscriptionURL)
        } catch {
            throw TranscriptionError.invalidEndpoint(error.localizedDescription)
        }
        let body = try await MultipartBodyFile.create(
            audioFileURL: audioFileURL,
            expectedAudioMetadata: audioMetadata,
            boundary: boundary,
            extraFields: [
                "model": config.openAIModel,
                "prompt": prompt,
            ],
            temporaryDirectoryURL: multipartTemporaryDirectoryURL
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.byteCount), forHTTPHeaderField: "Content-Length")

        return try await executeTranscriptionRequest(
            MultipartUpload(request: request, body: body),
            providerLabel: "OpenAI-compatible",
            route: .recoveryTranscription
        )
    }

    private func openAICompatibleAuthToken() throws -> String {
        do {
            guard let token = try recoveryCredentialStore.loadAPIKey() else {
                throw TranscriptionError.missingRecoveryAPIKey
            }
            return token
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.recoveryCredentialUnavailable(
                error.localizedDescription
            )
        }
    }

    private func executeTranscriptionRequest(
        _ upload: MultipartUpload,
        providerLabel: String,
        route: ProviderRoute
    ) async throws -> String {
        defer {
            try? FileManager.default.removeItem(at: upload.body.fileURL)
        }

        var attempt = 1
        while true {
            do {
                return try await executeSingleTranscriptionRequest(
                    upload,
                    providerLabel: providerLabel,
                    route: route
                )
            } catch let failure as ProviderRequestFailure {
                let reportedFailure = failure.withAttempts(attempt)
                guard
                    !failure.circuitOpen,
                    failure.isAutomaticallyRetryable,
                    attempt < transientFailureMaxAttempts
                else {
                    throw reportedFailure
                }

                Self.logger.error(
                    "\(providerLabel, privacy: .public) transcription transient failure category=\(failure.category.rawValue, privacy: .public) attempt=\(attempt, privacy: .public)/\(transientFailureMaxAttempts, privacy: .public)"
                )
                try await sleepBeforeRetry(afterFailedAttempt: attempt)
                attempt += 1
            }
        }
    }

    private func executeSingleTranscriptionRequest(
        _ upload: MultipartUpload,
        providerLabel: String,
        route: ProviderRoute
    ) async throws -> String {
        let request = upload.request
        try await providerHealthMonitor.requireRequestPermission(for: route)
        Self.logger.info(
            "Sending \(providerLabel, privacy: .public) transcription request host=\(request.url?.host ?? "unknown", privacy: .public) path=\(request.url?.path ?? "unknown", privacy: .public) bodyBytes=\(upload.body.byteCount, privacy: .public)"
        )

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await uploadLoader(
                request,
                upload.body.fileURL
            )
        } catch is CancellationError {
            await providerHealthMonitor.recordCancellation(for: route)
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            await providerHealthMonitor.recordCancellation(for: route)
            throw CancellationError()
        } catch {
            let failure = ProviderFailureClassifier.network(route: route)
            await providerHealthMonitor.recordFailure(failure)
            throw failure
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            Self.logger.error("\(providerLabel, privacy: .public) transcription response was not HTTP")
            let failure = ProviderFailureClassifier.invalidResponse(
                route: route
            )
            await providerHealthMonitor.recordFailure(failure)
            throw failure
        }
        Self.logger.info(
            "\(providerLabel, privacy: .public) transcription response status=\(httpResponse.statusCode, privacy: .public) responseBytes=\(responseData.count, privacy: .public)"
        )

        guard (200..<300).contains(httpResponse.statusCode) else {
            Self.logger.error(
                "\(providerLabel, privacy: .public) transcription failed status=\(httpResponse.statusCode, privacy: .public) contentType=\(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown", privacy: .public) server=\(httpResponse.value(forHTTPHeaderField: "Server") ?? "unknown", privacy: .public)"
            )
            let failure = ProviderFailureClassifier.http(
                route: route,
                response: httpResponse,
                bodyPrefix: String(data: responseData.prefix(512), encoding: .utf8)
            )
            await providerHealthMonitor.recordFailure(failure)
            throw failure
        }

        let object = try? JSONSerialization
            .jsonObject(with: responseData) as? [String: Any]
        if let text = object?["text"] as? String, !text.isEmpty {
            await providerHealthMonitor.recordSuccess(for: route)
            return text
        }
        if let text = object?["transcript"] as? String, !text.isEmpty {
            await providerHealthMonitor.recordSuccess(for: route)
            return text
        }

        let failure = ProviderFailureClassifier.invalidResponse(route: route)
        await providerHealthMonitor.recordFailure(failure)
        throw failure
    }

    private func sleepBeforeRetry(
        afterFailedAttempt attempt: Int
    ) async throws {
        let delay = retrySchedule.delayMilliseconds(
            afterFailedAttempt: attempt,
            jitterUnit: retryJitter()
        )
        guard delay > 0 else {
            return
        }
        try await retrySleeper(delay)
    }

    private func makeBoundary() -> String {
        "VibeWhisper-\(UUID().uuidString)"
    }

    private func inspectAudioFile(at fileURL: URL) async throws -> AudioUploadMetadata {
        let worker = Task.detached(priority: .utility) {
            try AudioUploadMetadata.inspect(fileURL)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private func elapsedMilliseconds(since start: UInt64) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
}

extension ChatGPTTranscriber: Transcriber {}
