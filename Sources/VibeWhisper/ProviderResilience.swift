import Foundation

enum ProviderRoute: String, Codable, CaseIterable, Sendable {
    case managedTranscription = "managed_transcription"
    case recoveryTranscription = "recovery_transcription"
    case textPolish = "text_polish"

    var localizedName: String {
        switch self {
        case .managedTranscription:
            return L10n.text("ChatGPT transcription")
        case .recoveryTranscription:
            return L10n.text("OpenAI-Compatible transcription")
        case .textPolish:
            return L10n.text("AI Polish")
        }
    }
}

enum ProviderErrorCategory: String, Codable, CaseIterable, Sendable {
    case authentication
    case challenge
    case rateLimited = "rate_limited"
    case requestRejected = "request_rejected"
    case contractChanged = "contract_changed"
    case serviceUnavailable = "service_unavailable"
    case network
    case invalidResponse = "invalid_response"
    case unknown
}

struct ProviderRequestFailure: Error, LocalizedError, Equatable, Sendable {
    let route: ProviderRoute
    let category: ProviderErrorCategory
    let statusCode: Int?
    let retryAfterSeconds: Int?
    let attempts: Int
    let circuitOpen: Bool
    /// Short upstream detail (e.g. model-not-found) when available from the response body.
    let detail: String?

    init(
        route: ProviderRoute,
        category: ProviderErrorCategory,
        statusCode: Int? = nil,
        retryAfterSeconds: Int? = nil,
        attempts: Int = 1,
        circuitOpen: Bool = false,
        detail: String? = nil
    ) {
        self.route = route
        self.category = category
        self.statusCode = statusCode
        self.retryAfterSeconds = retryAfterSeconds.map {
            min(3_600, max(1, $0))
        }
        self.attempts = max(1, attempts)
        self.circuitOpen = circuitOpen
        self.detail = detail.map {
            String($0.prefix(280)).trimmingCharacters(in: .whitespacesAndNewlines)
        }.flatMap { $0.isEmpty ? nil : $0 }
    }

    var shouldRefreshAuthentication: Bool {
        category == .authentication
    }

    var permitsPromptFallback: Bool {
        category == .requestRejected
            && (statusCode == 400 || statusCode == 422)
    }

    var isAutomaticallyRetryable: Bool {
        category == .serviceUnavailable || category == .network
    }

    var isRetryableByUser: Bool {
        switch category {
        case .challenge, .rateLimited, .serviceUnavailable, .network:
            return true
        case .authentication,
             .requestRejected,
             .contractChanged,
             .invalidResponse,
             .unknown:
            return false
        }
    }

    func withAttempts(_ attempts: Int) -> ProviderRequestFailure {
        ProviderRequestFailure(
            route: route,
            category: category,
            statusCode: statusCode,
            retryAfterSeconds: retryAfterSeconds,
            attempts: attempts,
            circuitOpen: circuitOpen,
            detail: detail
        )
    }

    var errorDescription: String? {
        let name = route.localizedName
        switch category {
        case .authentication:
            return L10n.format(
                "%@ rejected the credential. Sign in again or update the API key.",
                name
            )
        case .challenge:
            if route == .textPolish {
                return L10n.format(
                    "%@ hit an upstream challenge. VibeWhisper kept the normalized transcript.",
                    name
                )
            }
            return L10n.format(
                "%@ hit an upstream challenge. Recording kept—wait briefly, then Retry.",
                name
            )
        case .rateLimited:
            let seconds = retryAfterSeconds ?? 60
            if route == .textPolish {
                return L10n.format(
                    "%@ is rate limited. VibeWhisper kept the normalized transcript; try again in about %ld seconds.",
                    name,
                    seconds
                )
            }
            return L10n.format(
                "%@ is rate limited. Recording kept—retry in about %ld seconds.",
                name,
                seconds
            )
        case .requestRejected:
            if let detail, Self.detailLooksLikeModelIssue(detail) {
                return L10n.format(
                    "%@ rejected the selected model. %@",
                    name,
                    detail
                )
            }
            if let detail {
                return L10n.format(
                    "%@ rejected the request: %@",
                    name,
                    detail
                )
            }
            return L10n.format(
                "%@ rejected the request format.",
                name
            )
        case .contractChanged:
            return L10n.format(
                "%@ contract changed. Update VibeWhisper before retrying this provider.",
                name
            )
        case .serviceUnavailable:
            if route == .textPolish {
                return L10n.format(
                    "%@ is temporarily unavailable after %ld attempts. VibeWhisper kept the normalized transcript.",
                    name,
                    attempts
                )
            }
            return L10n.format(
                "%@ is unavailable after %ld attempts. Recording kept—try again later.",
                name,
                attempts
            )
        case .network:
            if route == .textPolish {
                return L10n.format(
                    "%@ could not reach the network after %ld attempts. VibeWhisper kept the normalized transcript.",
                    name,
                    attempts
                )
            }
            return L10n.format(
                "%@ could not reach the network after %ld attempts. Recording kept—retry when online.",
                name,
                attempts
            )
        case .invalidResponse:
            return L10n.format(
                "%@ returned an invalid or empty response.",
                name
            )
        case .unknown:
            if circuitOpen {
                return L10n.format(
                    "%@ is temporarily paused after repeated failures. Try again in about %ld seconds.",
                    name,
                    retryAfterSeconds ?? 30
                )
            }
            return L10n.format("%@ failed unexpectedly.", name)
        }
    }

    private static func detailLooksLikeModelIssue(_ detail: String) -> Bool {
        let lower = detail.lowercased()
        return lower.contains("model")
            && (
                lower.contains("not found")
                    || lower.contains("does not exist")
                    || lower.contains("unsupported")
                    || lower.contains("not available")
                    || lower.contains("invalid")
                    || lower.contains("unknown")
                    || lower.contains("access")
                    || lower.contains("permission")
            )
    }
}

enum ProviderFailureClassifier {
    static func http(
        route: ProviderRoute,
        response: HTTPURLResponse,
        bodyPrefix: String?,
        now: Date = Date()
    ) -> ProviderRequestFailure {
        let statusCode = response.statusCode
        let contentType = response
            .value(forHTTPHeaderField: "Content-Type")?
            .lowercased() ?? ""
        let server = response
            .value(forHTTPHeaderField: "Server")?
            .lowercased() ?? ""
        let body = bodyPrefix?.lowercased() ?? ""

        let category: ProviderErrorCategory
        if statusCode == 403,
           server.contains("cloudflare")
            || contentType.contains("text/html")
            || body.contains("<html")
            || body.contains("cloudflare")
        {
            category = .challenge
        } else {
            switch statusCode {
            case 401, 403:
                category = .authentication
            case 429:
                category = .rateLimited
            case 400, 409, 415, 422:
                category = .requestRejected
            case 404, 405, 410:
                category = .contractChanged
            case 408, 425, 500...599:
                category = .serviceUnavailable
            default:
                category = .unknown
            }
        }

        let detail = sanitizeBodyDetail(bodyPrefix)
        return ProviderRequestFailure(
            route: route,
            category: category,
            statusCode: statusCode,
            retryAfterSeconds: category == .rateLimited
                ? retryAfterSeconds(response: response, now: now)
                : nil,
            detail: detail
        )
    }

    private static func sanitizeBodyDetail(_ bodyPrefix: String?) -> String? {
        guard let raw = bodyPrefix?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else {
            return nil
        }
        if let data = raw.data(using: .utf8),
           let message = ChatGPTAccountModelCatalog.extractErrorMessage(from: data),
           !message.isEmpty
        {
            return message
        }
        // Avoid dumping HTML challenge pages into the UI.
        if raw.lowercased().contains("<html") || raw.lowercased().contains("<!doctype") {
            return nil
        }
        return String(raw.prefix(240))
    }

    static func network(
        route: ProviderRoute
    ) -> ProviderRequestFailure {
        ProviderRequestFailure(route: route, category: .network)
    }

    static func invalidResponse(
        route: ProviderRoute
    ) -> ProviderRequestFailure {
        ProviderRequestFailure(route: route, category: .invalidResponse)
    }

    private static func retryAfterSeconds(
        response: HTTPURLResponse,
        now: Date
    ) -> Int? {
        guard let rawValue = response
            .value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawValue.isEmpty
        else {
            return nil
        }

        if let seconds = Int(rawValue) {
            return min(3_600, max(1, seconds))
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let retryDate = formatter.date(from: rawValue) else {
            return nil
        }
        return min(
            3_600,
            max(1, Int(ceil(retryDate.timeIntervalSince(now))))
        )
    }
}

struct ProviderCircuitPolicy: Sendable, Equatable {
    let transientFailureThreshold: Int
    let challengeFailureThreshold: Int
    let transientCooldownSeconds: Int
    let contractCooldownSeconds: Int
    let defaultRateLimitSeconds: Int

    static let `default` = ProviderCircuitPolicy(
        transientFailureThreshold: 3,
        challengeFailureThreshold: 4,
        transientCooldownSeconds: 30,
        contractCooldownSeconds: 15 * 60,
        defaultRateLimitSeconds: 60
    )
}

protocol ProviderHealthMonitoring: Sendable {
    func requireRequestPermission(for route: ProviderRoute) async throws
    func recordSuccess(for route: ProviderRoute) async
    func recordFailure(_ failure: ProviderRequestFailure) async
    func recordCancellation(for route: ProviderRoute) async
}

actor ProviderHealthMonitor: ProviderHealthMonitoring {
    static let shared = ProviderHealthMonitor()

    private struct RouteState {
        var consecutiveFailures = 0
        var openUntil: Date?
        var probeInFlight = false
        var category = ProviderErrorCategory.unknown
    }

    private let policy: ProviderCircuitPolicy
    private let now: @Sendable () -> Date
    private var states: [ProviderRoute: RouteState] = [:]

    init(
        policy: ProviderCircuitPolicy = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.policy = policy
        self.now = now
    }

    func requireRequestPermission(for route: ProviderRoute) throws {
        guard var state = states[route], let openUntil = state.openUntil else {
            return
        }

        let current = now()
        if openUntil > current {
            throw circuitOpenFailure(
                route: route,
                state: state,
                current: current
            )
        }

        if state.probeInFlight {
            throw ProviderRequestFailure(
                route: route,
                category: state.category,
                retryAfterSeconds: 1,
                attempts: max(1, state.consecutiveFailures),
                circuitOpen: true
            )
        }

        state.probeInFlight = true
        states[route] = state
    }

    func recordSuccess(for route: ProviderRoute) {
        states.removeValue(forKey: route)
    }

    func recordFailure(_ failure: ProviderRequestFailure) {
        var state = states[failure.route] ?? RouteState()
        state.probeInFlight = false
        state.category = failure.category

        switch failure.category {
        case .authentication, .requestRejected:
            state.consecutiveFailures = 0
            state.openUntil = nil
        case .rateLimited:
            state.consecutiveFailures += 1
            state.openUntil = now().addingTimeInterval(
                TimeInterval(
                    failure.retryAfterSeconds
                        ?? policy.defaultRateLimitSeconds
                )
            )
        case .contractChanged:
            state.consecutiveFailures += 1
            state.openUntil = now().addingTimeInterval(
                TimeInterval(policy.contractCooldownSeconds)
            )
        case .challenge:
            state.consecutiveFailures += 1
            if state.consecutiveFailures
                >= max(1, policy.challengeFailureThreshold)
            {
                state.openUntil = now().addingTimeInterval(
                    TimeInterval(policy.transientCooldownSeconds)
                )
            }
        case .serviceUnavailable,
             .network,
             .invalidResponse,
             .unknown:
            state.consecutiveFailures += 1
            if state.consecutiveFailures
                >= max(1, policy.transientFailureThreshold)
            {
                state.openUntil = now().addingTimeInterval(
                    TimeInterval(policy.transientCooldownSeconds)
                )
            }
        }

        if state.consecutiveFailures == 0, state.openUntil == nil {
            states.removeValue(forKey: failure.route)
        } else {
            states[failure.route] = state
        }
    }

    func recordCancellation(for route: ProviderRoute) {
        guard var state = states[route], state.probeInFlight else {
            return
        }
        state.probeInFlight = false
        states[route] = state
    }

    private func circuitOpenFailure(
        route: ProviderRoute,
        state: RouteState,
        current: Date
    ) -> ProviderRequestFailure {
        let remaining = max(
            1,
            Int(
                ceil(
                    (state.openUntil ?? current)
                        .timeIntervalSince(current)
                )
            )
        )
        return ProviderRequestFailure(
            route: route,
            category: state.category,
            retryAfterSeconds: remaining,
            attempts: max(1, state.consecutiveFailures),
            circuitOpen: true
        )
    }
}

struct ProviderRetrySchedule: Sendable, Equatable {
    let baseDelayMilliseconds: Int
    let maximumDelayMilliseconds: Int
    let jitterFraction: Double

    static let `default` = ProviderRetrySchedule(
        baseDelayMilliseconds: 250,
        maximumDelayMilliseconds: 2_000,
        jitterFraction: 0.2
    )

    func delayMilliseconds(
        afterFailedAttempt attempt: Int,
        jitterUnit: Double
    ) -> Int {
        let exponent = min(8, max(0, attempt - 1))
        let boundedMaximum = max(0, maximumDelayMilliseconds)
        let boundedBase = max(0, baseDelayMilliseconds)
        let (candidate, overflow) = boundedBase
            .multipliedReportingOverflow(by: 1 << exponent)
        let exponential = min(
            boundedMaximum,
            overflow ? boundedMaximum : candidate
        )
        let boundedJitter = min(1, max(0, jitterUnit))
        let signedJitter = (boundedJitter * 2) - 1
        let multiplier = 1 + (signedJitter * min(1, max(0, jitterFraction)))
        return min(
            boundedMaximum,
            max(0, Int((Double(exponential) * multiplier).rounded()))
        )
    }
}
