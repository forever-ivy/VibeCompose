import AppKit
import Foundation

extension Notification.Name {
    static let chatGPTAuthStateDidChange = Notification.Name(
        "\(ProductIdentity.name)ChatGPTAuthStateDidChange"
    )
}

enum ChatGPTAuthError: LocalizedError {
    case loginRequired
    case sessionExpired
    case sessionUnavailable
    case accessTokenMissing
    case refreshFailed(String)
    case browserLoginFailed(String)

    var errorDescription: String? {
        switch self {
        case .loginRequired:
            return L10n.text("Connect ChatGPT with the default browser first.")
        case .sessionExpired:
            return L10n.text("VibeCompose's saved ChatGPT session has expired. Sign in again.")
        case .sessionUnavailable:
            return L10n.text("VibeCompose cannot currently read a usable ChatGPT session.")
        case .accessTokenMissing:
            return L10n.text("VibeCompose is signed in, but no usable ChatGPT access token is available.")
        case .refreshFailed(let message):
            return L10n.format("VibeCompose failed to refresh the ChatGPT session: %@", message)
        case .browserLoginFailed(let message):
            return L10n.format("VibeCompose browser login failed: %@", message)
        }
    }
}

enum ChatGPTAuthState: Sendable, Equatable {
    case signedOut
    case ready
    case expired
    case unavailable
}

struct ChatGPTAuthSnapshot: Sendable, Equatable {
    let state: ChatGPTAuthState
    let detail: String
    let userEmail: String?
}

protocol ChatGPTAuthProviding: Sendable {
    func authSnapshot() -> ChatGPTAuthSnapshot
    func bestAvailableAccessToken() async throws -> String
    func refreshAccessToken() async throws -> String
    func prewarmSession() async
    func signOut() throws
}

final class ChatGPTAuthManager: ChatGPTAuthProviding, @unchecked Sendable {
    private final class RefreshFlight: @unchecked Sendable {
        let id: UUID
        let generation: UInt64
        let refreshToken: String
        let task: Task<ChatGPTSession, Error>

        init(
            generation: UInt64,
            refreshToken: String,
            task: Task<ChatGPTSession, Error>
        ) {
            id = UUID()
            self.generation = generation
            self.refreshToken = refreshToken
            self.task = task
        }
    }

    private let store: any ChatGPTSessionPersisting
    private let browserAuthBridge: any BrowserAuthBridging
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var cachedSession: ChatGPTSession?
    private var sessionGeneration: UInt64 = 0
    private var refreshFlight: RefreshFlight?

    init(
        store: any ChatGPTSessionPersisting = KeychainChatGPTSessionStore(),
        browserAuthBridge: any BrowserAuthBridging = BrowserAuthBridge(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.browserAuthBridge = browserAuthBridge
        self.now = now
        cachedSession = try? store.load()
    }

    func authSnapshot() -> ChatGPTAuthSnapshot {
        do {
            guard let session = try loadSession() else {
                return ChatGPTAuthSnapshot(
                    state: .signedOut,
                    detail: L10n.text("Use Browser Login in VibeCompose Settings before recording."),
                    userEmail: nil
                )
            }
            if session.tokenIsUsable(now: now()) {
                return ChatGPTAuthSnapshot(
                    state: .ready,
                    detail: L10n.text("VibeCompose has its own ChatGPT session and can transcribe without Codex."),
                    userEmail: session.userEmail
                )
            }
            return ChatGPTAuthSnapshot(
                state: .expired,
                detail: L10n.text("VibeCompose has a saved ChatGPT session, but it needs refresh or sign-in again."),
                userEmail: session.userEmail
            )
        } catch {
            return ChatGPTAuthSnapshot(
                state: .unavailable,
                detail: error.localizedDescription,
                userEmail: nil
            )
        }
    }

    func bestAvailableAccessToken() async throws -> String {
        if let session = try loadSession(), session.tokenIsUsable(now: now()) {
            return session.accessToken
        }
        return try await refreshAccessToken()
    }

    func refreshAccessToken() async throws -> String {
        guard let session = try loadSession() else {
            throw ChatGPTAuthError.loginRequired
        }
        guard let refreshToken = session.refreshToken, refreshToken.isEmpty == false else {
            throw ChatGPTAuthError.sessionExpired
        }

        let flight = try makeOrReuseRefreshFlight(
            refreshToken: refreshToken,
            now: now()
        )

        do {
            let refreshed = try await flight.task.value
            return try commitRefreshResult(refreshed, for: flight)
        } catch let error as ChatGPTAuthError {
            if case .loginRequired = error {
                try? signOut()
            }
            clearFailedRefreshFlight(flight)
            throw error
        } catch {
            clearFailedRefreshFlight(flight)
            throw ChatGPTAuthError.refreshFailed(error.localizedDescription)
        }
    }

    func connectViaDefaultBrowser() async throws -> ChatGPTSession {
        if let session = try loadSession(), session.tokenIsUsable(now: now()) {
            return session
        }

        let generation = currentGeneration()
        do {
            let session = try await browserAuthBridge.captureSession(now: now())
            return try commitCapturedSession(session, expectedGeneration: generation)
        } catch {
            throw ChatGPTAuthError.browserLoginFailed(error.localizedDescription)
        }
    }

    func browserBridgeSnapshot() -> BrowserBridgeSnapshot {
        browserAuthBridge.snapshot()
    }

    func prewarmSession() async {
        _ = try? await bestAvailableAccessToken()
    }

    func signOut() throws {
        lock.lock()
        sessionGeneration &+= 1
        refreshFlight?.task.cancel()
        refreshFlight = nil
        cachedSession = nil
        do {
            try store.delete()
        } catch {
            lock.unlock()
            throw error
        }
        lock.unlock()
        NotificationCenter.default.post(name: .chatGPTAuthStateDidChange, object: nil)
    }

    private func loadSession() throws -> ChatGPTSession? {
        lock.lock()
        if let cachedSession {
            lock.unlock()
            return cachedSession
        }
        lock.unlock()

        let session = try store.load()
        lock.lock()
        cachedSession = session
        lock.unlock()
        return session
    }

    private func currentGeneration() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return sessionGeneration
    }

    private func makeOrReuseRefreshFlight(
        refreshToken: String,
        now: Date
    ) throws -> RefreshFlight {
        lock.lock()
        defer { lock.unlock() }

        if let refreshFlight {
            return refreshFlight
        }

        let task = Task.detached { [browserAuthBridge, refreshToken, now] in
            try await browserAuthBridge.refreshSession(
                refreshToken: refreshToken,
                now: now
            )
        }
        let flight = RefreshFlight(
            generation: sessionGeneration,
            refreshToken: refreshToken,
            task: task
        )
        refreshFlight = flight
        return flight
    }

    private func commitRefreshResult(
        _ result: ChatGPTSession,
        for flight: RefreshFlight
    ) throws -> String {
        var refreshed = result
        if refreshed.refreshToken == nil {
            refreshed.refreshToken = flight.refreshToken
        }

        lock.lock()

        if let refreshFlight, refreshFlight.id == flight.id {
            guard sessionGeneration == flight.generation,
                  cachedSession?.refreshToken == flight.refreshToken
            else {
                self.refreshFlight = nil
                lock.unlock()
                throw ChatGPTAuthError.sessionExpired
            }

            do {
                try store.save(refreshed)
            } catch {
                self.refreshFlight = nil
                lock.unlock()
                throw error
            }
            cachedSession = refreshed
            sessionGeneration &+= 1
            self.refreshFlight = nil
            lock.unlock()
            NotificationCenter.default.post(name: .chatGPTAuthStateDidChange, object: nil)
            return refreshed.accessToken
        }

        guard sessionGeneration > flight.generation,
              cachedSession?.accessToken == refreshed.accessToken
        else {
            lock.unlock()
            throw ChatGPTAuthError.sessionExpired
        }
        let accessToken = cachedSession?.accessToken ?? refreshed.accessToken
        lock.unlock()
        return accessToken
    }

    private func clearFailedRefreshFlight(_ flight: RefreshFlight) {
        lock.lock()
        if refreshFlight?.id == flight.id {
            refreshFlight = nil
        }
        lock.unlock()
    }

    private func commitCapturedSession(
        _ session: ChatGPTSession,
        expectedGeneration: UInt64
    ) throws -> ChatGPTSession {
        lock.lock()

        guard sessionGeneration == expectedGeneration else {
            lock.unlock()
            throw ChatGPTAuthError.sessionUnavailable
        }
        refreshFlight?.task.cancel()
        refreshFlight = nil
        do {
            try store.save(session)
        } catch {
            lock.unlock()
            throw error
        }
        cachedSession = session
        sessionGeneration &+= 1
        lock.unlock()
        NotificationCenter.default.post(name: .chatGPTAuthStateDidChange, object: nil)
        return session
    }
}
