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
        detail: L10n.text("Use the default browser ChatGPT OAuth flow to connect OpenWhisper.")
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
    private static let originator = "openwhisper_desktop"
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
            setSnapshot(.connected, L10n.text("OpenWhisper connected to ChatGPT via browser OAuth."))
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
                        body: L10n.text("OpenWhisper authorization completed. Return to OpenWhisper.")
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

    private func respond(to connection: NWConnection, status: Int, body: String) {
        let reason = status == 200 ? "OK" : "Bad Request"
        let bodyData = Data(body.utf8)
        var response = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Length: \(bodyData.count)",
            "Content-Type: text/plain; charset=utf-8",
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
