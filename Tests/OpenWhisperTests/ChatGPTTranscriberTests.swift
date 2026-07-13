import Foundation
import Testing
@testable import OpenWhisper

private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requestURLs: [String] = []
    private(set) var requestBodies: [String] = []
    private(set) var authorizationHeaders: [String] = []

    func append(_ request: URLRequest, body: String, authorizationHeader: String? = nil) {
        lock.lock()
        requestURLs.append(request.url?.absoluteString ?? "")
        requestBodies.append(body)
        authorizationHeaders.append(authorizationHeader ?? "")
        lock.unlock()
    }

    func urls() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return requestURLs
    }

    func bodies() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return requestBodies
    }

    func authorizations() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return authorizationHeaders
    }
}

private final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    func current() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class UploadObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var bodyFileURL: URL?
    private var requestHadInMemoryBody = false
    private var declaredContentLength: Int?
    private var observedBodyBytes: Int?
    private var observedPermissions: Int?

    func record(request: URLRequest, bodyFileURL: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: bodyFileURL.path)
        lock.lock()
        self.bodyFileURL = bodyFileURL
        requestHadInMemoryBody = request.httpBody != nil || request.httpBodyStream != nil
        declaredContentLength = request
            .value(forHTTPHeaderField: "Content-Length")
            .flatMap(Int.init)
        observedBodyBytes = (attributes[.size] as? NSNumber)?.intValue
        observedPermissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        lock.unlock()
    }

    func snapshot() -> (
        bodyFileURL: URL?,
        requestHadInMemoryBody: Bool,
        declaredContentLength: Int?,
        observedBodyBytes: Int?,
        observedPermissions: Int?
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (
            bodyFileURL,
            requestHadInMemoryBody,
            declaredContentLength,
            observedBodyBytes,
            observedPermissions
        )
    }
}

private final class UploadURLCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        values.append(url)
        lock.unlock()
    }

    func urls() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private func makeAudioFixture(
    named name: String = UUID().uuidString,
    byteCount: Int? = nil
) throws -> RecordedAudio {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).wav")
    if let byteCount {
        try Data(repeating: 0x2A, count: byteCount).write(to: url)
    } else {
        try Data("fake-audio".utf8).write(to: url)
    }
    return RecordedAudio(fileURL: url, durationMs: 1_000)
}

private func makeSparseAudioFixture(byteCount: UInt64) throws -> RecordedAudio {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).wav")
    FileManager.default.createFile(atPath: url.path, contents: Data([0x2A]))
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: byteCount)
    try handle.close()
    return RecordedAudio(fileURL: url, durationMs: 1_000)
}

private func uploadBodyString(at fileURL: URL) throws -> String {
    String(data: try Data(contentsOf: fileURL), encoding: .utf8) ?? ""
}

@Test
func managedAuthSendsAudioAboveLegacyTenMegabyteLimit() async throws {
    var config = AppConfig().transcription
    config.provider = .chatGPTManagedAuth

    let capture = RequestCapture()
    let transcriber = ChatGPTTranscriber(
        authManager: FakeChatGPTAuthManager(),
        config: config,
        bridgePromptCapability: BridgePromptCapabilityStore(),
        uploadLoader: { request, bodyFileURL in
            let body = try uploadBodyString(at: bodyFileURL)
            capture.append(request, body: body)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"text":"large audio transcript"}"#.utf8), response)
        }
    )

    let byteCount = 10 * 1024 * 1024 + 1
    let audio = try makeAudioFixture(byteCount: byteCount)
    defer { try? FileManager.default.removeItem(at: audio.fileURL) }
    let result = try await transcriber.transcribe(audio)

    #expect(result.text == "large audio transcript")
    #expect(result.metrics.audioBytes == byteCount)
    #expect(capture.bodies().count == 1)
}

@Test
func rejectsAudioAboveOfficialTwentyFiveMegabyteLimit() async throws {
    var config = AppConfig().transcription
    config.provider = .chatGPTManagedAuth

    let transcriber = ChatGPTTranscriber(
        authManager: FakeChatGPTAuthManager(),
        config: config,
        bridgePromptCapability: BridgePromptCapabilityStore(),
        uploadLoader: { _, _ in
            Issue.record("Oversized audio should be rejected before a network request")
            throw URLError(.badServerResponse)
        }
    )

    let audio = try makeSparseAudioFixture(byteCount: 25_000_001)
    defer { try? FileManager.default.removeItem(at: audio.fileURL) }
    var caughtError: Error?
    do {
        _ = try await transcriber.transcribe(audio)
    } catch {
        caughtError = error
    }

    #expect(caughtError?.localizedDescription.contains("25 MB") == true)
}

@Test
func transcriptionStreamsPrivateMultipartFileAndRemovesItAfterUpload() async throws {
    var config = AppConfig().transcription
    config.provider = .chatGPTManagedAuth
    config.hintTerms = ["OpenWhisper"]

    let observation = UploadObservation()
    let transcriber = ChatGPTTranscriber(
        authManager: FakeChatGPTAuthManager(),
        config: config,
        bridgePromptCapability: BridgePromptCapabilityStore(),
        uploadLoader: { request, bodyFileURL in
            try observation.record(request: request, bodyFileURL: bodyFileURL)
            let body = try uploadBodyString(at: bodyFileURL)
            #expect(body.contains("name=\"prompt\""))
            #expect(body.contains("name=\"file\""))
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"text":"streamed"}"#.utf8), response)
        }
    )

    let audio = try makeAudioFixture()
    defer { try? FileManager.default.removeItem(at: audio.fileURL) }
    let result = try await transcriber.transcribe(audio)
    let snapshot = observation.snapshot()

    #expect(result.text == "streamed")
    #expect(snapshot.requestHadInMemoryBody == false)
    #expect(snapshot.declaredContentLength == snapshot.observedBodyBytes)
    #expect(snapshot.observedPermissions == 0o600)
    #expect(snapshot.bodyFileURL.map { !FileManager.default.fileExists(atPath: $0.path) } == true)
}

@Test
func multipartCreationFailureDoesNotSendNetworkRequestOrLeavePartialFile() async throws {
    var config = AppConfig().transcription
    config.provider = .chatGPTManagedAuth

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let missingDirectory = root.appendingPathComponent("missing", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let capability = BridgePromptCapabilityStore()
    capability.mark(false)
    let uploadAttempts = AttemptCounter()
    let transcriber = ChatGPTTranscriber(
        authManager: FakeChatGPTAuthManager(),
        config: config,
        bridgePromptCapability: capability,
        multipartTemporaryDirectoryURL: missingDirectory,
        uploadLoader: { _, _ in
            _ = uploadAttempts.next()
            Issue.record("Multipart creation failure should happen before network upload")
            throw URLError(.badServerResponse)
        }
    )

    let audio = try makeAudioFixture()
    defer { try? FileManager.default.removeItem(at: audio.fileURL) }

    await #expect(throws: CocoaError.self) {
        _ = try await transcriber.transcribe(audio)
    }

    #expect(uploadAttempts.current() == 0)
    #expect(!FileManager.default.fileExists(atPath: missingDirectory.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}

@Test
func uploadFailureRemovesMultipartTemporaryFile() async throws {
    var config = AppConfig().transcription
    config.provider = .chatGPTManagedAuth

    let capability = BridgePromptCapabilityStore()
    capability.mark(false)
    let capture = UploadURLCapture()
    let transcriber = ChatGPTTranscriber(
        authManager: FakeChatGPTAuthManager(),
        config: config,
        bridgePromptCapability: capability,
        uploadLoader: { _, bodyFileURL in
            capture.append(bodyFileURL)
            #expect(FileManager.default.fileExists(atPath: bodyFileURL.path))
            throw URLError(.networkConnectionLost)
        }
    )

    let audio = try makeAudioFixture()
    defer { try? FileManager.default.removeItem(at: audio.fileURL) }

    await #expect(throws: URLError.self) {
        _ = try await transcriber.transcribe(audio)
    }

    let uploadedFiles = capture.urls()
    #expect(uploadedFiles.count == 1)
    #expect(uploadedFiles.allSatisfy {
        !FileManager.default.fileExists(atPath: $0.path)
    })
}

@Test
func rejectsSymlinkedAudioBeforeBuildingMultipartUpload() async throws {
    var config = AppConfig().transcription
    config.provider = .chatGPTManagedAuth

    let target = try makeAudioFixture()
    defer { try? FileManager.default.removeItem(at: target.fileURL) }
    let symlinkURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).wav")
    try FileManager.default.createSymbolicLink(
        at: symlinkURL,
        withDestinationURL: target.fileURL
    )
    defer { try? FileManager.default.removeItem(at: symlinkURL) }

    let transcriber = ChatGPTTranscriber(
        authManager: FakeChatGPTAuthManager(),
        config: config,
        bridgePromptCapability: BridgePromptCapabilityStore(),
        uploadLoader: { _, _ in
            Issue.record("Symlinked audio should be rejected before upload")
            throw URLError(.badServerResponse)
        }
    )

    var caughtError: Error?
    do {
        _ = try await transcriber.transcribe(
            RecordedAudio(fileURL: symlinkURL, durationMs: 1_000)
        )
    } catch {
        caughtError = error
    }

    #expect(caughtError?.localizedDescription.contains("invalid") == true)
}

@Test
func openAICompatibleRouteIncludesPromptField() async throws {
    var config = AppConfig().transcription
    config.provider = .openAICompatible
    config.hintTerms = ["budget v2.xlsx", "OpenWhisper"]

    let capture = RequestCapture()
    let credentialStore = InMemoryOpenAICompatibleCredentialStore(
        apiKey: "  keychain-test-key  "
    )
    let transcriber = ChatGPTTranscriber(
        authManager: FakeChatGPTAuthManager(),
        config: config,
        recoveryCredentialStore: credentialStore,
        uploadLoader: { request, bodyFileURL in
            let body = try uploadBodyString(at: bodyFileURL)
            capture.append(
                request,
                body: body,
                authorizationHeader: request.value(
                    forHTTPHeaderField: "Authorization"
                )
            )
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"text":"OpenWhisper budget v2.xlsx"}"#.utf8), response)
        }
    )

    let audio = try makeAudioFixture()
    defer { try? FileManager.default.removeItem(at: audio.fileURL) }
    let result = try await transcriber.transcribe(audio)

    #expect(result.metrics.promptIncluded == true)
    #expect(capture.bodies().count == 1)
    #expect(capture.bodies()[0].contains("name=\"prompt\""))
    #expect(capture.bodies()[0].contains("budget v2.xlsx"))
    #expect(capture.authorizations() == ["Bearer keychain-test-key"])
}

@Test
func openAICompatibleRouteRejectsEnvironmentOnlyCredential() async throws {
    var config = AppConfig().transcription
    config.provider = .openAICompatible
    let originalEnvironmentKey = getenv("OPENAI_API_KEY").map {
        String(cString: $0)
    }
    setenv("OPENAI_API_KEY", "environment-only-key", 1)
    defer {
        if let originalEnvironmentKey {
            setenv("OPENAI_API_KEY", originalEnvironmentKey, 1)
        } else {
            unsetenv("OPENAI_API_KEY")
        }
    }

    let transcriber = ChatGPTTranscriber(
        authManager: FakeChatGPTAuthManager(),
        config: config,
        recoveryCredentialStore:
            InMemoryOpenAICompatibleCredentialStore(),
        uploadLoader: { _, _ in
            Issue.record(
                "Environment-only credentials must not reach the network"
            )
            throw URLError(.badServerResponse)
        }
    )

    let audio = try makeAudioFixture()
    defer { try? FileManager.default.removeItem(at: audio.fileURL) }
    var caughtError: Error?
    do {
        _ = try await transcriber.transcribe(audio)
    } catch {
        caughtError = error
    }

    if case .missingRecoveryAPIKey = caughtError as? TranscriptionError {
        // Expected: the shell environment is no longer a credential source.
    } else {
        Issue.record(
            "Expected missingRecoveryAPIKey, got \(String(describing: caughtError))"
        )
    }
}

@Test
func openAICompatibleRouteRedactsKeyFromProviderError() async throws {
    let secret = "sk-recovery-provider-secret"
    var config = AppConfig().transcription
    config.provider = .openAICompatible
    let transcriber = ChatGPTTranscriber(
        authManager: FakeChatGPTAuthManager(),
        config: config,
        recoveryCredentialStore:
            InMemoryOpenAICompatibleCredentialStore(apiKey: secret),
        uploadLoader: { request, _ in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (
                Data(
                    """
                    {"error":{"message":"Rejected Bearer \(secret)"}}
                    """.utf8
                ),
                response
            )
        }
    )

    let audio = try makeAudioFixture()
    defer { try? FileManager.default.removeItem(at: audio.fileURL) }
    var caughtError: Error?
    do {
        _ = try await transcriber.transcribe(audio)
    } catch {
        caughtError = error
    }

    let message = caughtError?.localizedDescription ?? ""
    #expect(message.contains(secret) == false)
    #expect(message.contains("[REDACTED]"))
}

@Test
func managedAuthFallsBackWhenPromptFieldIsRejected() async throws {
    var config = AppConfig().transcription
    config.provider = .chatGPTManagedAuth
    config.hintTerms = ["OpenWhisper"]

    let capture = RequestCapture()
    let capability = BridgePromptCapabilityStore()
    let authManager = FakeChatGPTAuthManager()
    let attempts = AttemptCounter()
    let transcriber = ChatGPTTranscriber(
        authManager: authManager,
        config: config,
        bridgePromptCapability: capability,
        uploadLoader: { request, bodyFileURL in
            let attempt = attempts.next()
            capture.append(request, body: try uploadBodyString(at: bodyFileURL))

            if attempt == 1 {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 400,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(#"{"message":"prompt unsupported"}"#.utf8), response)
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"text":"OpenWhisper done"}"#.utf8), response)
        }
    )

    let audio = try makeAudioFixture()
    defer { try? FileManager.default.removeItem(at: audio.fileURL) }
    let result = try await transcriber.transcribe(audio)

    #expect(result.text == "OpenWhisper done")
    #expect(result.metrics.promptIncluded == false)
    #expect(capture.bodies().count == 2)
    #expect(capture.bodies()[0].contains("name=\"prompt\""))
    #expect(capture.bodies()[1].contains("name=\"prompt\"") == false)
}

@Test
func managedAuthRefreshesAccessTokenAfterForbidden() async throws {
    var config = AppConfig().transcription
    config.provider = .chatGPTManagedAuth

    let capture = RequestCapture()
    let authManager = FakeChatGPTAuthManager(
        bestTokens: [.success("stale-token")],
        refreshTokens: [.success("fresh-token")]
    )
    let attempts = AttemptCounter()
    let transcriber = ChatGPTTranscriber(
        authManager: authManager,
        config: config,
        bridgePromptCapability: BridgePromptCapabilityStore(),
        uploadLoader: { request, bodyFileURL in
            let attempt = attempts.next()
            capture.append(
                request,
                body: try uploadBodyString(at: bodyFileURL),
                authorizationHeader: request.value(forHTTPHeaderField: "Authorization")
            )

            if attempt == 1 {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 403,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(#"{"message":"forbidden"}"#.utf8), response)
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"text":"refreshed transcript"}"#.utf8), response)
        }
    )

    let audio = try makeAudioFixture()
    defer { try? FileManager.default.removeItem(at: audio.fileURL) }
    let result = try await transcriber.transcribe(audio)

    #expect(result.text == "refreshed transcript")
    #expect(capture.authorizations() == ["Bearer stale-token", "Bearer fresh-token"])
}

@Test
func managedAuthReportsRetryableErrorAfterThreeCloudflareChallenges() async throws {
    var config = AppConfig().transcription
    config.provider = .chatGPTManagedAuth
    config.hintTerms = ["OpenWhisper"]

    let capture = RequestCapture()
    let authManager = FakeChatGPTAuthManager()
    let transcriber = ChatGPTTranscriber(
        authManager: authManager,
        config: config,
        bridgePromptCapability: BridgePromptCapabilityStore(),
        uploadLoader: { request, bodyFileURL in
            capture.append(
                request,
                body: try uploadBodyString(at: bodyFileURL),
                authorizationHeader: request.value(forHTTPHeaderField: "Authorization")
            )

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 403,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "text/html; charset=UTF-8",
                    "Server": "cloudflare",
                ]
            )!
            return (Data(#"<html><body>Just a moment...</body></html>"#.utf8), response)
        }
    )

    let audio = try makeAudioFixture()
    defer { try? FileManager.default.removeItem(at: audio.fileURL) }
    var caughtError: Error?
    do {
        _ = try await transcriber.transcribe(audio)
    } catch {
        caughtError = error
    }

    #expect(caughtError?.localizedDescription.contains("Cloudflare 403") == true)
    #expect(capture.bodies().count == 3)
    #expect(capture.authorizations() == ["Bearer desktop-token", "Bearer desktop-token", "Bearer desktop-token"])
}

@Test
func managedAuthManualRetryPolicyAttemptsCloudflareChallengeOnlyOnce() async throws {
    var config = AppConfig().transcription
    config.provider = .chatGPTManagedAuth
    config.hintTerms = ["OpenWhisper"]

    let capture = RequestCapture()
    let transcriber = ChatGPTTranscriber(
        authManager: FakeChatGPTAuthManager(),
        config: config,
        bridgePromptCapability: BridgePromptCapabilityStore(),
        cloudflareChallengeMaxAttempts: 1,
        uploadLoader: { request, bodyFileURL in
            capture.append(
                request,
                body: try uploadBodyString(at: bodyFileURL),
                authorizationHeader: request.value(forHTTPHeaderField: "Authorization")
            )

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 403,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "text/html; charset=UTF-8",
                    "Server": "cloudflare",
                ]
            )!
            return (Data(#"<html><body>Just a moment...</body></html>"#.utf8), response)
        }
    )

    let audio = try makeAudioFixture()
    defer { try? FileManager.default.removeItem(at: audio.fileURL) }
    var caughtError: Error?
    do {
        _ = try await transcriber.transcribe(audio)
    } catch {
        caughtError = error
    }

    #expect(caughtError?.localizedDescription.contains("403") == true)
    #expect(capture.urls() == [ManagedEndpointPolicy.transcriptionURL.absoluteString])
    #expect(capture.authorizations() == ["Bearer desktop-token"])
}
