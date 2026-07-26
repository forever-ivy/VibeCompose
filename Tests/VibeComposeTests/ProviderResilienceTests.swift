import Foundation
import Testing
@testable import VibeCompose

private final class ProviderTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(seconds: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(seconds)
        lock.unlock()
    }
}

@Test
func providerFailureClassifierSeparatesAuthChallengeRateLimitAndContract() {
    let url = URL(string: "https://chatgpt.com/backend-api/transcribe")!

    let authentication = ProviderFailureClassifier.http(
        route: .managedTranscription,
        response: HTTPURLResponse(
            url: url,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )!,
        bodyPrefix: #"{"message":"expired"}"#
    )
    #expect(authentication.category == .authentication)
    #expect(authentication.shouldRefreshAuthentication)

    let challenge = ProviderFailureClassifier.http(
        route: .managedTranscription,
        response: HTTPURLResponse(
            url: url,
            statusCode: 403,
            httpVersion: nil,
            headerFields: [
                "Content-Type": "text/html",
                "Server": "cloudflare",
            ]
        )!,
        bodyPrefix: "<html>Just a moment</html>"
    )
    #expect(challenge.category == .challenge)
    #expect(challenge.isRetryableByUser)

    let rateLimit = ProviderFailureClassifier.http(
        route: .managedTranscription,
        response: HTTPURLResponse(
            url: url,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "17"]
        )!,
        bodyPrefix: nil
    )
    #expect(rateLimit.category == .rateLimited)
    #expect(rateLimit.retryAfterSeconds == 17)

    let contract = ProviderFailureClassifier.http(
        route: .managedTranscription,
        response: HTTPURLResponse(
            url: url,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!,
        bodyPrefix: nil
    )
    #expect(contract.category == .contractChanged)
    #expect(contract.isRetryableByUser == false)
}

@Test
func providerFailureClassifierParsesHTTPDateRetryAfter() {
    let now = Date(timeIntervalSince1970: 1_784_000_000)
    let retryDate = now.addingTimeInterval(45)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"

    let response = HTTPURLResponse(
        url: URL(string: "https://chatgpt.com/backend-api/transcribe")!,
        statusCode: 429,
        httpVersion: nil,
        headerFields: ["Retry-After": formatter.string(from: retryDate)]
    )!
    let failure = ProviderFailureClassifier.http(
        route: .managedTranscription,
        response: response,
        bodyPrefix: nil,
        now: now
    )

    #expect(failure.retryAfterSeconds == 45)
}

@Test
func providerCircuitBreakerOpensAfterTransientFailuresAndResetsAfterProbe() async throws {
    let clock = ProviderTestClock(
        Date(timeIntervalSince1970: 1_784_000_000)
    )
    let monitor = ProviderHealthMonitor(
        policy: ProviderCircuitPolicy(
            transientFailureThreshold: 2,
            challengeFailureThreshold: 3,
            transientCooldownSeconds: 10,
            contractCooldownSeconds: 60,
            defaultRateLimitSeconds: 30
        ),
        now: clock.now
    )
    let failure = ProviderRequestFailure(
        route: .managedTranscription,
        category: .network
    )

    await monitor.recordFailure(failure)
    try await monitor.requireRequestPermission(
        for: .managedTranscription
    )
    await monitor.recordFailure(failure)

    var blocked: ProviderRequestFailure?
    do {
        try await monitor.requireRequestPermission(
            for: .managedTranscription
        )
    } catch let failure as ProviderRequestFailure {
        blocked = failure
    }
    #expect(blocked?.circuitOpen == true)
    #expect(blocked?.category == .network)
    #expect(blocked?.retryAfterSeconds == 10)

    clock.advance(seconds: 11)
    try await monitor.requireRequestPermission(
        for: .managedTranscription
    )
    await monitor.recordSuccess(for: .managedTranscription)
    try await monitor.requireRequestPermission(
        for: .managedTranscription
    )
}

@Test
func providerCircuitBreakerHonorsRetryAfterImmediately() async {
    let clock = ProviderTestClock(
        Date(timeIntervalSince1970: 1_784_000_000)
    )
    let monitor = ProviderHealthMonitor(
        now: clock.now
    )
    await monitor.recordFailure(
        ProviderRequestFailure(
            route: .recoveryTranscription,
            category: .rateLimited,
            statusCode: 429,
            retryAfterSeconds: 23
        )
    )

    var blocked: ProviderRequestFailure?
    do {
        try await monitor.requireRequestPermission(
            for: .recoveryTranscription
        )
    } catch let failure as ProviderRequestFailure {
        blocked = failure
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(blocked?.category == .rateLimited)
    #expect(blocked?.retryAfterSeconds == 23)
    #expect(blocked?.isRetryableByUser == true)
}

@Test
func providerCircuitBreakerReleasesHalfOpenProbeAfterCancellation() async throws {
    let clock = ProviderTestClock(
        Date(timeIntervalSince1970: 1_784_000_000)
    )
    let monitor = ProviderHealthMonitor(
        policy: ProviderCircuitPolicy(
            transientFailureThreshold: 1,
            challengeFailureThreshold: 1,
            transientCooldownSeconds: 10,
            contractCooldownSeconds: 60,
            defaultRateLimitSeconds: 30
        ),
        now: clock.now
    )
    await monitor.recordFailure(
        ProviderRequestFailure(
            route: .managedTranscription,
            category: .network
        )
    )

    clock.advance(seconds: 11)
    try await monitor.requireRequestPermission(
        for: .managedTranscription
    )
    await monitor.recordCancellation(for: .managedTranscription)

    try await monitor.requireRequestPermission(
        for: .managedTranscription
    )
    await monitor.recordSuccess(for: .managedTranscription)
    try await monitor.requireRequestPermission(
        for: .managedTranscription
    )
}

@Test
func providerRetryScheduleUsesBoundedExponentialBackoffAndJitter() {
    let schedule = ProviderRetrySchedule(
        baseDelayMilliseconds: 250,
        maximumDelayMilliseconds: 1_000,
        jitterFraction: 0.2
    )

    #expect(
        schedule.delayMilliseconds(
            afterFailedAttempt: 1,
            jitterUnit: 0.5
        ) == 250
    )
    #expect(
        schedule.delayMilliseconds(
            afterFailedAttempt: 2,
            jitterUnit: 0
        ) == 400
    )
    #expect(
        schedule.delayMilliseconds(
            afterFailedAttempt: 3,
            jitterUnit: 1
        ) == 1_000
    )

    let overflowSafeSchedule = ProviderRetrySchedule(
        baseDelayMilliseconds: .max,
        maximumDelayMilliseconds: 1_000,
        jitterFraction: 0
    )
    #expect(
        overflowSafeSchedule.delayMilliseconds(
            afterFailedAttempt: 9,
            jitterUnit: 0.5
        ) == 1_000
    )
}
