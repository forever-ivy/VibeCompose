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
            .appendingPathComponent("openwhisper-upload-\(UUID().uuidString).multipart")
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
    case missingAuthTokenEnv(String)
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
        case .missingAuthTokenEnv(let envName):
            return L10n.format("Missing transcription API key. Set environment variable %@.", envName)
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

private struct TranscriptionHTTPError: LocalizedError {
    let providerLabel: String
    let statusCode: Int
    let message: String
    let contentType: String?
    let server: String?
    let bodyPrefix: String?

    var isAuthFailure: Bool {
        statusCode == 401 || statusCode == 403
    }

    var shouldRefreshAuthToken: Bool {
        isAuthFailure && !isCloudflareChallenge
    }

    var canRetryWithoutPrompt: Bool {
        statusCode == 400 || statusCode == 422
    }

    var isCloudflareChallenge: Bool {
        guard statusCode == 403 else {
            return false
        }

        let lowerContentType = contentType?.lowercased() ?? ""
        let lowerServer = server?.lowercased() ?? ""
        let lowerBodyPrefix = bodyPrefix?.lowercased() ?? ""
        return lowerServer.contains("cloudflare")
            || lowerContentType.contains("text/html")
            || lowerBodyPrefix.contains("<html")
            || lowerBodyPrefix.contains("cloudflare")
    }

    var errorDescription: String? {
        if isCloudflareChallenge {
            return L10n.format(
                "%@ transcription failed because the private transcription endpoint returned a Cloudflare 403 challenge. This is not an expired OpenWhisper session.",
                providerLabel
            )
        }

        return L10n.format("%@ transcription failed: %@", providerLabel, message)
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

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? ProductIdentity.defaultBundleIdentifier,
        category: "Transcription"
    )

    let authManager: any ChatGPTAuthProviding
    let config: TranscriptionConfig
    let promptBuilder: TranscriptionPromptBuilder
    let bridgePromptCapability: BridgePromptCapabilityStore
    let cloudflareChallengeMaxAttempts: Int
    let multipartTemporaryDirectoryURL: URL
    let uploadLoader: UploadLoader

    init(
        authManager: any ChatGPTAuthProviding,
        config: TranscriptionConfig,
        promptBuilder: TranscriptionPromptBuilder = .init(),
        bridgePromptCapability: BridgePromptCapabilityStore = .shared,
        cloudflareChallengeMaxAttempts: Int = 3,
        multipartTemporaryDirectoryURL: URL = FileManager.default.temporaryDirectory,
        uploadLoader: @escaping UploadLoader = { request, bodyFileURL in
            try await SecureHTTPClient.upload(for: request, fromFile: bodyFileURL)
        }
    ) {
        self.authManager = authManager
        self.config = config
        self.promptBuilder = promptBuilder
        self.bridgePromptCapability = bridgePromptCapability
        self.cloudflareChallengeMaxAttempts = max(1, cloudflareChallengeMaxAttempts)
        self.multipartTemporaryDirectoryURL = multipartTemporaryDirectoryURL
        self.uploadLoader = uploadLoader
    }

    func transcribe(_ audio: RecordedAudio) async throws -> TranscriptionResult {
        let audioMetadata = try await inspectAudioFile(at: audio.fileURL)
        Self.logger.info(
            "Transcription requested provider=\(config.provider.rawValue, privacy: .public) durationMs=\(audio.durationMs, privacy: .public) audioBytes=\(audioMetadata.byteCount, privacy: .public)"
        )

        let prompt = promptBuilder.buildPrompt(
            hintTerms: config.promptHintTerms,
            speechCleanupEnabled: config.speechCleanupEnabled,
            languagePreference: config.languagePreference,
            punctuationPreference: config.punctuationPreference
        )

        switch config.provider {
        case .chatGPTManagedAuth:
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
            } catch let error as TranscriptionHTTPError where error.shouldRefreshAuthToken {
                Self.logger.info("ChatGPT transcription requested an access-token refresh after HTTP \(error.statusCode, privacy: .public)")
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
        case .openAICompatible:
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
            } catch let error as TranscriptionHTTPError where error.isCloudflareChallenge {
                Self.logger.error(
                    "ChatGPT transcription attempt \(attempt, privacy: .public) hit Cloudflare HTTP \(error.statusCode, privacy: .public)"
                )
                if attempt == cloudflareChallengeMaxAttempts {
                    throw TranscriptionError.retryableCloudflareChallenge(
                        attempts: cloudflareChallengeMaxAttempts
                    )
                }
                continue
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
                providerLabel: "ChatGPT"
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
                providerLabel: "ChatGPT"
            )
            bridgePromptCapability.mark(true)
            return (text, true)
        } catch let error as TranscriptionHTTPError where error.shouldRefreshAuthToken || error.isCloudflareChallenge {
            throw error
        } catch let error as TranscriptionHTTPError where !error.canRetryWithoutPrompt {
            throw error
        } catch {
            let fallbackText = try await executeTranscriptionRequest(
                try await makeChatGPTBridgeUpload(
                    audioFileURL: audioFileURL,
                    audioMetadata: audioMetadata,
                    token: token,
                    prompt: nil
                ),
                providerLabel: "ChatGPT"
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
        guard let token = openAICompatibleAuthToken() else {
            throw TranscriptionError.missingAuthTokenEnv(config.openAIAuthTokenEnv)
        }

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
            providerLabel: "OpenAI-compatible"
        )
    }

    private func openAICompatibleAuthToken() -> String? {
        let token = ProcessInfo.processInfo.environment[config.openAIAuthTokenEnv] ?? ""
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedToken.isEmpty ? nil : trimmedToken
    }

    private func executeTranscriptionRequest(
        _ upload: MultipartUpload,
        providerLabel: String
    ) async throws -> String {
        defer {
            try? FileManager.default.removeItem(at: upload.body.fileURL)
        }
        let request = upload.request
        Self.logger.info(
            "Sending \(providerLabel, privacy: .public) transcription request host=\(request.url?.host ?? "unknown", privacy: .public) path=\(request.url?.path ?? "unknown", privacy: .public) bodyBytes=\(upload.body.byteCount, privacy: .public)"
        )
        let (responseData, response) = try await uploadLoader(
            request,
            upload.body.fileURL
        )
        guard let httpResponse = response as? HTTPURLResponse else {
            Self.logger.error("\(providerLabel, privacy: .public) transcription response was not HTTP")
            throw TranscriptionError.transcriptionFailed("\(providerLabel) missing HTTP response")
        }
        Self.logger.info(
            "\(providerLabel, privacy: .public) transcription response status=\(httpResponse.statusCode, privacy: .public) responseBytes=\(responseData.count, privacy: .public)"
        )

        guard (200..<300).contains(httpResponse.statusCode) else {
            let providerMessage = decodeProviderMessage(from: responseData) ?? "status \(httpResponse.statusCode)"
            Self.logger.error(
                "\(providerLabel, privacy: .public) transcription failed status=\(httpResponse.statusCode, privacy: .public) contentType=\(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown", privacy: .public) server=\(httpResponse.value(forHTTPHeaderField: "Server") ?? "unknown", privacy: .public)"
            )
            throw TranscriptionHTTPError(
                providerLabel: providerLabel,
                statusCode: httpResponse.statusCode,
                message: providerMessage,
                contentType: httpResponse.value(forHTTPHeaderField: "Content-Type"),
                server: httpResponse.value(forHTTPHeaderField: "Server"),
                bodyPrefix: String(data: responseData.prefix(512), encoding: .utf8)
            )
        }

        let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        if let text = object?["text"] as? String, !text.isEmpty {
            return text
        }
        if let text = object?["transcript"] as? String, !text.isEmpty {
            return text
        }

        throw TranscriptionError.invalidResponse
    }

    private func makeBoundary() -> String {
        "OpenWhisper-\(UUID().uuidString)"
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

    private func decodeProviderMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return object["message"] as? String
    }

    private func elapsedMilliseconds(since start: UInt64) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
}

extension ChatGPTTranscriber: Transcriber {}
