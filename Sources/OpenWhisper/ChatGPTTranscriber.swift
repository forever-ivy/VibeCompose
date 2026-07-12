import Foundation
import OSLog

private enum TranscriptionUploadLimit {
    static let maxBytes = 25_000_000
    static let label = "25 MB"
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
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? ProductIdentity.defaultBundleIdentifier,
        category: "Transcription"
    )

    let authManager: any ChatGPTAuthProviding
    let config: TranscriptionConfig
    let promptBuilder: TranscriptionPromptBuilder
    let bridgePromptCapability: BridgePromptCapabilityStore
    let cloudflareChallengeMaxAttempts: Int
    let dataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(
        authManager: any ChatGPTAuthProviding,
        config: TranscriptionConfig,
        promptBuilder: TranscriptionPromptBuilder = .init(),
        bridgePromptCapability: BridgePromptCapabilityStore = .shared,
        cloudflareChallengeMaxAttempts: Int = 3,
        dataLoader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await SecureHTTPClient.data(for: request)
        }
    ) {
        self.authManager = authManager
        self.config = config
        self.promptBuilder = promptBuilder
        self.bridgePromptCapability = bridgePromptCapability
        self.cloudflareChallengeMaxAttempts = max(1, cloudflareChallengeMaxAttempts)
        self.dataLoader = dataLoader
    }

    func transcribe(_ audio: RecordedAudio) async throws -> TranscriptionResult {
        let data = try Data(contentsOf: audio.fileURL)
        Self.logger.info(
            "Transcription requested provider=\(config.provider.rawValue, privacy: .public) durationMs=\(audio.durationMs, privacy: .public) audioBytes=\(data.count, privacy: .public)"
        )
        guard !data.isEmpty else {
            Self.logger.error("Transcription rejected because the audio file was empty")
            throw TranscriptionError.invalidAudio
        }
        guard data.count <= TranscriptionUploadLimit.maxBytes else {
            Self.logger.error("Transcription rejected because audioBytes=\(data.count, privacy: .public) exceeded upload limit")
            throw TranscriptionError.payloadTooLarge
        }

        let prompt = promptBuilder.buildPrompt(
            hintTerms: config.promptHintTerms,
            speechCleanupEnabled: config.speechCleanupEnabled
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
                    audioData: data,
                    token: token,
                    prompt: prompt
                )
            } catch let error as TranscriptionHTTPError where error.shouldRefreshAuthToken {
                Self.logger.info("ChatGPT transcription requested an access-token refresh after HTTP \(error.statusCode, privacy: .public)")
                let refreshStarted = DispatchTime.now().uptimeNanoseconds
                token = try await authManager.refreshAccessToken()
                authMs += elapsedMilliseconds(since: refreshStarted)
                response = try await transcribeViaChatGPTBridgeWithCloudflareRetries(
                    audioData: data,
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
                    audioBytes: data.count,
                    authMs: authMs,
                    transcribeMs: transcribeMs,
                    promptIncluded: response.promptIncluded
                )
            )
        case .openAICompatible:
            let transcribeStarted = DispatchTime.now().uptimeNanoseconds
            let text = try await transcribeViaOpenAICompatible(
                audioData: data,
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
                    audioBytes: data.count,
                    authMs: 0,
                    transcribeMs: transcribeMs,
                    promptIncluded: true
                )
            )
        }
    }

    private func transcribeViaChatGPTBridgeWithCloudflareRetries(
        audioData: Data,
        token: String,
        prompt: String
    ) async throws -> (text: String, promptIncluded: Bool) {
        for attempt in 1...cloudflareChallengeMaxAttempts {
            do {
                Self.logger.info(
                    "ChatGPT transcription HTTP attempt \(attempt, privacy: .public)/\(cloudflareChallengeMaxAttempts, privacy: .public)"
                )
                return try await transcribeViaChatGPTBridge(
                    audioData: audioData,
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
        audioData: Data,
        token: String,
        prompt: String
    ) async throws -> (text: String, promptIncluded: Bool) {
        let capability = bridgePromptCapability.value()
        if capability == false {
            let text = try await executeTranscriptionRequest(
                try makeChatGPTBridgeRequest(
                    audioData: audioData,
                    token: token,
                    prompt: nil
                ),
                providerLabel: "ChatGPT"
            )
            return (text, false)
        }

        do {
            let text = try await executeTranscriptionRequest(
                try makeChatGPTBridgeRequest(
                    audioData: audioData,
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
                try makeChatGPTBridgeRequest(
                    audioData: audioData,
                    token: token,
                    prompt: nil
                ),
                providerLabel: "ChatGPT"
            )
            bridgePromptCapability.mark(false)
            return (fallbackText, false)
        }
    }

    private func makeChatGPTBridgeRequest(
        audioData: Data,
        token: String,
        prompt: String?
    ) throws -> URLRequest {
        let url = try ManagedEndpointPolicy.validatedURL(
            ManagedEndpointPolicy.transcriptionURL,
            for: .transcription
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(makeBoundary())", forHTTPHeaderField: "Content-Type")
        let boundary = request.value(forHTTPHeaderField: "Content-Type")!.split(separator: "=").last.map(String.init) ?? makeBoundary()
        request.httpBody = makeMultipartBody(
            boundary: boundary,
            audioData: audioData,
            extraFields: prompt.map { ["prompt": $0] } ?? [:]
        )
        return request
    }

    private func transcribeViaOpenAICompatible(audioData: Data, prompt: String) async throws -> String {
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
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = makeMultipartBody(
            boundary: boundary,
            audioData: audioData,
            extraFields: [
                "model": config.openAIModel,
                "prompt": prompt,
            ]
        )

        return try await executeTranscriptionRequest(request, providerLabel: "OpenAI-compatible")
    }

    private func openAICompatibleAuthToken() -> String? {
        let token = ProcessInfo.processInfo.environment[config.openAIAuthTokenEnv] ?? ""
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedToken.isEmpty ? nil : trimmedToken
    }

    private func executeTranscriptionRequest(_ request: URLRequest, providerLabel: String) async throws -> String {
        Self.logger.info(
            "Sending \(providerLabel, privacy: .public) transcription request host=\(request.url?.host ?? "unknown", privacy: .public) path=\(request.url?.path ?? "unknown", privacy: .public) bodyBytes=\(request.httpBody?.count ?? 0, privacy: .public)"
        )
        let (responseData, response) = try await dataLoader(request)
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

    private func makeMultipartBody(boundary: String, audioData: Data, extraFields: [String: String]) -> Data {
        var body = Data()
        for (name, value) in extraFields.sorted(by: { $0.key < $1.key }) {
            body.append(contentsOf: "--\(boundary)\r\n".utf8)
            body.append(contentsOf: "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8)
            body.append(contentsOf: "\(value)\r\n".utf8)
        }
        body.append(contentsOf: "--\(boundary)\r\n".utf8)
        body.append(contentsOf: "Content-Disposition: form-data; name=\"file\"; filename=\"voice.wav\"\r\n".utf8)
        body.append(contentsOf: "Content-Type: audio/wav\r\n\r\n".utf8)
        body.append(audioData)
        body.append(contentsOf: "\r\n--\(boundary)--\r\n".utf8)
        return body
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
