import Foundation
import Testing
@testable import VibeCompose

private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var requestURLs: [String] = []
    private var requestBodies: [String] = []
    private var authorizationHeaders: [String] = []

    func append(_ request: URLRequest, body: String) {
        lock.lock()
        requestURLs.append(request.url?.absoluteString ?? "")
        requestBodies.append(body)
        authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
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

private final class PolishAttemptCounter: @unchecked Sendable {
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

private final class PolishDelayCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int] = []

    func append(_ value: Int) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

@Test
func defaultTextPolishConfigUsesOnlyChatGPTAuthAndDoesNotEncodeKeys() throws {
    let config = AppConfig()

    #expect(config.transcription.textPolish.mode == .automaticWhenKeyAvailable)
    #expect(config.transcription.textPolish.chatGPTAuthEnabled)
    #expect(config.transcription.textPolish.chatGPTResponseModel == "gpt-5.5")
    #expect(config.transcription.textPolish.glossaryBudgetCharacters == 1_200)

    let data = try JSONEncoder().encode(config)
    let json = String(data: data, encoding: .utf8) ?? ""
    #expect(json.contains("apiKey") == false)
    #expect(json.contains("providerPriority") == false)
    #expect(json.contains("providers") == false)
    #expect(json.contains("sk-") == false)
}

@Test
func legacyTextPolishConfigIgnoresRemovedAPIKeyProviderFields() throws {
    let json = """
    {
      "transcription": {
        "textPolish": {
          "mode": "automaticWhenKeyAvailable",
          "providerPriority": ["deepSeek", "openAI", "kimi", "custom", "chatGPTAuth"],
          "providers": {
            "deepSeek": {"baseURL": "https://api.deepseek.com", "model": "deepseek-v4-flash"}
          },
          "allowChatGPTAuthFallback": false,
          "chatGPTResponseModel": "gpt-5.4"
        }
      }
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(AppConfig.self, from: json)

    #expect(decoded.transcription.textPolish.chatGPTAuthEnabled == false)
    #expect(decoded.transcription.textPolish.chatGPTResponseModel == "gpt-5.4")
}

@Test
func textPolishProviderSelectorUsesChatGPTAuthOrOwnAPI() throws {
    var config = TextPolishConfig()
    config.chatGPTAuthEnabled = true
    config.openAICompatibleEnabled = false

    let selected = TextPolishProviderSelector().selectProvider(
        config: config,
        chatGPTAuthAvailable: true
    )

    #expect(selected?.id == .chatGPTAuth)
    #expect(
        TextPolishProviderSelector().selectProvider(
            config: config,
            chatGPTAuthAvailable: false
        ) == nil
    )

    config.chatGPTAuthEnabled = false
    #expect(
        TextPolishProviderSelector().selectProvider(
            config: config,
            chatGPTAuthAvailable: true
        ) == nil
    )

    config.openAICompatibleEnabled = true
    config.openAICompatibleURL = "https://api.openai.com/v1/chat/completions"
    config.openAICompatibleModel = "gpt-4o"
    #expect(
        TextPolishProviderSelector().selectProvider(
            config: config,
            chatGPTAuthAvailable: false,
            openAICompatibleKeyAvailable: true
        )?.id == .openAICompatible
    )
    #expect(
        TextPolishProviderSelector().selectProvider(
            config: config,
            chatGPTAuthAvailable: true,
            openAICompatibleKeyAvailable: false
        ) == nil
    )
}

@Test
func textPolishPromptRequestsCodePromptStyleAndLaterIntentWins() {
    let prompt = TextPolishPromptBuilder().buildMessages(
        transcript: "呃先做一个登录页面，然后不对，改成先做设置页，最后发布 v0.1。",
        terminologyEntries: [
            TerminologyEntry(canonical: "VibeCompose", aliases: ["vibecompose"]),
            TerminologyEntry(canonical: "ExampleSDK", aliases: ["Example SDK"]),
        ],
        config: TextPolishConfig(),
        mode: .codePrompt,
        locale: "zh-CN"
    )

    let joined = prompt.map(\.content).joined(separator: "\n")
    #expect(joined.contains("Code Prompt"))
    #expect(joined.contains("implementation steps"))
    #expect(joined.contains("acceptance criteria"))
    #expect(joined.contains("后面"))
    #expect(joined.contains("VibeCompose"))
    #expect(joined.contains("ExampleSDK"))
    #expect(joined.contains("口头禅"))
    #expect(joined.contains("Do not summarize away requirements"))
    #expect(joined.contains("⟪OW_LITERAL_0000⟫"))
    #expect(joined.contains("immutable placeholders"))
}

@Test
func textPolishPromptHandlesChineseResequenceInstruction() {
    let prompt = TextPolishPromptBuilder().buildMessages(
        transcript: "我们来测试一下这个AI润色啊， 现在包括三个步骤啊，一，打开冰箱，二，然后呢再把冰箱关，呃不对，二，把大象放进去，三呢就是关上冰箱门，按这个顺序来做啊。",
        terminologyEntries: [
            TerminologyEntry(canonical: "ChatGPT", aliases: ["chat gpt"]),
        ],
        config: TextPolishConfig(),
        locale: "zh-CN"
    )

    let joined = prompt.map(\.content).joined(separator: "\n")
    #expect(joined.contains("一"))
    #expect(joined.contains("二"))
    #expect(joined.contains("三"))
    #expect(joined.contains("把大象放进去"))
    #expect(joined.contains("后面"))
}

@Test
func textPolishPromptAppliesModeSpecificWritingContract() {
    let builder = TextPolishPromptBuilder()
    let email = builder.buildMessages(
        transcript: "告诉大家明天下午三点开会。",
        terminologyEntries: [],
        config: TextPolishConfig(),
        mode: .email,
        locale: "zh-CN"
    )
    let codePrompt = builder.buildMessages(
        transcript: "修改 Sources/VibeCompose/AppConfig.swift。",
        terminologyEntries: [],
        config: TextPolishConfig(),
        mode: .codePrompt,
        locale: "zh-CN"
    )
    let translation = builder.buildMessages(
        transcript: "把这段内容翻译成英文。",
        terminologyEntries: [],
        config: TextPolishConfig(),
        mode: .translate,
        locale: "zh-CN"
    )

    #expect(email.map(\.content).joined().contains("Voice Mode: Email"))
    #expect(email.map(\.content).joined().contains("subject line"))
    #expect(
        codePrompt.map(\.content).joined()
            .contains("Voice Mode: Code Prompt")
    )
    #expect(
        codePrompt.map(\.content).joined()
            .contains("implementation-ready coding request")
    )
    #expect(
        codePrompt.map(\.content).joined()
            .contains("quoted literals")
    )
    #expect(
        translation.map(\.content).joined()
            .contains("Voice Mode: Translate")
    )
    #expect(
        translation.map(\.content).joined()
            .contains("predominantly Chinese")
    )
}

@Test
func textPolishTokenEstimatorClassifiesLongDictationCost() {
    let estimate = TextPolishTokenEstimator().estimate(
        transcript: String(repeating: "这是一个需要整理成长句计划的语音输入。", count: 80),
        terminologyEntries: [
            TerminologyEntry(canonical: "VibeCompose", aliases: ["vibecompose"]),
        ],
        config: TextPolishConfig()
    )

    #expect(estimate.inputTokens >= 1_000)
    #expect(estimate.outputTokens >= 300)
    #expect(estimate.summary.contains("estimated"))
}

@Test
func chatGPTAuthTextPolisherUsesResponsesEndpointWithLoginToken() async throws {
    var config = TextPolishConfig()
    config.chatGPTAuthEnabled = true
    config.chatGPTResponseModel = "gpt-5.5"

    let capture = RequestCapture()
    let auth = FakeChatGPTAuthManager(bestTokens: [.success("chatgpt-token")])
    let polisher = OpenAICompatibleTextPolisher(
        config: config,
        chatGPTAuthProvider: auth,
        chatGPTAuthAvailable: true,
        dataLoader: { request in
            capture.append(request, body: String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (
                Data(#"{"output_text":"- 目标：发布 VibeCompose v0.1"}"#.utf8),
                response
            )
        }
    )

    let result = try await polisher.polish(
        text: "呃发布 vibecompose v0.1",
        terminologyEntries: [TerminologyEntry(canonical: "VibeCompose", aliases: ["vibecompose"])],
        hintTerms: []
    )

    #expect(result.provider == .chatGPTAuth)
    #expect(result.applied)
    #expect(result.text.contains("VibeCompose v0.1"))
    #expect(capture.urls() == ["https://chatgpt.com/backend-api/codex/responses"])
    #expect(capture.authorizations() == ["Bearer chatgpt-token"])
    let body = capture.bodies().first ?? ""
    #expect(body.contains("gpt-5.5"))
    #expect(body.contains(#""stream":true"#))
    #expect(body.contains(#""store":false"#))
    #expect(body.contains("temperature") == false)
    #expect(body.contains("max_output_tokens") == false)
    #expect(body.contains("chatgpt-token") == false)
}


@Test
func openAICompatibleTextPolisherUsesChatCompletionsEndpoint() async throws {
    var config = TextPolishConfig()
    config.chatGPTAuthEnabled = false
    config.openAICompatibleEnabled = true
    config.openAICompatibleURL = "https://api.example.com/v1/chat/completions"
    config.openAICompatibleModel = "gpt-4o"

    let store = InMemoryOpenAICompatibleCredentialStore()
    try store.saveAPIKey("sk-test-polish")
    let capture = RequestCapture()
    let polisher = OpenAICompatibleTextPolisher(
        config: config,
        chatGPTAuthProvider: nil,
        chatGPTAuthAvailable: false,
        polishCredentialStore: store,
        dataLoader: { request in
            capture.append(request, body: String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (
                Data(#"{"choices":[{"message":{"role":"assistant","content":"Polished with own API"}}]}"#.utf8),
                response
            )
        }
    )

    let result = try await polisher.polish(
        text: "hello world",
        terminologyEntries: [],
        hintTerms: []
    )

    #expect(result.provider == .openAICompatible)
    #expect(result.text == "Polished with own API")
    #expect(capture.urls() == ["https://api.example.com/v1/chat/completions"])
    #expect(capture.authorizations() == ["Bearer sk-test-polish"])
    let body = capture.bodies().first ?? ""
    #expect(body.contains("gpt-4o"))
    #expect(body.contains("messages"))
    #expect(body.contains("sk-test-polish") == false)
}

@Test
func chatGPTAuthTextPolisherRequestCarriesResequenceHint() async throws {
    var config = TextPolishConfig()
    config.chatGPTAuthEnabled = true
    config.chatGPTResponseModel = "gpt-5.5"

    let capture = RequestCapture()
    let auth = FakeChatGPTAuthManager(bestTokens: [.success("chatgpt-token")])
    let polisher = OpenAICompatibleTextPolisher(
        config: config,
        chatGPTAuthProvider: auth,
        chatGPTAuthAvailable: true,
        dataLoader: { request in
            capture.append(request, body: String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (
                Data(#"{"output_text":"- 第一步：打开冰箱\n- 第二步：把大象放进去\n- 第三步：关上冰箱门"}"#.utf8),
                response
            )
        }
    )

    _ = try await polisher.polish(
        text: "我们来测试一下这个AI润色啊， 现在包括三个步骤啊，一，打开冰箱，二，然后呢再把冰箱关，呃不对，二，把大象放进去，三呢就是关上冰箱门，按这个顺序来做啊。",
        terminologyEntries: [],
        hintTerms: []
    )

    let body = capture.bodies().first ?? ""
    #expect(body.contains("后面为主"))
    #expect(body.contains("一，打开冰箱"))
    #expect(body.contains("把大象放进去"))
    #expect(body.contains("三呢就是关上冰箱门"))
    #expect(body.contains("Do not summarize away requirements"))
    #expect(body.contains("gpt-5.5"))
    #expect(capture.urls() == ["https://chatgpt.com/backend-api/codex/responses"])
}

@Test
func chatGPTAuthTextPolisherRetriesTransientFailuresThenRecovers() async throws {
    var config = TextPolishConfig()
    config.chatGPTAuthEnabled = true

    let attempts = PolishAttemptCounter()
    let delays = PolishDelayCapture()
    let polisher = OpenAICompatibleTextPolisher(
        config: config,
        chatGPTAuthProvider: FakeChatGPTAuthManager(),
        chatGPTAuthAvailable: true,
        transientFailureMaxAttempts: 2,
        retrySleeper: { delay in
            delays.append(delay)
        },
        retryJitter: { 0.5 },
        dataLoader: { request in
            if attempts.next() == 1 {
                return (
                    Data(#"{"message":"temporary"}"#.utf8),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 503,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
            return (
                Data(#"{"output_text":"Recovered polish"}"#.utf8),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
    )

    let result = try await polisher.polish(
        text: "recover this",
        terminologyEntries: [],
        hintTerms: []
    )

    #expect(result.text == "Recovered polish")
    #expect(attempts.current() == 2)
    #expect(delays.snapshot() == [250])
}

@Test
func chatGPTAuthTextPolisherRateLimitOpensSharedCircuit() async {
    var config = TextPolishConfig()
    config.chatGPTAuthEnabled = true

    let attempts = PolishAttemptCounter()
    let monitor = ProviderHealthMonitor()
    let polisher = OpenAICompatibleTextPolisher(
        config: config,
        chatGPTAuthProvider: FakeChatGPTAuthManager(),
        chatGPTAuthAvailable: true,
        providerHealthMonitor: monitor,
        retrySleeper: { _ in },
        retryJitter: { 0.5 },
        dataLoader: { request in
            _ = attempts.next()
            return (
                Data(#"{"message":"slow down"}"#.utf8),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: ["Retry-After": "15"]
                )!
            )
        }
    )

    var firstFailure: ProviderRequestFailure?
    do {
        _ = try await polisher.polish(
            text: "first",
            terminologyEntries: [],
            hintTerms: []
        )
    } catch let failure as ProviderRequestFailure {
        firstFailure = failure
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
    #expect(firstFailure?.category == .rateLimited)
    #expect(firstFailure?.retryAfterSeconds == 15)

    var secondFailure: ProviderRequestFailure?
    do {
        _ = try await polisher.polish(
            text: "second",
            terminologyEntries: [],
            hintTerms: []
        )
    } catch let failure as ProviderRequestFailure {
        secondFailure = failure
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
    #expect(secondFailure?.circuitOpen == true)
    #expect(attempts.current() == 1)
}
