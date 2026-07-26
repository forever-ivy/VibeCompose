import AppKit
import CryptoKit
import Foundation
import Network
import Security

enum BrowserBridgeState: Sendable, Equatable {
    case available
    case waiting
    case connected
    case failed(String)
}

struct BrowserBridgeSnapshot: Sendable, Equatable {
    var state: BrowserBridgeState
    var detail: String

    static let available = BrowserBridgeSnapshot(
        state: .available,
        detail: L10n.text("Use the default browser ChatGPT OAuth flow to connect VibeCompose.")
    )
}

enum BrowserAuthBridgeError: LocalizedError, Equatable {
    case timedOut
    case invalidRequest
    case duplicateCallbackParameter(String)
    case invalidState
    case missingAuthorizationCode
    case listenerFailed(String)
    case tokenExchangeFailed(String)
    case invalidTokenResponse

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return L10n.text("Browser login timed out. Finish the ChatGPT authorization page and try again if it expired.")
        case .invalidRequest:
            return L10n.text("Browser login sent an invalid callback.")
        case .duplicateCallbackParameter(let name):
            return L10n.format("Browser login sent the callback parameter %@ more than once.", name)
        case .invalidState:
            return L10n.text("Browser login was rejected because the one-time state did not match.")
        case .missingAuthorizationCode:
            return L10n.text("Browser login finished without an authorization code.")
        case .listenerFailed(let message):
            return L10n.format("Browser login callback server could not start: %@", message)
        case .tokenExchangeFailed(let message):
            return L10n.format("ChatGPT OAuth token exchange failed: %@", message)
        case .invalidTokenResponse:
            return L10n.text("ChatGPT OAuth did not return a usable access token.")
        }
    }
}

protocol BrowserAuthBridging: Sendable {
    func snapshot() -> BrowserBridgeSnapshot
    func captureSession(now: Date) async throws -> ChatGPTSession
    func refreshSession(refreshToken: String, now: Date) async throws -> ChatGPTSession
}

final class BrowserAuthBridge: BrowserAuthBridging, @unchecked Sendable {
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let issuer = "https://auth.openai.com"
    private static let callbackPort: UInt16 = 1455
    private static let callbackPath = "/auth/callback"
    private static let originator = "vibecompose_desktop"
    private static let scopes = "openid profile email offline_access"

    private let timeoutNanoseconds: UInt64
    private let opener: @MainActor @Sendable (URL) -> Void
    private let dataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let nowProvider: @Sendable () -> Date
    private let lock = NSLock()
    private var bridgeSnapshot = BrowserBridgeSnapshot.available

    init(
        timeoutSeconds: TimeInterval = 600,
        now: @escaping @Sendable () -> Date = Date.init,
        opener: @escaping @MainActor @Sendable (URL) -> Void = { url in
            NSWorkspace.shared.open(url)
        },
        dataLoader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        timeoutNanoseconds = UInt64(max(1, timeoutSeconds) * 1_000_000_000)
        nowProvider = now
        self.opener = opener
        self.dataLoader = dataLoader
    }

    func snapshot() -> BrowserBridgeSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return bridgeSnapshot
    }

    func captureSession(now: Date = Date()) async throws -> ChatGPTSession {
        let state = Self.randomBase64URL(bytes: 32)
        let pkce = Self.makePKCE()
        let callbackServer = BrowserOAuthCallbackServer(
            state: state,
            port: Self.callbackPort,
            path: Self.callbackPath
        )

        do {
            try await callbackServer.start()
            setSnapshot(.waiting, L10n.text("Waiting for ChatGPT authorization in your default browser."))
            await opener(Self.authorizationURL(state: state, codeChallenge: pkce.codeChallenge))

            let code = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await callbackServer.waitForAuthorizationCode()
                }
                group.addTask { [timeoutNanoseconds] in
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    throw BrowserAuthBridgeError.timedOut
                }

                guard let result = try await group.next() else {
                    throw BrowserAuthBridgeError.timedOut
                }
                group.cancelAll()
                return result
            }

            let response = try await exchangeAuthorizationCode(code, codeVerifier: pkce.codeVerifier)
            let session = makeSession(from: response, now: nowProvider())
            setSnapshot(.connected, L10n.text("VibeCompose connected to ChatGPT via browser OAuth."))
            await callbackServer.stop()
            return session
        } catch {
            await callbackServer.stop()
            setSnapshot(.failed(error.localizedDescription), error.localizedDescription)
            throw error
        }
    }

    func refreshSession(refreshToken: String, now: Date) async throws -> ChatGPTSession {
        let response = try await refreshTokens(refreshToken)
        return makeSession(from: response, now: now)
    }

    private func exchangeAuthorizationCode(_ code: String, codeVerifier: String) async throws -> OAuthTokenResponse {
        try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": Self.clientID,
            "code_verifier": codeVerifier,
        ])
    }

    private func refreshTokens(_ refreshToken: String) async throws -> OAuthTokenResponse {
        try await requestToken([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ])
    }

    private func requestToken(_ parameters: [String: String]) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: URL(string: "\(Self.issuer)/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded(parameters).data(using: .utf8)

        let (data, response) = try await dataLoader(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BrowserAuthBridgeError.invalidTokenResponse
        }
        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let body = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw BrowserAuthBridgeError.tokenExchangeFailed("\(httpResponse.statusCode) \(body)")
        }

        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        guard tokenResponse.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw BrowserAuthBridgeError.invalidTokenResponse
        }
        return tokenResponse
    }

    private func makeSession(from response: OAuthTokenResponse, now: Date) -> ChatGPTSession {
        let accessToken = response.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatGPTSession(
            accessToken: accessToken,
            accessTokenExpiresAt: response.expiresIn.map { now.addingTimeInterval(TimeInterval($0)) }
                ?? Self.parseJWTExpiry(accessToken),
            refreshToken: response.refreshToken,
            idToken: response.idToken,
            cookies: [],
            userEmail: Self.parseUserEmail(accessToken: accessToken, idToken: response.idToken),
            updatedAt: now
        )
    }

    private static var redirectURI: String {
        "http://localhost:\(callbackPort)\(callbackPath)"
    }

    private static func authorizationURL(state: String, codeChallenge: String) -> URL {
        var components = URLComponents(string: "\(issuer)/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: originator),
        ]
        return components.url!
    }

    private static func makePKCE() -> (codeVerifier: String, codeChallenge: String) {
        let verifier = randomBase64URL(bytes: 32)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return (verifier, Data(digest).base64URLEncodedString())
    }

    private static func randomBase64URL(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func parseUserEmail(accessToken: String, idToken: String?) -> String? {
        if let email = parseJWTPayload(idToken)?["email"] as? String, !email.isEmpty {
            return email
        }
        let profile = parseJWTPayload(accessToken)?["https://api.openai.com/profile"] as? [String: Any]
        return profile?["email"] as? String
    }

    private static func parseJWTExpiry(_ token: String) -> Date? {
        guard let exp = parseJWTPayload(token)?["exp"] as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }

    private static func parseJWTPayload(_ token: String?) -> [String: Any]? {
        guard let token else {
            return nil
        }
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else {
            return nil
        }
        return Data(base64URLEncoded: String(segments[1]))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    private func formEncoded(_ parameters: [String: String]) -> String {
        parameters
            .map { key, value in
                "\(Self.percentEncode(key))=\(Self.percentEncode(value))"
            }
            .joined(separator: "&")
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func setSnapshot(_ state: BrowserBridgeState, _ detail: String) {
        lock.lock()
        bridgeSnapshot = BrowserBridgeSnapshot(state: state, detail: detail)
        lock.unlock()
        NotificationCenter.default.post(name: .chatGPTAuthStateDidChange, object: nil)
    }
}

private struct OAuthTokenResponse: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var idToken: String?
    var expiresIn: Int?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
    }
}

enum BrowserAuthorizationPage {
    private static let logoWebPBase64 = """
    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
    """

    static func successHTML() -> String {
        let language = escaped(L10n.selectedLocalization)
        let brandName = escaped(ProductIdentity.name)
        let title = escaped(L10n.text("Authorization complete"))
        let documentTitle = "\(brandName) — \(title)"
        let logoData = logoWebPBase64.replacingOccurrences(of: "\n", with: "")

        return """
        <!doctype html>
        <html lang="\(language)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <meta name="color-scheme" content="light dark">
          <meta name="theme-color" content="#F7F7F5">
          <title>\(documentTitle)</title>
          <style>
            :root {
              color-scheme: light dark;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display",
                "Helvetica Neue", sans-serif;
              font-synthesis: none;
              --surface: #f7f7f5;
              --text: #18181a;
            }

            * {
              box-sizing: border-box;
            }

            html {
              min-width: 20rem;
              background: var(--surface);
            }

            body {
              min-height: 100vh;
              min-height: 100svh;
              margin: 0;
              display: grid;
              place-items: center;
              overflow-x: hidden;
              position: relative;
              color: var(--text);
              background: var(--surface);
            }

            .scene {
              width: min(100%, 42rem);
              padding:
                max(2rem, env(safe-area-inset-top))
                clamp(1.5rem, 6vw, 4rem)
                max(2rem, env(safe-area-inset-bottom));
              position: relative;
              z-index: 1;
              text-align: center;
            }

            .brand-lockup {
              width: fit-content;
              display: flex;
              flex-direction: column;
              align-items: center;
              gap: 1rem;
              margin: 0 auto clamp(3rem, 8vh, 4.5rem);
              animation: settle-in 420ms cubic-bezier(0.16, 1, 0.3, 1) both;
            }

            .logo-shell {
              width: clamp(5rem, 8vw, 6.25rem);
              height: clamp(5rem, 8vw, 6.25rem);
              padding: 0.32rem;
              display: grid;
              place-items: center;
              overflow: hidden;
              border: 1px solid rgba(24, 24, 26, 0.08);
              border-radius: clamp(1.5rem, 2.4vw, 1.9rem);
              background: white;
              box-shadow:
                0 0.55rem 1.8rem rgba(24, 24, 26, 0.09),
                0 1px 2px rgba(24, 24, 26, 0.06);
            }

            .brand-mark {
              display: block;
              width: 100%;
              height: 100%;
              border-radius: clamp(1.18rem, 2vw, 1.5rem);
            }

            .brand-name {
              color: var(--text);
              font-size: clamp(1.15rem, 2.4vw, 1.35rem);
              font-weight: 650;
              letter-spacing: -0.025em;
            }

            h1 {
              max-width: 14ch;
              margin: 0 auto;
              color: var(--text);
              font-size: clamp(2.35rem, 6.5vw, 4rem);
              font-weight: 620;
              letter-spacing: -0.05em;
              line-height: 1;
              text-wrap: balance;
              animation: settle-in 440ms 90ms cubic-bezier(0.16, 1, 0.3, 1) both;
            }

            @keyframes settle-in {
              from {
                opacity: 0;
                transform: translateY(0.4rem);
              }
              to {
                opacity: 1;
                transform: translateY(0);
              }
            }

            @media (max-width: 38rem) {
              .brand-lockup {
                margin-bottom: clamp(2.6rem, 7vh, 3.5rem);
              }

              .scene {
                padding-inline: 1.4rem;
              }
            }

            @media (max-height: 39rem) and (min-width: 38rem) {
              .brand-lockup {
                margin-bottom: 2.2rem;
              }

              h1 {
                font-size: clamp(2.35rem, 8vh, 3.5rem);
              }
            }

            @media (prefers-color-scheme: dark) {
              :root {
                --surface: #111113;
                --text: #f2f2f3;
              }

              .logo-shell {
                border-color: rgba(255, 255, 255, 0.16);
                box-shadow: 0 0.35rem 1.2rem rgba(0, 0, 0, 0.24);
              }
            }

            @media (prefers-reduced-motion: reduce) {
              *,
              *::before,
              *::after {
                scroll-behavior: auto !important;
                animation-duration: 0.01ms !important;
                animation-iteration-count: 1 !important;
              }
            }
          </style>
        </head>
        <body>
          <main class="scene" aria-labelledby="page-title">
            <div class="brand-lockup">
              <span class="logo-shell" aria-hidden="true">
                <img class="brand-mark" src="data:image/webp;base64,\(logoData)" alt="" width="56" height="56">
              </span>
              <span class="brand-name">\(brandName)</span>
            </div>

            <section role="status" aria-live="polite" aria-labelledby="page-title">
              <h1 id="page-title">\(title)</h1>
            </section>
          </main>
        </body>
        </html>
        """
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

final class BrowserOAuthCallbackServer: @unchecked Sendable {
    private let state: String
    private let port: UInt16
    private let path: String
    private let queue = DispatchQueue(label: ProductIdentity.oauthCallbackQueueLabel)
    private let lock = NSLock()
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?
    private var completedResult: Result<String, Error>?

    init(state: String, port: UInt16, path: String) {
        self.state = state
        self.port = port
        self.path = path
    }

    func start() async throws {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let box = VoidContinuationBox(continuation: continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    box.resume(.success(()))
                case .failed(let error):
                    box.resume(.failure(BrowserAuthBridgeError.listenerFailed(error.localizedDescription)))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        }
    }

    func waitForAuthorizationCode() async throws -> String {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let completedResult {
                    lock.unlock()
                    continuation.resume(with: completedResult)
                    return
                }
                if self.continuation != nil {
                    lock.unlock()
                    continuation.resume(throwing: BrowserAuthBridgeError.invalidRequest)
                    return
                }
                self.continuation = continuation
                lock.unlock()
            }
        }, onCancel: {
            cancelWaitingForAuthorization()
        })
    }

    func stop() async {
        listener?.cancel()
        listener = nil
        complete(.failure(CancellationError()))
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.complete(.failure(error))
                self.respond(to: connection, status: 400, body: L10n.text("Bad Request"))
                return
            }
            do {
                let request = try HTTPRequest(data: data ?? Data())
                switch try self.parseCode(from: request) {
                case .code(let code):
                    self.respond(
                        to: connection,
                        status: 200,
                        body: BrowserAuthorizationPage.successHTML(),
                        contentType: "text/html; charset=utf-8"
                    )
                    self.complete(.success(code))
                case .oauthFailure(let error):
                    self.respond(to: connection, status: 400, body: error.localizedDescription)
                    self.complete(.failure(error))
                }
            } catch {
                self.respond(to: connection, status: 400, body: error.localizedDescription)
            }
        }
    }

    private enum CallbackResult {
        case code(String)
        case oauthFailure(Error)
    }

    private func parseCode(from request: HTTPRequest) throws -> CallbackResult {
        guard request.method == "GET", request.path == path else {
            throw BrowserAuthBridgeError.invalidRequest
        }
        guard request.query["state"] == state else {
            throw BrowserAuthBridgeError.invalidState
        }
        if let error = request.query["error"] {
            let detail = request.query["error_description"] ?? error
            return .oauthFailure(BrowserAuthBridgeError.tokenExchangeFailed(detail))
        }
        guard let code = request.query["code"], !code.isEmpty else {
            throw BrowserAuthBridgeError.missingAuthorizationCode
        }
        return .code(code)
    }

    private func respond(
        to connection: NWConnection,
        status: Int,
        body: String,
        contentType: String = "text/plain; charset=utf-8"
    ) {
        let reason = status == 200 ? "OK" : "Bad Request"
        let bodyData = Data(body.utf8)
        var response = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Length: \(bodyData.count)",
            "Content-Type: \(contentType)",
            "Cache-Control: no-store",
            "Content-Security-Policy: default-src 'none'; img-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
            "Permissions-Policy: camera=(), microphone=(), geolocation=()",
            "Referrer-Policy: no-referrer",
            "X-Content-Type-Options: nosniff",
            "X-Frame-Options: DENY",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n").data(using: .utf8)!
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func complete(_ result: Result<String, Error>) {
        lock.lock()
        guard completedResult == nil else {
            lock.unlock()
            return
        }
        completedResult = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    private func cancelWaitingForAuthorization() {
        lock.lock()
        guard completedResult == nil else {
            lock.unlock()
            return
        }
        completedResult = .failure(CancellationError())
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
    }
}

private final class VoidContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: CheckedContinuation<Void, Error>
    private var didResume = false

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<Void, Error>) {
        lock.lock()
        guard didResume == false else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()
        continuation.resume(with: result)
    }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]

    init(data: Data) throws {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            throw BrowserAuthBridgeError.invalidRequest
        }
        let header = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
        guard let requestLine = header.components(separatedBy: "\r\n").first else {
            throw BrowserAuthBridgeError.invalidRequest
        }
        let requestParts = requestLine.split(separator: " ").map(String.init)
        guard requestParts.count >= 2 else {
            throw BrowserAuthBridgeError.invalidRequest
        }
        method = requestParts[0]

        let rawTarget = requestParts[1]
        let components = URLComponents(string: rawTarget)
        path = components?.path ?? rawTarget
        var parsedQuery: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            guard let value = item.value, !item.name.isEmpty else {
                throw BrowserAuthBridgeError.invalidRequest
            }
            guard parsedQuery[item.name] == nil else {
                throw BrowserAuthBridgeError.duplicateCallbackParameter(item.name)
            }
            parsedQuery[item.name] = value
        }
        query = parsedQuery
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = base64.count % 4
        if padding != 0 {
            base64 += String(repeating: "=", count: 4 - padding)
        }
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
