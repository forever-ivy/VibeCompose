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

@Test
func managedAuthSendsAudioAboveLegacyTenMegabyteLimit() async throws {
    var config = AppConfig().transcription
    config.provider = .chatGPTManagedAuth

    let capture = RequestCapture()
    let transcriber = ChatGPTTranscriber(
        authManager: FakeChatGPTAuthManager(),
        config: config,
        bridgePromptCapability: BridgePromptCapabilityStore(),
        dataLoader: { request in
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
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
        dataLoader: { _ in
            Issue.record("Oversized audio should be rejected before a network request")
            throw URLError(.badServerResponse)
        }
    )

    let audio = try makeAudioFixture(byteCount: 25_000_001)
    var caughtError: Error?
    do {
        _ = try await transcriber.transcribe(audio)
    } catch {
        caughtError = error
    }

    #expect(caughtError?.localizedDescription.contains("25 MB") == true)
}

@Test
func openAICompatibleRouteIncludesPromptField() async throws {
    var config = AppConfig().transcription
    config.provider = .openAICompatible
    config.openAIAuthTokenEnv = "OPENWHISPER_TEST_OPENAI_KEY"
    config.hintTerms = ["budget v2.xlsx", "OpenWhisper"]

    let capture = RequestCapture()
    let transcriber = ChatGPTTranscriber(
        authManager: FakeChatGPTAuthManager(),
        config: config,
        dataLoader: { request in
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            capture.append(request, body: body)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"text":"OpenWhisper budget v2.xlsx"}"#.utf8), response)
        }
    )

    let originalEnvironment = ProcessInfo.processInfo.environment
    setenv(config.openAIAuthTokenEnv, "test-key", 1)
    defer {
        if let existing = originalEnvironment[config.openAIAuthTokenEnv] {
            setenv(config.openAIAuthTokenEnv, existing, 1)
        } else {
            unsetenv(config.openAIAuthTokenEnv)
        }
    }

    let audio = try makeAudioFixture()
    let result = try await transcriber.transcribe(audio)

    #expect(result.metrics.promptIncluded == true)
    #expect(capture.bodies().count == 1)
    #expect(capture.bodies()[0].contains("name=\"prompt\""))
    #expect(capture.bodies()[0].contains("budget v2.xlsx"))
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
        dataLoader: { request in
            let attempt = attempts.next()
            capture.append(request, body: String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "")

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
        dataLoader: { request in
            let attempt = attempts.next()
            capture.append(
                request,
                body: String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "",
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
    let result = try await transcriber.transcribe(audio)

    #expect(result.text == "refreshed transcript")
    #expect(capture.authorizations() == ["Bearer stale-token", "Bearer fresh-token"])
}

@Test
func managedAuthReportsRetryableErrorAfterThreeCloudflareChallenges() async throws {
    var config = AppConfig().transcription
    config.provider = .chatGPTManagedAuth
    config.hintTerms = ["OpenWhisper"]
    config.openAIAuthTokenEnv = "OPENWHISPER_TEST_MISSING_RECOVERY_KEY"
    unsetenv(config.openAIAuthTokenEnv)

    let capture = RequestCapture()
    let authManager = FakeChatGPTAuthManager()
    let transcriber = ChatGPTTranscriber(
        authManager: authManager,
        config: config,
        bridgePromptCapability: BridgePromptCapabilityStore(),
        dataLoader: { request in
            capture.append(
                request,
                body: String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "",
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
        dataLoader: { request in
            capture.append(
                request,
                body: String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "",
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
