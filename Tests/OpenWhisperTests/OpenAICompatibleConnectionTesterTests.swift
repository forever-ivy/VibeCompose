import Foundation
import Testing
@testable import OpenWhisper

private final class ConnectionRequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?

    func record(_ request: URLRequest) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func snapshot() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}

@Test
func recoveryConnectionTestSendsOnlySyntheticSilenceAndModel() async throws {
    let capture = ConnectionRequestCapture()
    let store = InMemoryOpenAICompatibleCredentialStore(
        apiKey: "recovery-test-key"
    )
    var config = AppConfig().transcription
    config.openAITranscriptionURL =
        "https://api.example.com/v1/audio/transcriptions"
    config.openAIModel = "example-transcriber"
    config.hintTerms = [
        "PRIVATE USER TRANSCRIPT MUST NOT BE SENT",
        "PRIVATE USER AUDIO MUST NOT BE SENT",
    ]

    let tester = OpenAICompatibleConnectionTester(
        credentialStore: store,
        dataLoader: { request in
            capture.record(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"text":""}"#.utf8), response)
        }
    )

    try await tester.test(config: config)

    let request = try #require(capture.snapshot())
    let body = try #require(request.httpBody)
    let bodyText = String(decoding: body, as: UTF8.self)

    #expect(request.httpMethod == "POST")
    #expect(
        request.url?.absoluteString
            == "https://api.example.com/v1/audio/transcriptions"
    )
    #expect(
        request.value(forHTTPHeaderField: "Authorization")
            == "Bearer recovery-test-key"
    )
    #expect(bodyText.contains("name=\"model\""))
    #expect(bodyText.contains("example-transcriber"))
    #expect(
        bodyText.contains(
            "filename=\"openwhisper-connection-test.wav\""
        )
    )
    #expect(body.range(of: Data("RIFF".utf8)) != nil)
    #expect(
        bodyText.contains("PRIVATE USER TRANSCRIPT MUST NOT BE SENT")
            == false
    )
    #expect(
        bodyText.contains("PRIVATE USER AUDIO MUST NOT BE SENT")
            == false
    )
    #expect(body.count < 8 * 1024)
}

@Test
func recoveryConnectionTestRedactsCredentialsFromProviderErrors() async {
    let secret = "sk-super-secret-recovery-key"
    let store = InMemoryOpenAICompatibleCredentialStore(apiKey: secret)
    let tester = OpenAICompatibleConnectionTester(
        credentialStore: store,
        dataLoader: { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = Data(
                """
                {"error":{"message":"Rejected \(secret) and Bearer token-another-secret-value"}}
                """.utf8
            )
            return (body, response)
        }
    )

    var caughtError: Error?
    do {
        try await tester.test(config: AppConfig().transcription)
    } catch {
        caughtError = error
    }

    let message = caughtError?.localizedDescription ?? ""
    #expect(message.contains(secret) == false)
    #expect(message.contains("token-another-secret-value") == false)
    #expect(message.contains("[REDACTED]"))
    #expect(message.contains("HTTP 401"))
}

@Test
func recoveryConnectionTestRequiresKeychainCredentialBeforeNetwork() async {
    let tester = OpenAICompatibleConnectionTester(
        credentialStore: InMemoryOpenAICompatibleCredentialStore(),
        dataLoader: { _ in
            Issue.record("Missing credentials must block the request")
            throw URLError(.badServerResponse)
        }
    )

    var caughtError: Error?
    do {
        try await tester.test(config: AppConfig().transcription)
    } catch {
        caughtError = error
    }

    #expect(
        caughtError as? OpenAICompatibleConnectionTestError
            == .missingAPIKey
    )
}
