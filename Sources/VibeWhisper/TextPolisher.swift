import Foundation

struct TextPolishMessage: Sendable, Equatable {
    let role: String
    let content: String
}

struct TextPolishEstimate: Sendable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let summary: String
}

struct TextPolishProviderSelection: Sendable, Equatable {
    let id: TextPolishProviderID
}

struct TextPolishResult: Sendable, Equatable {
    let text: String
    let provider: TextPolishProviderID?
    let applied: Bool
    let estimatedInputTokens: Int
    let estimatedOutputTokens: Int
}

protocol TextPolishing: Sendable {
    func polish(
        text: String,
        terminologyEntries: [TerminologyEntry],
        hintTerms: [String]
    ) async throws -> TextPolishResult
}

enum TextPolishError: LocalizedError {
    case providerUnavailable
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            return L10n.text("No text polish provider is configured.")
        case .invalidResponse:
            return L10n.text("Text polish provider returned an empty response.")
        case .requestFailed(let message):
            return L10n.format("Text polish failed: %@", message)
        }
    }
}

struct TextPolishProviderSelector: Sendable {
    func selectProvider(
        config: TextPolishConfig,
        chatGPTAuthAvailable: Bool
    ) -> TextPolishProviderSelection? {
        guard config.mode != .disabled else {
            return nil
        }

        if config.chatGPTAuthEnabled && chatGPTAuthAvailable {
            return TextPolishProviderSelection(id: .chatGPTAuth)
        }

        return nil
    }
}

struct TextPolishPromptBuilder: Sendable {
    var compiler: SkillPromptCompiler =
        .init()

    func buildMessages(
        transcript: String,
        terminologyEntries: [TerminologyEntry],
        config: TextPolishConfig,
        mode: DictationMode = .direct,
        locale: String = Locale.preferredLanguages.first ?? "zh-CN"
    ) -> [TextPolishMessage] {
        buildMessages(
            transcript: transcript,
            terminologyEntries: terminologyEntries,
            config: config,
            plan: SkillResolver().resolve(
                manualSkillID: mode.skillID,
                config: SkillsConfig(),
                launchAppContext: nil
            ),
            locale: locale
        )
    }

    func buildMessages(
        transcript: String,
        terminologyEntries:
            [TerminologyEntry],
        config: TextPolishConfig,
        plan:
            ResolvedSkillExecutionPlan,
        context: SkillPromptContext =
            .init(),
        locale: String =
            Locale.preferredLanguages
                .first ?? "zh-CN"
    ) -> [TextPolishMessage] {
        compiler.compile(
            transcript: transcript,
            terminologyEntries:
                terminologyEntries,
            config: config,
            plan: plan,
            context: context,
            locale: locale
        )
    }
}

struct TextPolishTokenEstimator: Sendable {
    func estimate(
        transcript: String,
        terminologyEntries: [TerminologyEntry],
        config: TextPolishConfig
    ) -> TextPolishEstimate {
        let glossaryCharacters = terminologyEntries
            .prefix(80)
            .map { $0.canonical.count + $0.aliases.joined(separator: " ").count }
            .reduce(0, +)
        let promptCharacters = 1_800 + min(glossaryCharacters, config.glossaryBudgetCharacters)
        let inputTokens = max(1, Int(ceil(Double(promptCharacters + transcript.count) / 1.8)))
        let outputTokens = max(120, min(config.maxOutputTokens, Int(ceil(Double(transcript.count) / 2.4))))
        return TextPolishEstimate(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            summary: "estimated \(inputTokens) input / \(outputTokens) output tokens"
        )
    }
}

struct OpenAICompatibleTextPolisher: TextPolishing {
    typealias RetrySleeper = @Sendable (Int) async throws -> Void
    typealias RetryJitter = @Sendable () -> Double

    let config: TextPolishConfig
    let dictationMode: DictationMode
    let skillPlan:
        ResolvedSkillExecutionPlan
    let skillPromptContext:
        SkillPromptContext
    let chatGPTAuthProvider: (any ChatGPTAuthProviding)?
    let chatGPTAuthAvailable: Bool
    let providerCapabilityPolicy: any ProviderCapabilityChecking
    let providerHealthMonitor: any ProviderHealthMonitoring
    let promptBuilder: TextPolishPromptBuilder
    let selector: TextPolishProviderSelector
    let transientFailureMaxAttempts: Int
    let retrySchedule: ProviderRetrySchedule
    let retrySleeper: RetrySleeper
    let retryJitter: RetryJitter
    let dataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(
        config: TextPolishConfig,
        dictationMode: DictationMode = .direct,
        skillPlan:
            ResolvedSkillExecutionPlan? = nil,
        skillPromptContext:
            SkillPromptContext = .init(),
        chatGPTAuthProvider: (any ChatGPTAuthProviding)? = nil,
        chatGPTAuthAvailable: Bool,
        providerCapabilityPolicy: any ProviderCapabilityChecking = ProviderCapabilityPolicyController.shared,
        providerHealthMonitor: any ProviderHealthMonitoring =
            ProviderHealthMonitor(),
        promptBuilder: TextPolishPromptBuilder = .init(),
        selector: TextPolishProviderSelector = .init(),
        transientFailureMaxAttempts: Int = 2,
        retrySchedule: ProviderRetrySchedule = .default,
        retrySleeper: @escaping RetrySleeper = { delayMilliseconds in
            try await Task.sleep(
                for: .milliseconds(delayMilliseconds)
            )
        },
        retryJitter: @escaping RetryJitter = {
            Double.random(in: 0...1)
        },
        dataLoader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await SecureHTTPClient.data(for: request)
        }
    ) {
        self.config = config
        self.dictationMode = dictationMode
        self.skillPlan =
            skillPlan
            ?? SkillResolver().resolve(
                manualSkillID:
                    dictationMode.skillID,
                config: SkillsConfig(),
                launchAppContext: nil
            )
        self.skillPromptContext =
            skillPromptContext
        self.chatGPTAuthProvider = chatGPTAuthProvider
        self.chatGPTAuthAvailable = chatGPTAuthAvailable
        self.providerCapabilityPolicy = providerCapabilityPolicy
        self.providerHealthMonitor = providerHealthMonitor
        self.promptBuilder = promptBuilder
        self.selector = selector
        self.transientFailureMaxAttempts = max(
            1,
            transientFailureMaxAttempts
        )
        self.retrySchedule = retrySchedule
        self.retrySleeper = retrySleeper
        self.retryJitter = retryJitter
        self.dataLoader = dataLoader
    }

    func polish(
        text: String,
        terminologyEntries: [TerminologyEntry],
        hintTerms: [String]
    ) async throws -> TextPolishResult {
        let allEntries = terminologyEntries + hintTerms.map {
            TerminologyEntry(canonical: $0, aliases: [])
        }
        let estimate = TextPolishTokenEstimator().estimate(
            transcript: text,
            terminologyEntries: allEntries,
            config: config
        )

        guard let selected = selector.selectProvider(
            config: config,
            chatGPTAuthAvailable: chatGPTAuthAvailable
        ) else {
            throw TextPolishError.providerUnavailable
        }

        guard selected.id == .chatGPTAuth, let chatGPTAuthProvider else {
            throw TextPolishError.providerUnavailable
        }

        try await providerCapabilityPolicy.require(.chatGPTTextPolish)
        let token = try await chatGPTAuthProvider.bestAvailableAccessToken()
        let polished = try await executeChatGPTResponsesRequest(
            token: token,
            messages: promptBuilder.buildMessages(
                transcript: text,
                terminologyEntries: allEntries,
                config: config,
                plan: skillPlan,
                context:
                    skillPromptContext
            )
        )
        return TextPolishResult(
            text: polished,
            provider: .chatGPTAuth,
            applied: polished != text,
            estimatedInputTokens: estimate.inputTokens,
            estimatedOutputTokens: estimate.outputTokens
        )
    }

    private func executeChatGPTResponsesRequest(
        token: String,
        messages: [TextPolishMessage]
    ) async throws -> String {
        guard !config.chatGPTResponseModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TextPolishError.providerUnavailable
        }
        let url = try ManagedEndpointPolicy.validatedURL(
            ManagedEndpointPolicy.responsesURL,
            for: .responses
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ProductIdentity.userAgent, forHTTPHeaderField: "User-Agent")

        let system = messages.first(where: { $0.role == "system" })?.content ?? ""
        let userText = messages
            .filter { $0.role != "system" }
            .map(\.content)
            .joined(separator: "\n\n")
        let body: [String: Any] = [
            "model": config.chatGPTResponseModel,
            "instructions": system,
            "input": [
                [
                    "type": "message",
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": userText,
                        ],
                    ],
                ],
            ],
            "stream": true,
            "store": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            return try await executeResponsesRequest(request)
        } catch let error as ProviderRequestFailure
            where error.shouldRefreshAuthentication
        {
            let refreshedToken = try await chatGPTAuthProvider?.refreshAccessToken() ?? token
            request.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
            return try await executeResponsesRequest(request)
        }
    }

    private func executeResponsesRequest(_ request: URLRequest) async throws -> String {
        var attempt = 1
        while true {
            do {
                return try await executeSingleResponsesRequest(request)
            } catch let failure as ProviderRequestFailure {
                let reportedFailure = failure.withAttempts(attempt)
                guard
                    !failure.circuitOpen,
                    failure.isAutomaticallyRetryable,
                    attempt < transientFailureMaxAttempts
                else {
                    throw reportedFailure
                }

                let delay = retrySchedule.delayMilliseconds(
                    afterFailedAttempt: attempt,
                    jitterUnit: retryJitter()
                )
                if delay > 0 {
                    try await retrySleeper(delay)
                }
                attempt += 1
            }
        }
    }

    private func executeSingleResponsesRequest(
        _ request: URLRequest
    ) async throws -> String {
        try await providerHealthMonitor.requireRequestPermission(
            for: .textPolish
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await dataLoader(request)
        } catch is CancellationError {
            await providerHealthMonitor.recordCancellation(for: .textPolish)
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            await providerHealthMonitor.recordCancellation(for: .textPolish)
            throw CancellationError()
        } catch {
            let failure = ProviderFailureClassifier.network(
                route: .textPolish
            )
            await providerHealthMonitor.recordFailure(failure)
            throw failure
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            let failure = ProviderFailureClassifier.invalidResponse(
                route: .textPolish
            )
            await providerHealthMonitor.recordFailure(failure)
            throw failure
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let failure = ProviderFailureClassifier.http(
                route: .textPolish,
                response: httpResponse,
                bodyPrefix: String(data: data.prefix(512), encoding: .utf8)
            )
            await providerHealthMonitor.recordFailure(failure)
            throw failure
        }

        if let text = decodeResponsesText(from: data) {
            await providerHealthMonitor.recordSuccess(for: .textPolish)
            return text
        }
        if let text = decodeResponsesSSEText(from: data) {
            await providerHealthMonitor.recordSuccess(for: .textPolish)
            return text
        }
        let failure = ProviderFailureClassifier.invalidResponse(
            route: .textPolish
        )
        await providerHealthMonitor.recordFailure(failure)
        throw failure
    }

    private func decodeResponsesText(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let outputText = object["output_text"] as? String {
            let trimmed = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let output = object["output"] as? [[String: Any]] else {
            return nil
        }
        let text = output
            .flatMap { item -> [[String: Any]] in
                item["content"] as? [[String: Any]] ?? []
            }
            .compactMap { content -> String? in
                content["text"] as? String
                    ?? content["output_text"] as? String
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func decodeResponsesSSEText(from data: Data) -> String? {
        guard let stream = String(data: data, encoding: .utf8) else {
            return nil
        }
        var output = ""
        for line in stream.components(separatedBy: .newlines) where line.hasPrefix("data: ") {
            let payload = String(line.dropFirst(6))
            guard payload != "[DONE]", let eventData = payload.data(using: .utf8) else {
                continue
            }
            guard let event = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
                continue
            }
            if let delta = event["delta"] as? String,
               (event["type"] as? String) == "response.output_text.delta" {
                output += delta
            } else if let response = event["response"] as? [String: Any],
                      let responseData = try? JSONSerialization.data(withJSONObject: response),
                      let text = decodeResponsesText(from: responseData) {
                output = text
            }
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

}
