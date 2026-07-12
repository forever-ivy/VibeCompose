import Foundation
import Testing
@testable import OpenWhisper

@Test
func oauthCallbackServerAcceptsMatchingStateAndCode() async throws {
    let server = BrowserOAuthCallbackServer(state: "state-1", port: 14655, path: "/auth/callback")
    try await server.start()
    defer {
        Task { await server.stop() }
    }

    async let code = server.waitForAuthorizationCode()
    let status = try await get("http://localhost:14655/auth/callback?code=auth-code&state=state-1")

    #expect(status == 200)
    #expect(try await code == "auth-code")
}

@Test
func oauthCallbackServerRejectsMismatchedState() async throws {
    let server = BrowserOAuthCallbackServer(state: "state-1", port: 14656, path: "/auth/callback")
    try await server.start()
    defer {
        Task { await server.stop() }
    }

    let status = try await get("http://localhost:14656/auth/callback?code=auth-code&state=wrong")

    #expect(status == 400)
}

@Test
func oauthCallbackServerKeepsWaitingAfterDuplicateOrInvalidCallback() async throws {
    let server = BrowserOAuthCallbackServer(state: "state-1", port: 14657, path: "/auth/callback")
    try await server.start()
    defer {
        Task { await server.stop() }
    }

    async let code = server.waitForAuthorizationCode()
    let duplicateStatus = try await get(
        "http://localhost:14657/auth/callback?code=bad&state=state-1&state=state-1"
    )
    #expect(duplicateStatus == 400)

    let validStatus = try await get(
        "http://localhost:14657/auth/callback?code=auth-code&state=state-1"
    )
    #expect(validStatus == 200)
    #expect(try await code == "auth-code")
}

@Test
func oauthCallbackWaiterRespectsCancellation() async throws {
    let server = BrowserOAuthCallbackServer(state: "state-1", port: 14658, path: "/auth/callback")
    try await server.start()
    let waiter = Task {
        try await server.waitForAuthorizationCode()
    }
    waiter.cancel()

    await #expect(throws: CancellationError.self) {
        try await waiter.value
    }
    await server.stop()
}

@Test
func chatGPTAuthManagerDoesNotStartBrowserBridgeWhenStoredSessionIsUsable() async throws {
    let session = makeChatGPTSession(token: "stored-token", expiresAt: Date(timeIntervalSince1970: 1_800_003_600))
    let store = InMemoryChatGPTSessionStore(session: session)
    let bridge = RecordingBrowserAuthBridge(session: makeChatGPTSession(token: "browser-token"))
    let manager = ChatGPTAuthManager(
        store: store,
        browserAuthBridge: bridge,
        now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )

    let connected = try await manager.connectViaDefaultBrowser()

    #expect(connected.accessToken == "stored-token")
    #expect(bridge.captureCount == 0)
}

@Test
func chatGPTAuthManagerSavesOAuthSession() async throws {
    let store = InMemoryChatGPTSessionStore()
    let browserSession = makeChatGPTSession(token: "browser-token", refreshToken: "refresh-token", userEmail: "browser@example.com")
    let bridge = RecordingBrowserAuthBridge(session: browserSession)
    let manager = ChatGPTAuthManager(
        store: store,
        browserAuthBridge: bridge,
        now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )

    let connected = try await manager.connectViaDefaultBrowser()
    let accessToken = try await manager.bestAvailableAccessToken()

    #expect(connected == browserSession)
    #expect(accessToken == "browser-token")
    #expect(try store.load() == browserSession)
    #expect(bridge.captureCount == 1)
}

@Test
func chatGPTAuthManagerRefreshesOAuthSessionWithRefreshToken() async throws {
    let expiredSession = makeChatGPTSession(
        token: "expired-token",
        expiresAt: Date(timeIntervalSince1970: 1_799_999_000),
        refreshToken: "refresh-token"
    )
    let refreshedSession = makeChatGPTSession(
        token: "refreshed-token",
        expiresAt: Date(timeIntervalSince1970: 1_800_003_600),
        refreshToken: "refresh-token-2"
    )
    let store = InMemoryChatGPTSessionStore(session: expiredSession)
    let bridge = RecordingBrowserAuthBridge(session: makeChatGPTSession(token: "browser-token"), refreshedSession: refreshedSession)
    let manager = ChatGPTAuthManager(
        store: store,
        browserAuthBridge: bridge,
        now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )

    let accessToken = try await manager.refreshAccessToken()

    #expect(accessToken == "refreshed-token")
    #expect(try store.load() == refreshedSession)
    #expect(bridge.refreshTokens == ["refresh-token"])
}

@Test
func chatGPTAuthManagerCoalescesConcurrentRefreshesIntoOneNetworkCall() async throws {
    let expiredSession = makeChatGPTSession(
        token: "expired-token",
        expiresAt: Date(timeIntervalSince1970: 1_799_999_000),
        refreshToken: "refresh-token"
    )
    let refreshedSession = makeChatGPTSession(
        token: "refreshed-token",
        expiresAt: Date(timeIntervalSince1970: 1_800_003_600),
        refreshToken: "refresh-token"
    )
    let bridge = DelayedRefreshBrowserAuthBridge(refreshedSession: refreshedSession)
    let manager = ChatGPTAuthManager(
        store: InMemoryChatGPTSessionStore(session: expiredSession),
        browserAuthBridge: bridge,
        now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )

    let tokens = await withTaskGroup(of: String?.self, returning: [String?].self) { group in
        for _ in 0..<20 {
            group.addTask {
                try? await manager.refreshAccessToken()
            }
        }

        var output: [String?] = []
        for await token in group {
            output.append(token)
        }
        return output
    }

    #expect(tokens.count == 20)
    #expect(tokens.allSatisfy { $0 == "refreshed-token" })
    #expect(await bridge.refreshCount() == 1)
}

@Test
func chatGPTAuthManagerDoesNotResurrectSessionAfterSignOutDuringRefresh() async throws {
    let expiredSession = makeChatGPTSession(
        token: "expired-token",
        expiresAt: Date(timeIntervalSince1970: 1_799_999_000),
        refreshToken: "refresh-token"
    )
    let refreshedSession = makeChatGPTSession(
        token: "late-token",
        expiresAt: Date(timeIntervalSince1970: 1_800_003_600),
        refreshToken: "refresh-token"
    )
    let bridge = DelayedRefreshBrowserAuthBridge(
        refreshedSession: refreshedSession,
        delayNanoseconds: 250_000_000
    )
    let store = InMemoryChatGPTSessionStore(session: expiredSession)
    let manager = ChatGPTAuthManager(
        store: store,
        browserAuthBridge: bridge,
        now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )

    let refreshTask = Task {
        try? await manager.refreshAccessToken()
    }
    try await Task.sleep(nanoseconds: 30_000_000)
    try manager.signOut()
    _ = await refreshTask.value

    #expect(try store.load() == nil)
    #expect(manager.authSnapshot().state == .signedOut)
}

private final class RecordingBrowserAuthBridge: BrowserAuthBridging, @unchecked Sendable {
    private let session: ChatGPTSession
    private let refreshedSession: ChatGPTSession
    private(set) var captureCount = 0
    private(set) var refreshTokens: [String] = []

    init(session: ChatGPTSession, refreshedSession: ChatGPTSession? = nil) {
        self.session = session
        self.refreshedSession = refreshedSession ?? session
    }

    func snapshot() -> BrowserBridgeSnapshot {
        .available
    }

    func captureSession(now: Date) async throws -> ChatGPTSession {
        captureCount += 1
        return session
    }

    func refreshSession(refreshToken: String, now: Date) async throws -> ChatGPTSession {
        refreshTokens.append(refreshToken)
        return refreshedSession
    }
}

private final class DelayedRefreshBrowserAuthBridge: BrowserAuthBridging, @unchecked Sendable {
    private let refreshedSession: ChatGPTSession
    private let delayNanoseconds: UInt64
    private let counter = RefreshCounter()

    init(
        refreshedSession: ChatGPTSession,
        delayNanoseconds: UInt64 = 80_000_000
    ) {
        self.refreshedSession = refreshedSession
        self.delayNanoseconds = delayNanoseconds
    }

    func snapshot() -> BrowserBridgeSnapshot {
        .available
    }

    func captureSession(now: Date) async throws -> ChatGPTSession {
        refreshedSession
    }

    func refreshSession(refreshToken: String, now: Date) async throws -> ChatGPTSession {
        await counter.increment()
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        return refreshedSession
    }

    func refreshCount() async -> Int {
        await counter.value
    }
}

private actor RefreshCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private func get(_ urlString: String) async throws -> Int {
    let (_, response) = try await URLSession.shared.data(from: URL(string: urlString)!)
    return try #require(response as? HTTPURLResponse).statusCode
}

private func makeChatGPTSession(
    token: String,
    expiresAt: Date? = Date(timeIntervalSince1970: 1_800_003_600),
    refreshToken: String? = nil,
    userEmail: String? = nil
) -> ChatGPTSession {
    ChatGPTSession(
        accessToken: token,
        accessTokenExpiresAt: expiresAt,
        refreshToken: refreshToken,
        idToken: nil,
        cookies: [],
        userEmail: userEmail,
        updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
}
